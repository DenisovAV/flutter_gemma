import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/src/filter_codec.dart';
import 'package:flutter_gemma_rag_qdrant/src/point_id_hasher.dart';
import 'package:flutter_gemma_rag_qdrant/src/qdrant_edge_client.dart';
import 'package:path/path.dart' as p;

/// Native-only RAG vector store backed by qdrant-edge (FFI). Implements
/// flutter_gemma's [VectorStoreRepository]. Its HNSW index makes it the fastest
/// native option — roughly 5–11× faster search than the in-SQLite sqlite-vec
/// store at 1k–10k docs (with identical top-K results). Web is unsupported
/// (qdrant-edge can't compile to WASM); use flutter_gemma_rag_sqlite there.
///
/// Public API parity with the existing contract:
///
/// * `String id` continues to be the user-facing identifier. Internally
///   each id is mapped to a stable UUIDv5 via [PointIdHasher] and stored
///   alongside the document content in the qdrant payload so that
///   [searchSimilar] returns the original String back without a sidecar
///   mapping table.
/// * `addDocument`'s `metadata` is still a JSON string. We do **not**
///   parse it eagerly — we forward the raw string into the payload under
///   the key `metadata`. Filtering by metadata fields therefore requires
///   that callers pass valid JSON; this matches the existing constraint.
/// * `enableHnsw` is accepted but ignored — qdrant decides indexing
///   internally based on its `indexing_threshold` (~20k points). Below
///   that it brute-forces a plain segment, which is already faster than
///   our Dart HNSW for typical RAG corpora.
///
/// Distance defaults to cosine, matching the historical behaviour.
///
/// ### On-disk layout
///
/// The store owns a bounded, format-scoped subdirectory —
/// `databasePath/qdrant_edge_v1` — created on first write, and that is the only
/// shard it ever opens. This means:
///
///   * a shard written by 1.x (crate 0.7.x) sits at the bare `databasePath` and
///     is never opened, so there is no partial-open or WAL-corruption risk from
///     mixing engine versions. It is not ignored either: [initialize] refuses
///     it with a [VectorStoreException] rather than letting the store come up
///     silently empty over a populated index;
///   * [clear] deletes the owned subdirectory, and — only when a 1.x store is
///     present — the three entries such a shard owns at the bare path
///     (`edge_config.json`, `wal/`, `segments/`). That is what makes the
///     documented "clear and re-index" remedy actually work. Any OTHER file or
///     directory the caller keeps alongside the store is never touched.
class QdrantVectorStore implements VectorStoreRepository {
  QdrantEdgeClient? _client;

  /// Dimension is captured on the first `addDocument` call (matches the
  /// existing auto-detection contract). Subsequent inserts must agree.
  int? _dim;

  /// Cached for [getStats] — the shim never exposes the configured dim,
  /// only the count. We keep it in Dart-land instead.
  Distance _distance = Distance.cosine;

  /// The path passed to [initialize]. The store never opens or deletes this
  /// path directly — only the owned subdirectory under it (see [_storeDirFor]).
  String? _databasePath;

  /// In-flight [QdrantEdgeClient.open]. Two concurrent `addDocument` calls on a
  /// cold store both saw `_client == null` and both opened the same directory;
  /// qdrant holds the WAL exclusively, so the loser failed with
  /// `Can't init WAL: Kind(WouldBlock)` and its document was lost.
  /// `Future.wait(docs.map(store.addDocument))` is the obvious way to index a
  /// corpus, so this was reachable from ordinary use.
  Future<QdrantEdgeClient>? _opening;

  /// Bumped by [initialize], [clear] and [close]. An open that started before
  /// the bump must not install its client afterwards: it would resurrect a
  /// closed store (holding the WAL lock for the process lifetime) or, worse,
  /// point `_client` at the PREVIOUS path while `_databasePath` names the new
  /// one — sending every later write into the wrong store.
  int _generation = 0;

  /// Set when a shard EXISTS on disk but could not be opened.
  ///
  /// `_client == null` collapsed three different facts into one value: never
  /// initialized (a caller error), initialized-but-cold (genuinely empty), and
  /// "there are documents on disk that we failed to read". The third read as
  /// the second — searchSimilar returned `[]`, getStats returned 0 — so an app
  /// whose corpus was intact but unreadable answered without context and said
  /// nothing about it. That is the defect this release exists to fix; leaving
  /// it on the read path would be shipping it under a new version number.
  ///
  /// Cleared once an open succeeds, and on initialize/clear/close.
  String? _adoptionFailure;

