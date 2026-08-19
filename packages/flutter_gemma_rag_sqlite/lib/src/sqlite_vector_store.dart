import 'dart:ffi';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:flutter_gemma_rag_sqlite/src/filter_to_vec0.dart';

/// On-device RAG vector store backed by sqlite3 (dart:ffi) + the `sqlite-vec`
/// (`vec0`) virtual table. Native platforms only; web uses
/// [WebSqliteVectorStore]. Implements flutter_gemma's [VectorStoreRepository].
///
/// KNN runs inside SQLite (C via `sqlite-vec`) — there is no Dart brute-force
/// or in-memory index. The `vec0` table carries the embedding plus auxiliary
/// `+content`/`+metadata` columns and one typed column per declared
/// [FilterField], so `searchSimilar` returns the document and its metadata in a
/// single query and pushes [Filter] predicates down to the engine.
class SqliteVectorStore implements VectorStoreRepository {
  Database? _db;
  int? _detectedDimension;
  bool _isInitialized = false;

  /// vec0 virtual table holding `id TEXT PRIMARY KEY`, `embedding float[D]`,
  /// the auxiliary `+content`/`+metadata` columns, and one typed column per
  /// declared filter field.
  static const String _tableName = 'vec_documents';

  /// Declared filterable-metadata schema (via [configure]). Empty by default,
  /// so callers that never declare a schema get a table with no filter columns
  /// and the historical "filters are a safe no-op" behaviour.
  FilterSchema _filterSchema = const FilterSchema();

  @override
  @Deprecated('No-op since vector search moved into SQLite; removed in 2.0')
  bool get enableHnsw => false;

  @override
  @Deprecated('No-op since vector search moved into SQLite; removed in 2.0')
  set enableHnsw(bool value) {}

  @override
  bool get isInitialized => _isInitialized;

  @override
  FilterSchema get filterSchema => _filterSchema;

  @override
  void configure(FilterSchema schema) {
    // Validate here, not only in FilterField's assert: asserts are stripped in
    // release, and a field name read from config at runtime would otherwise
    // reach the storage layer unchecked. Rejecting at configure() points the
    // error at the schema the developer wrote rather than at a query built
    // from it much later.
    // Core checks what is wrong on every backend; this store checks what
    // ITS storage cannot take. Splitting them keeps one backend's grammar
    // out of a package that has no backends.
    FilterField.validateSchema(schema);
    for (final field in schema.fields) {
      FilterToVec0.validateFieldName(field.name);
    }
    _filterSchema = schema;
  }

  // === sqlite-vec (vec0) extension loading ===

  /// Loaded once per process: registering the `vec0` virtual-table module is a
  /// global sqlite3 operation that must happen BEFORE any database is opened.
  static bool _vec0Loaded = false;

  /// Resolves the prebuilt `vec0` loadable extension and registers its static
  /// entrypoint with sqlite3. NOT runtime `SELECT load_extension` (the bundled
  /// sqlite3 omits it for security) — instead [DynamicLibrary.open] +
  /// [Sqlite3.ensureExtensionLoaded] with the `sqlite3_vec_init` symbol, the
  /// path proven by `test/vec0_text_pk_test.dart`.
  static void _ensureVec0Loaded() {
    if (_vec0Loaded) return;
    final lib = DynamicLibrary.open(_resolveVec0Path());
    sqlite3.ensureExtensionLoaded(
      SqliteExtension.inLibrary(lib, 'sqlite3_vec_init'),
    );
    _vec0Loaded = true;
  }

  /// Host-test override for the loadable's path; null in production.
  ///
  /// The qdrant store already had this (`QdrantEdgeClient.debugOverrideDylibPath`)
  /// and vec0 had only the environment variable, so a test could hand one store
  /// its library and had to configure the other through the process environment
  /// — which meant `tool/test_all.sh` had to know about it, and a plain
  /// `flutter test` in this package failed on a dlopen for no visible reason.
  /// Same mechanism on both sides now.
  ///
  /// Setting it after the first load has no effect: sqlite3 caches the
  /// extension.
  @visibleForTesting
  static String? debugOverrideDylibPath;

