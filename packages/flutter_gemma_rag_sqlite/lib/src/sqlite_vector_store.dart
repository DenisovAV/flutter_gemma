import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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
  void configure(FilterSchema schema) => _filterSchema = schema;

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

  /// Path to the `vec0` loadable extension. Host tests set `$VEC0_DYLIB`; in a
  /// real app the per-platform `vec0.<ext>` is bundled by `hook/build.dart`
  /// (Native Assets) and resolved by its bundled filename — the same mechanism
  /// qdrant-edge uses.
  static String _resolveVec0Path() {
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
    final filterValues = _extractFilterValues(metadata);

    final columnNames = <String>['id', 'embedding'];
    final placeholders = <String>['?', '?'];
    final binds = <Object?>[id, blob];
    for (final field in _filterSchema.fields) {
      columnNames.add(field.name);
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

  /// Decodes the declared [FilterField] values out of the raw [metadata] JSON
  /// for promotion into typed columns. Defensive: non-object or unparseable
  /// metadata yields no values (columns stay NULL), never a throw — a [Filter]
  /// on a missing field simply matches nothing (documented no-op).
  Map<String, Object?> _extractFilterValues(String? metadata) {
    if (_filterSchema.isEmpty || metadata == null) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(metadata);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map) return const {};
    final values = <String, Object?>{};
    for (final field in _filterSchema.fields) {
      if (!decoded.containsKey(field.name)) continue;
      values[field.name] = _coerceForColumn(decoded[field.name], field.type);
    }
    return values;
  }

  /// Coerces a decoded JSON [value] to the bind type its typed vec0 column
  /// expects — matching [FilterToVec0]'s predicate binds so insert and query
  /// agree: bool → `0`/`1` (INTEGER), number → `double` (a FLOAT column rejects
  /// an INTEGER bind), string → unchanged.
  static Object? _coerceForColumn(Object? value, FilterFieldType type) {
    if (value is bool) return value ? 1 : 0;
    if (type == FilterFieldType.number && value is num) return value.toDouble();
    return value;
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
    final whereExtra = translated.whereSql.isEmpty
        ? ''
        : ' AND ${translated.whereSql}';

    final rows = _db!.select(
      'SELECT id, content, metadata, distance FROM $_tableName '
      'WHERE embedding MATCH ? AND k = ?$whereExtra '
      'ORDER BY distance',
      [_embeddingToBlob(queryEmbedding), topK, ...translated.binds],
    );

    final results = <RetrievalResult>[];
    for (final row in rows) {
      // vec0 returns cosine DISTANCE; similarity = 1 - distance (1 = identical).
      final similarity = 1.0 - (row['distance'] as num).toDouble();
      if (similarity < threshold) continue;
      results.add(
        RetrievalResult(
          id: row['id'] as String,
          content: row['content'] as String? ?? '',
          similarity: similarity,
          metadata: row['metadata'] as String?,
        ),
      );
    }
    return results;
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