  /// `enableHnsw` is part of the contract but a no-op for qdrant.
  bool _enableHnsw = true;

  /// Declared filterable-metadata schema (via [configure]). Empty by default,
  /// so callers that never declare a schema get byte-identical payloads. When
  /// non-empty, [addDocument] promotes each declared field to a TOP-LEVEL
  /// payload key (alongside the opaque [_metadataKey] blob) so qdrant's
  /// [FilterCodec] — which already targets top-level keys — can match on them.
  FilterSchema _filterSchema = const FilterSchema();

  /// Payload key under which we stash the original String id sent by the
  /// caller. qdrant point ids are UUID-hashed for storage; this lets
  /// [searchSimilar] reconstruct the original on the way out.
  static const _userIdKey = '__flutter_gemma_id';
  static const _contentKey = '__flutter_gemma_content';
  static const _metadataKey = '__flutter_gemma_metadata';

  /// The three keys above, as a set — [configure] refuses a filter field that
  /// would collide with one.
  static const _reservedPayloadKeys = <String>{
    _userIdKey,
    _contentKey,
    _metadataKey,
  };

  /// The package's on-disk format namespace. A new location for the 0.8.0
  /// SDK / crate-0.8.0 shard format. A shard written by an older (1.x /
  /// crate 0.7.x) release sits at the bare [_databasePath]; this release never
  /// opens it, refuses to start over it, and can remove it via [clear].
  static const _storeDirName = 'qdrant_edge_v1';

  /// Test-only seam: when set, [clear] calls this instead of
  /// `dir.deleteSync(recursive: true)` on the owned shard directory. Lets
  /// tests deterministically exercise the delete-failure / fail-closed
  /// recovery path (see `clear()`) by throwing a [FileSystemException] from
  /// here, without OS-level fault injection (permission bits, symlinks) that
  /// would not behave identically across POSIX and Windows.
  @visibleForTesting
  void Function(Directory dir)? debugDeleteDirOverride;

  @override
  bool get isInitialized => _databasePath != null;

  @override
  bool get enableHnsw => _enableHnsw;