  /// Path to the `vec0` loadable extension. Host tests set `$VEC0_DYLIB`; in a
  /// real app the per-platform `vec0.<ext>` is bundled by `hook/build.dart`
  /// (Native Assets) and resolved by its bundled filename — the same mechanism
  /// qdrant-edge uses.
  static String _resolveVec0Path() {
    final testOverride = debugOverrideDylibPath;
    if (testOverride != null && testOverride.isNotEmpty) return testOverride;

    final override = Platform.environment['VEC0_DYLIB'];
    if (override != null && override.isNotEmpty) return override;

    if (Platform.isIOS) {
      // Native Assets bundles dylibs into Frameworks/ inside the app.
      return '@executable_path/Frameworks/vec0.framework/vec0';
    }
    if (Platform.isMacOS) {
      return 'vec0.framework/vec0';
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libvec0.so';
    }
    if (Platform.isWindows) {
      return 'vec0.dll';
    }
    throw UnsupportedError(
      'sqlite-vec is not available on ${Platform.operatingSystem}',
    );
  }

  @override
  Future<void> initialize(String databasePath) async {
    try {
      _ensureVec0Loaded();
      // Ensure the parent directory exists before sqlite3 opens the file.
      // Sandboxed desktop temp paths (macOS `~/Library/Containers/.../Caches`)
      // and fresh installs may not have it yet, and sqlite3 will not create
      // it — it returns "unable to open database file" (code 14). Mirrors the
      // qdrant store's parent guard.
      final parent = File(databasePath).parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _db?.close();
      _db = sqlite3.open(databasePath);
      _isInitialized = true;
      _detectDimensionFromExistingTable();
    } catch (e) {
      throw VectorStoreException('Failed to initialize vector store', e);
    }
  }

