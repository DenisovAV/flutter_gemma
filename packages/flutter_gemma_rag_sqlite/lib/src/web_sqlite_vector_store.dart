import 'dart:typed_data';

import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_sqlite/src/filter_to_vec0.dart';
import 'package:sqlite3/wasm.dart';

/// Web implementation of [VectorStoreRepository] backed by sqlite-vec (`vec0`)
/// running in a custom `sqlite3.wasm` (the vector extension is statically
/// linked in — see `tool/build_vec0_wasm.sh`).
///
/// **Architecture** (single engine, identical SQL dialect to the native arm):
/// ```
/// WebSqliteVectorStore (Dart, main isolate)
///         ↓  package:sqlite3/wasm.dart  (CommonSqlite3 API)
/// sqlite3.wasm  (sqlite-vec / vec0 statically linked)
///         ↓  VFS
/// OPFS → IndexedDB → in-memory  (first that works; persists across reload)
/// ```
///
/// KNN runs inside SQLite — there is no Dart brute-force and no in-memory HNSW.
/// `vec0` returns a `distance`; cosine **similarity = 1 - distance**, and the
/// `threshold`/`topK` are applied against that, exactly like the native store.
///
/// The vec0 table is created **lazily** on the first [addDocument] (so the
/// embedding dimension can be learned), or recovered from an existing table on
/// [initialize].
class WebSqliteVectorStore implements VectorStoreRepository {
  static const String _tableName = 'vec_documents';

  /// Where the custom wasm ships in the published package's web assets.
  /// Resolved relative to the app's base href at runtime.
  static const String _wasmUrl = 'rag/sqlite3.wasm';

  /// The single logical database file the persistent VFS reserves. OPFS /
  /// IndexedDB persist exactly one file; opening it is the simolus3-documented
  /// persistent path.
  static const String _dbFile = '/database';

  WasmSqlite3? _sqlite3;
  CommonDatabase? _db;
  int? _detectedDimension;
  bool _isInitialized = false;

  /// Declared filterable-metadata schema (via [configure]). Empty by default,
  /// so callers that never declare a schema keep the historical behaviour
  /// (filters are an ignored no-op).
  FilterSchema _filterSchema = const FilterSchema();

  /// No-op since vector search moved into SQLite (`vec0` does exact KNN in C).
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