  @override
  set enableHnsw(bool value) => _enableHnsw = value;

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
      FilterCodec.validateFieldName(field.name);
      // Declared fields are promoted to TOP-LEVEL payload keys, the same map
      // that carries the document's id, content and metadata. A field named
      // like one of those overwrites it: a String value silently swaps the id
      // or the body of every hit, and a non-String value escapes searchSimilar
      // as a raw _TypeError rather than a VectorStoreException. Reject it here,
      // where the error points at the schema the developer wrote.
      if (_reservedPayloadKeys.contains(field.name)) {
        throw ArgumentError.value(
          field.name,
          'schema.fields',
          'is reserved by flutter_gemma_rag_qdrant for the stored document '
              'id/content/metadata — choose another field name',
        );
      }
    }
    _filterSchema = schema;
  }

  @override
  Future<void> initialize(String databasePath) async {
    // Re-init is allowed and matches the DartVectorStoreRepository contract:
    // close any prior shard, then arm the new path. Dimension is detected
    // lazily on the first addDocument so we don't have to commit to one
    // before we've seen an embedding.
    final existing = _client;
    if (existing != null) {
      try {
        await existing.close();
      } on QdrantException catch (e) {
        gemmaLog('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
    _client = null;
    _dim = null;
    _adoptionFailure = null;
    _generation++;
    _databasePath = databasePath;

    // Adopt an existing shard NOW rather than on the first write. Opening
    // lazily meant a store re-opened after an app restart reported zero
    // documents and no search hits until something happened to write to it —
    // and a removeDocument() issued before that first write was dropped with
    // only a log line. The dimension comes from the shard itself, so we do not
    // need an embedding in hand to do this.
    final gen = _generation;
    final storeDir = _storeDirFor(databasePath);

    // Detect the 1.x layout HERE, not on the first write. Checking it only in
    // _ensureClient meant a read-only session — open the app, ask a question —
    // never reached the check: initialize() succeeded, searchSimilar returned
    // no hits, and the model answered without the corpus that was sitting on
    // disk the whole time. Only a write complained.
    //
    // Order matters: `_databasePath` is already armed above, so the clear()
    // this message prescribes is reachable. Throwing before that would leave
    // the caller holding a store that refuses the remedy it just recommended.
    if (!Directory(storeDir).existsSync() && _hasLegacyStoreAt(databasePath)) {
      throw VectorStoreException(_legacyStoreMessage(databasePath));
    }

    try {
      final opened = await QdrantEdgeClient.openExisting(path: storeDir);
      if (opened == null) return;
      if (_generation != gen) {
        // initialize()/clear()/close() ran while we were opening.
        try {
          await opened.client.close();
        } catch (_) {}
        return;
      }
      _client = opened.client;
      _dim = opened.dim;
      _adoptionFailure = null;
    } on QdrantException catch (e) {
      // Not fatal HERE: a write goes through _ensureClient, which retries the
      // open with the dimension the caller actually intends — and only that
      // retry can tell a dimension mismatch from a real failure. But a read
      // between now and then must not answer "empty" for a shard that is
      // sitting right there, so latch it. gemmaLog alone would not do: it is
      // `if (!kDebugMode) return;`, so in a release build nobody is told at all.
      _adoptionFailure = '$e';
      gemmaLog('[QdrantVectorStore] could not adopt existing shard: $e');
    }
  }

  /// The owned, format-scoped shard directory for [databasePath] — the only
  /// path this store ever opens or deletes. Never the bare [databasePath]
  /// itself.
  static String _storeDirFor(String databasePath) =>
      p.join(databasePath, _storeDirName);

  /// Entries a 1.x store (crate 0.7.x) wrote DIRECTLY at [_databasePath],
  /// before this package owned a format-scoped subdirectory. `edge_config.json`
  /// is the marker; `wal` and `segments` are the payload.
  static const _legacyEntries = ['edge_config.json', 'wal', 'segments'];

  /// True when [databasePath] holds a shard written by 1.x. Such a store is
  /// invisible to this release — 2.0 only ever opens the owned subdir — so
  /// without this check the app comes up with an empty index, no error, and
  /// the old corpus still occupying disk.
  static String _legacyStoreMessage(String databasePath) =>
      'Found a store written by flutter_gemma_rag_qdrant 1.x at $databasePath. '
      'Its on-disk format is not readable by 2.0. Call clear() to remove it '
      '(that now deletes the 1.x layout too), then re-index.';

  static bool _hasLegacyStoreAt(String databasePath) {
    // Gate on `edge_config.json` ONLY, and on its content — never on `wal` or
    // `segments`. Those two are ordinary directory names, `databasePath` is
    // routinely an app-documents directory, and a false positive here is
    // destructive: the store refuses to run and `clear()` — the remedy the
    // error message names — deletes what it matched. A caller's own
    // `segments/` must never be mistaken for our shard.
    //
    // The cost is a false NEGATIVE for a 1.x store whose marker was removed by
    // hand. That case degrades to "2.0 creates its subdir alongside", which
    // wastes disk but destroys nothing — the right direction to be wrong in.
    final marker = File(p.join(databasePath, _legacyEntries.first));
    if (!marker.existsSync()) return false;
    try {
      return jsonDecode(marker.readAsStringSync()) is Map;
    } catch (_) {
      // Present but not JSON — someone else's file with the same name.
      return false;
    }
  }

  /// Deletes ONLY the three entries a 1.x shard owns. Deliberately not a
  /// recursive wipe of [databasePath]: callers are allowed to keep unrelated
  /// files alongside the store, and this release must not touch them.
  /// Returns the entries it could NOT remove, so the caller can settle its
  /// own state before reporting the failure.
  static List<String> _clearLegacyStoreAt(String databasePath) {
    if (!_hasLegacyStoreAt(databasePath)) return const [];
    // Delete the payload first and the MARKER LAST. `edge_config.json` is what
    // _hasLegacyStoreAt keys on, so removing it before `wal/` and `segments/`
    // would make any survivor of a partial delete permanently undetectable —
    // unclearable by this API and invisible to the guard in initialize().
    final failed = <String>[];
    for (final name in [..._legacyEntries.skip(1), _legacyEntries.first]) {
      final path = p.join(databasePath, name);
      final dir = Directory(path);
      final file = File(path);
      try {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        } else if (file.existsSync()) {
          file.deleteSync();
        }
      } on FileSystemException catch (e) {
        failed.add('$path ($e)');
      }
    }
    // Do NOT log-and-continue: gemmaLog is compiled out of release builds, so a
    // logged failure here is an unreported one for every user. clear() is how a
    // caller erases indexed documents — reporting success over a partial delete
    // is the same defect this release fixed for the owned subdirectory.
    return failed;
  }

  /// The contract on [VectorStoreRepository] documents `StateError` for an
  /// uninitialized store on searchSimilar/getStats/removeDocument, and the
  /// sibling sqlite store throws it. This one returned empty results instead,
  /// so the same misuse was loud in one implementation and invisible in the
  /// other.
  void _assertUsable(String operation) {
    final databasePath = _databasePath;
    if (databasePath == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    final failure = _adoptionFailure;
    if (failure != null) {
      throw VectorStoreException(
        '$operation refused: a qdrant shard exists at '
        '${_storeDirFor(databasePath)} but could not be opened, so this store '
        'cannot tell you whether it is empty. Reporting no results would hide '
        'an intact corpus. Underlying error: $failure',
      );
    }
  }

  Future<QdrantEdgeClient> _ensureClient({required int dim}) async {
    final databasePath = _databasePath;
    if (databasePath == null) {
      throw const VectorStoreException(
        'Vector store not initialized — call initialize(path) first.',
      );
    }
    final existing = _client;
    if (existing != null) {
      if (_dim != dim) {
        throw ArgumentError(
          'Embedding dimension mismatch: shard was opened with dim=$_dim, '
          'got vector of length $dim',
        );
      }
      return existing;
    }

    // Someone else is already opening this store — join them instead of racing
    // for the WAL lock.
    final inFlight = _opening;
    if (inFlight != null) {
      final c = await inFlight;
      if (_dim != dim) {
        throw ArgumentError(
          'Embedding dimension mismatch: shard was opened with dim=$_dim, '
          'got vector of length $dim',
        );
      }
      return c;
    }
    // First open. The store owns `<databasePath>/qdrant_edge_v1` — created
    // recursively — and never opens the bare databasePath itself, so a
    // pre-existing (e.g. legacy) directory or file sitting directly at
    // databasePath is left untouched.
    final storeDir = _storeDirFor(databasePath);
    // A 1.x store sits directly at databasePath and this release never opens
    // it. Left undetected the app starts with an empty index, reports no
    // error, and answers without context while the old corpus still occupies
    // disk — so refuse loudly instead, and say what actually clears it.
    if (!Directory(storeDir).existsSync() && _hasLegacyStoreAt(databasePath)) {
      throw VectorStoreException(_legacyStoreMessage(databasePath));
    }
    try {
      Directory(storeDir).createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw VectorStoreException(
        'Failed to create qdrant shard directory at $storeDir: $e',
      );
    }
    final gen = _generation;
    try {
      final future = QdrantEdgeClient.open(
        path: storeDir,
        dim: dim,
        distance: _distance,
      );
      _opening = future;
      final QdrantEdgeClient c;
      try {
        c = await future;
      } finally {
        if (identical(_opening, future)) _opening = null;
      }
      if (_generation != gen) {
        // initialize()/clear()/close() ran while we were opening. Installing
        // this client now would either resurrect a store the caller closed —
        // keeping its WAL lock until the process exits — or bind `_client` to
        // the old path under a new `_databasePath`. Hand the shard back
        // instead, and let the caller retry against the current state.
        try {
          await c.close();
        } catch (_) {
          // Best-effort: we are already unwinding.
        }
        throw const VectorStoreException(
          'Vector store was re-initialized, cleared or closed while opening — '
          'retry the operation.',
        );
      }
      _client = c;
      _dim = dim;
      _adoptionFailure = null;
      return c;
    } on QdrantException catch (e) {
      // Wrap and rethrow — never auto-rename/delete/rebuild. Whether the
      // failure is transient (permissions, lock, missing native lib, I/O) or
      // a real format incompatibility, it surfaces the same safe way: thrown,
      // data untouched.
      // Say what failed, not what to delete. Most causes here are transient
      // or a plain caller error — a concurrent open, a lock still held by a
      // client that was not closed, a changed embedding dimension — and only
      // the last is corruption. Blanket "clear and re-index" advice told users
      // to destroy a working index to fix a lock.
      throw VectorStoreException('Failed to open qdrant shard at $storeDir', e);
    }
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  }) async {
    final c = await _ensureClient(dim: embedding.length);
    final payload = <String, dynamic>{
      _userIdKey: id,
      _contentKey: content,
      _metadataKey: ?metadata,
    };
    // Filter-field promotion: only when a schema is declared AND metadata is
    // present. Without a schema this branch never runs, so existing callers
    // get byte-identical payloads (the opaque blob under _metadataKey only).
    // With a schema, expand each DECLARED field to a top-level payload key so
    // FilterCodec's top-level-key predicates actually match.
    if (!_filterSchema.isEmpty && metadata != null) {
      _promoteFilterFields(payload, metadata);
    }
    try {
      await c.upsert(
        id: PointIdHasher.hash(id),
        vector: embedding,
        payload: payload,
      );
    } on QdrantException catch (e) {
      throw VectorStoreException('addDocument failed for id=$id', e);
    }
  }

  /// Expands the declared [FilterField]s out of the raw [metadata] JSON into
  /// top-level [payload] keys (in addition to the opaque [_metadataKey] blob).
  ///
  /// Defensive by design — promotion must never break an `addDocument` that
  /// would otherwise succeed:
  /// * non-object or unparseable [metadata] → logged, left as the opaque blob;
  /// * a declared field absent from the metadata → skipped (no key written),
  ///   so a [Filter] on it matches nothing (documented no-op, never a throw).
  void _promoteFilterFields(Map<String, dynamic> payload, String metadata) {
    Object? decoded;
    try {
      decoded = jsonDecode(metadata);
    } on FormatException catch (e) {
      gemmaLog(
        '[QdrantVectorStore] metadata is not valid JSON — filter fields not '
        'promoted (round-trip blob kept): $e',
      );
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      gemmaLog(
        '[QdrantVectorStore] metadata JSON is not an object — filter fields '
        'not promoted (round-trip blob kept)',
      );
      return;
    }
    for (final field in _filterSchema.fields) {
      if (decoded.containsKey(field.name)) {
        payload[field.name] = decoded[field.name];
      }
    }
  }

  @override
  Future<void> removeDocument({required String id}) async {
    _assertUsable('removeDocument');
    final c = _client;
    // Initialized, no shard on disk: deleting from an empty store is the
    // documented no-op. Reachable only when nothing was ever written.
    if (c == null) return;
    try {
      await c.delete([PointIdHasher.hash(id)]);
    } on QdrantException catch (e) {
      throw VectorStoreException('removeDocument failed for id=$id', e);
    }
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
    Filter? filter,
  }) async {
    _assertUsable('searchSimilar');
    final c = _client;
    if (c == null || _dim == null) {
      // No documents yet — nothing to retrieve. Genuinely empty: _assertUsable
      // has already ruled out "uninitialized" and "on disk but unreadable".
      return const [];
    }
    if (queryEmbedding.length != _dim) {
      throw ArgumentError(
        'Query embedding dimension ${queryEmbedding.length} does not '
        'match stored dimension $_dim',
      );
    }
    final filterJson = FilterCodec.encode(filter, _filterSchema);
    final List<SearchHit> hits;
    try {
      hits = await c.search(
        queryVector: queryEmbedding,
        topK: topK,
        filterJson: filterJson,
      );
    } on QdrantException catch (e) {
      throw VectorStoreException('searchSimilar failed', e);
    }
    return [
      for (final hit in hits)
        if (hit.score >= threshold)
          RetrievalResult(
            id: hit.payload?[_userIdKey] as String? ?? hit.id,
            content: hit.payload?[_contentKey] as String? ?? '',
            similarity: hit.score,
            metadata: hit.payload?[_metadataKey] as String?,
          ),
    ];
  }

  @override
  Future<VectorStoreStats> getStats() async {
    _assertUsable('getStats');
    final c = _client;
    if (c == null) {
      return VectorStoreStats(documentCount: 0, vectorDimension: 0);
    }
    final int n;
    try {
      n = await c.count();
    } on QdrantException catch (e) {
      throw VectorStoreException('getStats failed', e);
    }
    return VectorStoreStats(documentCount: n, vectorDimension: _dim ?? 0);
  }

  @override
  Future<void> clear() async {
    final c = _client;
    final databasePath = _databasePath;
    if (databasePath == null) return;

    // qdrant-edge has no truncate primitive — close the client, delete the
    // OWNED shard subdirectory (never the bare databasePath), and let the
    // next addDocument reopen fresh.
    if (c != null) {
      try {
        await c.close();
      } catch (e) {
        throw VectorStoreException(
          'Failed to close qdrant client during clear: $e',
        );
      }
    }
    // Invalidate any in-flight open now — it must not install its client on
    // top of a store we are clearing. But do NOT drop `_client`/`_dim` yet:
    // the guard and the delete below can throw, and nulling them first makes
    // getStats()/searchSimilar() answer "empty" over data that is still on
    // disk, then resurrect it on the next write. 1.x deliberately dropped the
    // handles only after close + delete both succeeded; that ordering is the
    // property, not an accident.
    _generation++;

    final storeDir = _storeDirFor(databasePath);
    final dir = Directory(storeDir);
    if (!dir.existsSync()) {
      // Nothing under the owned subdir. There may still be a 1.x store at the
      // bare path — clear() is the remedy the CHANGELOG points at, so it has
      // to be able to remove one.
      final failed = _clearLegacyStoreAt(databasePath);
      _client = null;
      _dim = null;
      _adoptionFailure = null;
      if (failed.isNotEmpty) _throwLegacySweepFailure(databasePath, failed);
      return;
    }

    _assertStoreDirWithinDatabasePath(databasePath, storeDir);

    List<String> legacyFailures = const [];
    try {
      final override = debugDeleteDirOverride;
      if (override != null) {
        override(dir);
      } else {
        dir.deleteSync(recursive: true);
      }
      legacyFailures = _clearLegacyStoreAt(databasePath);
      // Close + delete both succeeded: only now is it safe to report empty.
      _client = null;
      _dim = null;
      _adoptionFailure = null;
    } on FileSystemException catch (e) {
      // Delete failed partway — the on-disk subdir may be left in a mixed
      // state. Fail-closed: mark the whole store uninitialized (rather than
      // just clearing the client/dim above) so nothing reuses a possibly
      // half-deleted shard; the caller must call initialize() again before
      // any further operation succeeds.
      _databasePath = null;
      throw VectorStoreException(
        'Failed to delete qdrant shard directory at $storeDir: $e',
      );
    }
    // Reported only after the handles are settled above — a throw here must not
    // skip the state transition and wedge the store on a closed client.
    if (legacyFailures.isNotEmpty) {
      _throwLegacySweepFailure(databasePath, legacyFailures);
    }
  }

  static Never _throwLegacySweepFailure(
    String databasePath,
    List<String> failed,
  ) {
    // Not a log: gemmaLog is compiled out of release builds, so logging a
    // partial delete means no user is ever told. clear() is how a caller erases
    // indexed documents; reporting success over surviving data is the defect
    // this release fixed for the owned subdirectory.
    throw VectorStoreException(
      'clear() removed this release\'s store but could not remove the 1.x '
      'store at $databasePath. These entries remain on disk and still hold '
      'indexed documents: ${failed.join('; ')}',
    );
  }

  /// Refuses to delete anything unless the *canonicalized* [storeDir]
  /// resolves to a non-root descendant of the *canonicalized* [databasePath]
  /// — i.e. actually inside it, not equal to it. Canonicalizing (resolving
  /// symlinks) before comparing is what makes this a real guard rather than a
  /// string-prefix check: [storeDir] is always literally
  /// `p.join(databasePath, 'qdrant_edge_v1')` by construction, so the only way
  /// this can fail is a symlink (or similar) that makes the on-disk path
  /// resolve outside [databasePath]. On any failure to resolve, or an escape,
  /// this throws [VectorStoreException] and deletes nothing.
  void _assertStoreDirWithinDatabasePath(String databasePath, String storeDir) {
    final String canonicalDatabasePath;
    final String canonicalStoreDir;
    try {
      canonicalDatabasePath = Directory(
        databasePath,
      ).resolveSymbolicLinksSync();
      canonicalStoreDir = Directory(storeDir).resolveSymbolicLinksSync();
    } on FileSystemException catch (e) {
      throw VectorStoreException(
        'Failed to resolve the qdrant shard path for the clear() safety '
        'check: $e',
      );
    }
    if (!p.isWithin(canonicalDatabasePath, canonicalStoreDir)) {
      throw VectorStoreException(
        'Refusing to delete "$storeDir": it does not resolve to a path '
        'inside the initialized database directory "$databasePath" '
        '(possible symlink escape). No data was deleted.',
      );
    }
  }

  @override
  Future<void> close() async {
    final c = _client;
    _client = null;
    _dim = null;
    _adoptionFailure = null;
    _generation++;
    _databasePath = null;
    if (c != null) {
      try {
        await c.close();
      } on QdrantException catch (e) {
        gemmaLog('[QdrantVectorStore] close() failed (best-effort): $e');
      }
    }
  }
}