  /// When re-opening a database that already holds a populated `vec_documents`
  /// table, learn the dimension from a stored embedding so subsequent adds and
  /// queries validate against it (no lazy re-create on the existing table).
  void _detectDimensionFromExistingTable() {
    final exists = _db!.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [_tableName],
    );
    if (exists.isEmpty) return;
    final row = _db!.select('SELECT embedding FROM $_tableName LIMIT 1');
    if (row.isEmpty) return;
    final blob = row.first['embedding'] as Uint8List;
    _detectedDimension = blob.length ~/ 4; // float32 = 4 bytes
  }

  /// Lazily creates the vec0 virtual table once the embedding dimension is
  /// known. Declares one typed metadata column per [FilterField] (the ONLY
  /// columns a vec0 KNN `WHERE` can filter on), plus the auxiliary
  /// `+content`/`+metadata` columns returned at SELECT but not filterable.
  void _createTable(int dimension) {
    final columns = <String>[
      'id TEXT PRIMARY KEY',
      // distance_metric=cosine so KNN `distance` is cosine distance in [0,2]
      // (0 = identical) → similarity = 1 - distance, matching the contract.
      // Without it vec0 defaults to L2, breaking the 1 - distance convention.
      'embedding float[$dimension] distance_metric=cosine',
    ];
    for (final field in _filterSchema.fields) {
      // Deliberately bare, never quoted: sqlite-vec parses this DDL with its
      // own tokenizer, which has no quoted-identifier form — `"x"`, `[x]` and
      // backticks all fail with `vec0 constructor error: Could not parse`.
      // FilterField's constructor is what guarantees the name is a legal bare
      // identifier here (and that it carries no comma, which would silently
      // declare a second column).
      columns.add('${field.name} ${_vec0ColumnType(field.type)}');
    }
    // Auxiliary (unindexed) columns: round-trip content + raw metadata JSON.
    columns.add('+content TEXT');
    columns.add('+metadata TEXT');
    _db!.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $_tableName USING vec0(\n'
      '  ${columns.join(',\n  ')}\n'
      ')',
    );
  }

  /// vec0 declared-column SQL type for a [FilterFieldType]. Booleans map to
  /// INTEGER because [FilterToVec0] binds bool predicates as `0`/`1`.
  static String _vec0ColumnType(FilterFieldType type) => switch (type) {
    FilterFieldType.string => 'TEXT',
    FilterFieldType.number => 'FLOAT',
    FilterFieldType.bool => 'INTEGER',
  };

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // Dimension validation / lazy table creation on the first add.
    if (_detectedDimension == null) {
      _detectedDimension = embedding.length;
      _createTable(embedding.length);
    } else if (embedding.length != _detectedDimension) {
      throw ArgumentError(
        'Embedding dimension mismatch: expected $_detectedDimension, '
        'got ${embedding.length}',
      );
    }

    final blob = _embeddingToBlob(embedding);

    // Promote declared filter fields into their typed columns (decoded from the
    // raw metadata JSON). Absent / unparseable metadata leaves them NULL.
    // Shared with the web arm — see FilterToVec0.declaredColumnValues.
    final filterValues = FilterToVec0.declaredColumnValues(
      metadata,
      _filterSchema,
    );

    final columnNames = <String>['id', 'embedding'];
    final placeholders = <String>['?', '?'];
    final binds = <Object?>[id, blob];
    for (final field in _filterSchema.fields) {
      // Quoted here (SQLite parses this statement) but NOT in the vec0 DDL
      // above — see FilterToVec0.quoteColumn.
      columnNames.add(FilterToVec0.quoteColumn(field.name));
      placeholders.add('?');
      binds.add(filterValues[field.name]);
    }
    columnNames.add('content');
    placeholders.add('?');
    binds.add(content);
    columnNames.add('metadata');
    placeholders.add('?');
    binds.add(metadata);

    // vec0 does NOT honor `INSERT OR REPLACE`/UPSERT conflict resolution on its
    // declared primary key — a duplicate id raises a UNIQUE violation instead
    // of replacing. Emulate upsert with delete-then-insert.
    _db!.execute('DELETE FROM $_tableName WHERE id = ?', [id]);
    _db!.execute(
      'INSERT INTO $_tableName (${columnNames.join(', ')}) '
      'VALUES (${placeholders.join(', ')})',
      binds,
    );
  }

  @override
  Future<void> removeDocument({required String id}) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    if (_detectedDimension == null) return; // table not created yet → no-op
    _db!.execute('DELETE FROM $_tableName WHERE id = ?', [id]);
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    if (_detectedDimension == null) {
      // No documents added yet → nothing to retrieve, no table to query.
      return const [];
    }
    if (queryEmbedding.length != _detectedDimension) {
      throw ArgumentError(
        'Query dimension mismatch: expected $_detectedDimension, '
        'got ${queryEmbedding.length}',
      );
    }

    final translated = FilterToVec0.translate(filter, _filterSchema);
    // An unsatisfiable filter has one answer and it costs nothing to give:
    // an empty result. Without this the over-fetch loop below would grow the
    // candidate set to the 16x cap looking for rows that cannot exist, and
    // then log that the result "may be truncated" — a warning about a
    // shortfall that is the correct and complete answer.
    if (translated.matchesNothing) return const [];
    final whereExtra = translated.whereSql.isEmpty
        ? ''
        : ' AND ${translated.whereSql}';

    // vec0's KNN takes a conjunction of single-column comparisons and nothing
    // else. A filter it cannot accept — a cross-column OR, a CASE over a FLOAT
    // set, a NOT BETWEEN — is not rejected: SQLite quietly evaluates it AFTER
    // vec0 has already chosen its k rows. That is a post-filter over a global
    // top-k, and it can only ever return FEWER than k, never reach past them.
    // Measured: two conditions on different columns at k=2, with the two
    // nearest matching neither, returned zero rows while three documents
    // satisfied the filter.
    //
    // So ask vec0 for more and keep doubling until k survive — bounded,
    // because unbounded growth degenerates to a full scan. Past the cap we
    // return what we have and say the result is short.
    var fetch = topK;
    int? totalRows;
    final results = <RetrievalResult>[];
    var rowsReturned = 0;

    while (true) {
      final rows = _db!.select(
        'SELECT id, content, metadata, distance FROM $_tableName '
        'WHERE embedding MATCH ? AND k = ?$whereExtra '
        'ORDER BY distance',
        [_embeddingToBlob(queryEmbedding), fetch, ...translated.binds],
      );
      rowsReturned = rows.length;

      results.clear();
      for (final row in rows) {
        // vec0 returns cosine DISTANCE; similarity = 1 - distance.
        final similarity = 1.0 - (row['distance'] as num).toDouble();
        // Rows arrive ordered by distance, so this can only trim the tail —
        // it is NOT a reason to fetch more (see FilterToVec0.shouldOverFetch).
        if (similarity < threshold) break;
        results.add(
          RetrievalResult(
            id: row['id'] as String,
            content: row['content'] as String? ?? '',
            similarity: similarity,
            metadata: row['metadata'] as String?,
          ),
        );
      }

      if (translated.whereSql.isEmpty) break;
      totalRows ??=
          _db!.select('SELECT COUNT(*) AS c FROM $_tableName').first['c']
              as int;
      if (!FilterToVec0.shouldOverFetch(
        rowsReturned: rowsReturned,
        topK: topK,
        fetch: fetch,
        totalRows: totalRows,
      )) {
        break;
      }
      fetch *= 2;
    }

    // Only a filter shortfall is worth reporting: a short result because the
    // threshold trimmed the tail, or because the table simply holds fewer
    // matches, is not something the caller can fix by narrowing the filter.
    final hitTheCap =
        totalRows != null &&
        fetch < totalRows &&
        fetch >= topK * FilterToVec0.maxOverFetchFactor;
    if (rowsReturned < topK && hitTheCap) {
      gemmaLog(
        '[SqliteVectorStore] searchSimilar found $rowsReturned of the '
        'requested $topK after over-fetching '
        '${topK * FilterToVec0.maxOverFetchFactor} candidates. This filter '
        'cannot be pushed into the KNN scan (a cross-column OR, a set over a '
        'number column, or a negated two-sided range), so matches beyond that '
        'window are unreachable. Narrow the filter or lower topK.',
      );
    }

    return results.length > topK ? results.sublist(0, topK) : results;
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    final count = _detectedDimension == null
        ? 0
        : (_db!
                  .select('SELECT COUNT(*) as count FROM $_tableName')
                  .first['count']
              as int);
    return VectorStoreStats(
      documentCount: count,
      vectorDimension: _detectedDimension ?? 0,
    );
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    if (_detectedDimension != null) {
      // vec0 bakes the dimension into the DDL; drop the table so the next add
      // re-detects the dimension and recreates it (resets the schema cleanly).
      _db!.execute('DROP TABLE IF EXISTS $_tableName');
    }
    _detectedDimension = null;
  }

  @override
  Future<void> close() async {
    if (!_isInitialized) return;
    _db?.close();
    _db = null;
    _isInitialized = false;
    _detectedDimension = null;
  }

  // === BLOB Encoding (float32 little-endian, same as Kotlin/Swift) ===

  static Uint8List _embeddingToBlob(List<double> embedding) {
    final buffer = ByteData(embedding.length * 4);
    for (int i = 0; i < embedding.length; i++) {
      buffer.setFloat32(i * 4, embedding[i].toDouble(), Endian.little);
    }
    return buffer.buffer.asUint8List();
  }
}
