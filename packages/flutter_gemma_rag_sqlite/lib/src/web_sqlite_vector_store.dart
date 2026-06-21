import 'dart:convert';
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
  void configure(FilterSchema schema) => _filterSchema = schema;

  @override
  Future<void> initialize(String databasePath) async {
    try {
      _sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse(_wasmUrl));
      await _registerPersistentVfs(_sqlite3!, databasePath);

      _db = _sqlite3!.open(_dbFile);

      // Recover the dimension from an existing vec0 table (page reload).
      _detectExistingTable();

      _isInitialized = true;
    } catch (e) {
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

    // In-memory — no persistence, but keeps the store usable.
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  }

  /// Reads the embedding dimension back from an existing vec0 table, if any.
  void _detectExistingTable() {
    try {
      final exists = _db!.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [_tableName],
      );
      if (exists.isEmpty) return;
      final row = _db!.select('SELECT embedding FROM $_tableName LIMIT 1');
      if (row.isNotEmpty) {
        final blob = row.first['embedding'] as Uint8List;
        _detectedDimension = blob.length ~/ 4; // float32 = 4 bytes
      }
    } catch (e) {
      // A pre-vec0 (plain-BLOB) table or a corrupt slot — start fresh.
      gemmaLog('[WebVectorStore] No reusable vec0 table found: $e');
    }
  }

  /// Builds the `vec0` virtual table for dimension [dimension] with one typed,
  /// filterable column per declared [FilterSchema] field, plus auxiliary
  /// (SELECT-only) `+content` / `+metadata` columns.
  void _createTable(int dimension) {
    final columns = <String>[
      'id TEXT PRIMARY KEY',
      'embedding float[$dimension]',
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
      final declared = _declaredValues(metadata);
      final columns = <String>[
        'id',
        'embedding',
        ...declared.keys,
        'content',
        'metadata',
      ];
      final placeholders = List.filled(columns.length, '?').join(', ');
      final binds = <Object?>[
        id,
        _embeddingToBlob(embedding),
        ...declared.values,
        content,
        metadata,
      ];
      _db!.execute(
        'INSERT OR REPLACE INTO $_tableName (${columns.join(', ')}) '
        'VALUES ($placeholders)',
        binds,
      );
    } catch (e) {
      throw VectorStoreException('Failed to add document', e);
    }
  }

  /// Extracts declared filterable fields out of the raw [metadata] JSON into
  /// the typed vec0 columns. Undeclared fields stay only in the `+metadata`
  /// blob. Returns an empty map when no schema is configured or the metadata is
  /// not a decodable JSON object.
  Map<String, Object?> _declaredValues(String? metadata) {
    if (_filterSchema.isEmpty || metadata == null || metadata.isEmpty) {
      return const {};
    }
    Object? decoded;
    try {
      decoded = jsonDecode(metadata);
    } catch (_) {
      return const {};
    }
    if (decoded is! Map) return const {};

    final values = <String, Object?>{};
    for (final field in _filterSchema.fields) {
      if (!decoded.containsKey(field.name)) continue;
      final raw = decoded[field.name];
      values[field.name] = switch (field.type) {
        FilterFieldType.bool => (raw == true || raw == 1) ? 1 : 0,
        _ => raw,
      };
    }
    return values;
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
        final distance = (row['distance'] as num).toDouble();
        final similarity = 1.0 - distance; // cosine: 1 = identical
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
    if (!_isInitialized) return; // Idempotent.
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