  @override
  Future<void> initialize(String databasePath) async {
    try {
      _sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse(_wasmUrl));
      await _registerPersistentVfs(_sqlite3!, databasePath);

      // Close the previous handle before overwriting the field, exactly as the
      // native arm does. Without this a re-initialize dropped a live
      // connection on the floor — and because the IndexedDB VFS name is
      // derived from `databasePath`, re-initializing onto the SAME path left
      // two live connections against one persistent store.
      _db?.close();
      _db = _sqlite3!.open(_dbFile);

      // Recover the dimension from an existing vec0 table (page reload).
      _detectExistingTable();

      _isInitialized = true;
    } catch (e) {
      // Settle the state, same as the native arm. A FIRST failed initialize
      // was already honest here (the flag is set last), but a RE-initialize
      // that throws used to keep the previous run's `true` — and `_db` had
      // already been reassigned above, dropping the old handle unclosed. So
      // "isInitialized reports true after an initialize() that threw" was only
      // half fixed if this arm were left alone.
      _isInitialized = false;
      _detectedDimension = null;
      final failed = _db;
      _db = null;
      try {
        failed?.close();
      } catch (closeError) {
        gemmaLog(
          '[WebVectorStore] close() during a failed initialize: $closeError',
        );
      }
      throw VectorStoreException('Failed to initialize SQLite WASM (vec0)', e);
    }
  }

  /// Registers the best persistent VFS the current runtime supports and makes
  /// it the default, so `open(_dbFile)` persists across reloads.
  ///
  /// Preference order: OPFS (fastest, needs a dedicated worker context) →
  /// IndexedDB (works on the main isolate, where Flutter web runs) →
  /// in-memory (no persistence; last resort so the store still functions).
  Future<void> _registerPersistentVfs(
    WasmSqlite3 sqlite3,
    String databasePath,
  ) async {
    // OPFS first — only available in a dedicated web worker; on the main
    // isolate (the usual Flutter web context) it throws, so we fall through.
    try {
      final opfs = await SimpleOpfsFileSystem.loadFromStorage(databasePath);
      sqlite3.registerVirtualFileSystem(opfs, makeDefault: true);
      gemmaLog('[WebVectorStore] Using OPFS VFS for persistence');
      return;
    } catch (e) {
      gemmaLog('[WebVectorStore] OPFS VFS unavailable ($e); trying IndexedDB');
    }

    // IndexedDB — main-isolate-safe and persistent. The IndexedDB database name
    // is derived from the caller's path so distinct stores stay isolated.
    try {
      final idb = await IndexedDbFileSystem.open(
        dbName: 'flutter_gemma_rag_$databasePath',
      );
      sqlite3.registerVirtualFileSystem(idb, makeDefault: true);
      gemmaLog('[WebVectorStore] Using IndexedDB VFS for persistence');
      return;
    } catch (e) {
      gemmaLog(
        '[WebVectorStore] IndexedDB VFS unavailable ($e); '
        'falling back to in-memory (no persistence)',
      );
    }

    // Last resort: in-memory — the store works but loses all documents on page
    // reload. Logged explicitly (symmetric with the OPFS/IndexedDB branches) so
    // the durability downgrade is at least visible in debug builds. NOTE:
    // gemmaLog is stripped in release, so a production user in a restricted-
    // storage context (private browsing, partitioned storage) gets a
    // non-persistent store silently — surfacing this through a public
    // persistence-mode API is tracked as a follow-up.
    gemmaLog(
      '[WebVectorStore] Neither OPFS nor IndexedDB available — using in-memory '
      'storage. Documents will NOT persist across page reloads.',
    );
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  }

  /// Reads the embedding dimension back from an existing vec0 table, if any.
  void _detectExistingTable() {
    // Reset first, and do NOT catch — both exactly as the native arm.
    //
    // Both early returns below mean "this database tells us nothing", and
    // keeping the previous value there let a re-initialize onto a DIFFERENT,
    // empty database inherit the old dimension.
    //
    // The catch that used to sit here logged and continued, so `initialize()`
    // went on to set `_isInitialized = true` with no dimension: `searchSimilar`
    // then returned `[]`, `getStats` reported `documentCount: 0`, and
    // `removeDocument` reported success while deleting nothing — over a corpus
    // that was there and merely unreadable. Its comment claimed it would
    // "start fresh"; it dropped nothing, so the next `addDocument` ran
    // `CREATE VIRTUAL TABLE IF NOT EXISTS` against the surviving table and did
    // nothing either. An app deploying the stock `sqlite3.wasm` instead of the
    // vec0-linked one this package ships hits it on the first query, and the
    // only trace was a `gemmaLog` that does not exist in a release build.
    _detectedDimension = null;
    final exists = _db!.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [_tableName],
    );
    if (exists.isEmpty) return;
    final row = _db!.select('SELECT embedding FROM $_tableName LIMIT 1');
    if (row.isEmpty) return;
    final blob = row.first['embedding'] as Uint8List;
    _detectedDimension = blob.length ~/ 4; // float32 = 4 bytes
  }

  /// Builds the `vec0` virtual table for dimension [dimension] with one typed,
  /// filterable column per declared [FilterSchema] field, plus auxiliary
  /// (SELECT-only) `+content` / `+metadata` columns.
  void _createTable(int dimension) {
    final columns = <String>[
      'id TEXT PRIMARY KEY',
      // distance_metric=cosine so KNN `distance` is cosine distance in [0,2]
      // and `similarity = 1 - distance` holds. Without it vec0 defaults to L2,
      // breaking the similarity convention (matches the native store).
      'embedding float[$dimension] distance_metric=cosine',
      // Deliberately bare, never quoted — sqlite-vec's DDL tokenizer has no
      // quoted-identifier form. FilterField's constructor guarantees the name
      // is a legal bare identifier. Matches the native store.
      for (final field in _filterSchema.fields)
        '${field.name} ${_columnType(field.type)}',
      '+content TEXT',
      '+metadata TEXT',
    ];
    _db!.execute(
      'CREATE VIRTUAL TABLE IF NOT EXISTS $_tableName USING vec0(\n'
      '  ${columns.join(',\n  ')}\n'
      ')',
    );
  }

  static String _columnType(FilterFieldType type) => switch (type) {
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
    if (!_isInitialized || _db == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // Learn the dimension on the first add, then create the vec0 table.
    if (_detectedDimension == null) {
      _detectedDimension = embedding.length;
      _createTable(_detectedDimension!);
    } else if (embedding.length != _detectedDimension) {
      throw ArgumentError(
        'Embedding dimension mismatch: expected $_detectedDimension, '
        'got ${embedding.length}',
      );
    }

    try {
      // Shared with the native arm — see FilterToVec0.declaredColumnValues.
      // One entry per declared field, in schema order, so both arms write the
      // same column list for the same document.
      final declared = FilterToVec0.declaredColumnValues(
        metadata,
        _filterSchema,
      );
      final columns = <String>[
        'id',
        'embedding',
        // Quoted here (SQLite parses this statement) but NOT in the vec0 DDL
        // above — see FilterToVec0.quoteColumn.
        ...declared.keys.map(FilterToVec0.quoteColumn),
        'content',
        'metadata',
      ];
      // `CAST(? AS REAL)` for every declared NUMBER column — a web-only
      // necessity, not belt-and-braces.
      //
      // The shared codec already does `value.toDouble()` for a number field
      // (FilterToVec0.coerceForColumn), which is what makes the NATIVE arm bind
      // REAL. On the web that call cannot work: dart2js has one numeric type, so
      // `10.0` and `10` are the same JS number and `10.0 is int` is true.
      // package:sqlite3 then binds a whole-valued double as INTEGER and vec0
      // refuses it —
      //   Expected float for FLOAT metadata column price, received INTEGER
      // — so an ordinary `{"price": 10}` document was insertable natively and
      // not on the web. SQL is the only place the distinction still exists on
      // this platform, so SQL is where the type gets declared.
      final numberColumns = {
        for (final f in _filterSchema.fields)
          if (f.type == FilterFieldType.number) f.name,
      };
      // A non-finite declared value is the absent-field sentinel
      // (FilterToVec0.absentNumber). It goes in as a literal for the same
      // reason the WHERE clause does it: binding -Infinity on the web throws
      // "cannot be converted to a BigInt" before SQL ever sees it.
      final declaredSql = <String>[];
      final declaredBinds = <Object?>[];
      for (final entry in declared.entries) {
        final v = entry.value;
        if (numberColumns.contains(entry.key)) {
          if (v is num && !v.isFinite) {
            declaredSql.add(FilterToVec0.absentNumberSql);
            continue;
          }
          declaredSql.add('CAST(? AS REAL)');
        } else {
          declaredSql.add('?');
        }
        declaredBinds.add(v);
      }
      final placeholders = [
        '?', // id
        '?', // embedding
        ...declaredSql,
        '?', // content
        '?', // metadata
      ].join(', ');
      final binds = <Object?>[
        id,
        _embeddingToBlob(embedding),
        ...declaredBinds,
        content,
        metadata,
      ];
      // vec0 does NOT honor `INSERT OR REPLACE`/UPSERT conflict resolution on
      // its declared TEXT primary key — a duplicate id raises a UNIQUE
      // violation instead of replacing. Emulate upsert with delete-then-insert
      // (matches the native store).
      _db!.execute('DELETE FROM $_tableName WHERE id = ?', [id]);
      _db!.execute(
        'INSERT INTO $_tableName (${columns.join(', ')}) '
        'VALUES ($placeholders)',
        binds,
      );
    } catch (e) {
      throw VectorStoreException('Failed to add document', e);
    }
  }

  @override
  Future<void> removeDocument({required String id}) async {
    if (!_isInitialized || _db == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    try {
      // No-op when the table doesn't exist yet (nothing was ever added) or the
      // id is absent — DELETE simply matches zero rows.
      if (_detectedDimension == null) return;
      _db!.execute('DELETE FROM $_tableName WHERE id = ?', [id]);
    } catch (e) {
      throw VectorStoreException('Failed to remove document', e);
    }
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async {
    if (!_isInitialized || _db == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // No table yet → no documents → empty result (never throws on filter).
    if (_detectedDimension == null) return const [];

    if (queryEmbedding.length != _detectedDimension) {
      throw ArgumentError(
        'Query dimension mismatch: expected $_detectedDimension, '
        'got ${queryEmbedding.length}',
      );
    }

    try {
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

      // Over-fetch exactly as the native arm does. Both arms share
      // FilterToVec0, so the SQL and binds are byte-identical — and this loop
      // was missing here, which meant the same filter answered `[d4]` on
      // native and `[]` on web. See the native store for why an unpushable
      // filter needs it at all.
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
          final similarity = 1.0 - (row['distance'] as num).toDouble();
          // Ordered by distance, so this only trims the tail — not a reason to
          // fetch more (see FilterToVec0.shouldOverFetch).
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

      return results.length > topK ? results.sublist(0, topK) : results;
    } catch (e) {
      throw VectorStoreException('Search failed', e);
    }
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized || _db == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      final count = _detectedDimension == null
          ? 0
          : (_db!
                    .select('SELECT COUNT(*) AS count FROM $_tableName')
                    .first['count']
                as int);
      return VectorStoreStats(
        documentCount: count,
        vectorDimension: _detectedDimension ?? 0,
      );
    } catch (e) {
      throw VectorStoreException('Failed to get stats', e);
    }
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized || _db == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    try {
      // Drop the table so a re-add can re-learn the dimension / re-apply a new
      // schema (vec0 bakes both into the DDL).
      if (_detectedDimension != null) {
        _db!.execute('DROP TABLE IF EXISTS $_tableName');
      }
      _detectedDimension = null;
    } catch (e) {
      throw VectorStoreException('Failed to clear vector store', e);
    }
  }

  @override
  Future<void> close() async {
    // Deliberately NOT gated on `_isInitialized` alone — same rule as the
    // native arm. A store whose initialize() failed is exactly the one still
    // holding resources nobody else will release, and the flag is false for it.
    // `_sqlite3` is named here because the failed-initialize path clears `_db`
    // but not the WASM instance or the VFS it registered.
    if (_db == null && _sqlite3 == null && !_isInitialized) return;
    try {
      _db?.close();
    } finally {
      _db = null;
      _sqlite3 = null;
      _isInitialized = false;
      _detectedDimension = null;
    }
  }

  // === BLOB encoding (float32 little-endian, identical to native + Kotlin/Swift)

  static Uint8List _embeddingToBlob(List<double> embedding) {
    final buffer = ByteData(embedding.length * 4);
    for (var i = 0; i < embedding.length; i++) {
      buffer.setFloat32(i * 4, embedding[i].toDouble(), Endian.little);
    }
    return buffer.buffer.asUint8List();
  }
}
