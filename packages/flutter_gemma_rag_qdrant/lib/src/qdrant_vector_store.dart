import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
/// Thrown when a store written by `flutter_gemma_rag_qdrant` 1.x is found at
/// the bare `databasePath`, and ONLY then.
///
/// It exists because the remedy is destructive. `clear()` is the documented
/// answer to this one situation, and to no other: for a moment this package
/// threw a bare [VectorStoreException] for both this and "a shard is here and
/// would not open", which made the recipe in its own README delete an intact
/// 2.0 corpus whenever the store happened to be open elsewhere — and report
/// success. Measured, with two documents.
///
/// Catch this, not [VectorStoreException], before calling `clear()`.
class QdrantLegacyStoreException extends VectorStoreException {
  const QdrantLegacyStoreException(super.message);
}

class QdrantVectorStore implements VectorStoreRepository {
  QdrantEdgeClient? _client;

  /// Dimension is captured on the first `addDocument` call (matches the
  /// existing auto-detection contract). Subsequent inserts must agree.
  int? _dim;

  /// Cached for [getStats] — the shim never exposes the configured dim,
  /// only the count. We keep it in Dart-land instead.
  final Distance _distance = Distance.cosine;

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

  /// Lifecycle transitions run one at a time.
  ///
  /// initialize/clear/close each mutate several fields around an await, and
  /// interleaving any two of them produced states no single method can:
  ///
  ///   * two concurrent `initialize(samePath)` calls — a provider rebuilt, an
  ///     initState firing twice — raced qdrant's exclusive WAL. One won, the
  ///     other caught `WouldBlock` and latched the store unreadable over an
  ///     intact corpus, while BOTH calls reported success. Measured.
  ///   * a `close()` landing inside initialize()'s `await existing.close()`
  ///     was silently undone: initialize resumed and re-installed a live
  ///     client, so a store the caller closed sat holding a WAL lock.
  ///   * a `clear()` landing in the same gap dropped a client a concurrent
  ///     initialize had just installed, without closing it — WAL held for the
  ///     process lifetime, every later write failing WouldBlock.
  ///
  /// `_generation` still guards the OPEN inside one transition. This guards
  /// the transitions against each other, which a counter captured after the
  /// await cannot do.
  Future<void> _lifecycle = Future<void>.value();

  Future<T> _serializeLifecycle<T>(Future<T> Function() body) {
    // The lane advances through a gate that never errors, NOT by attaching a
    // handler to the caller's own future.
    //
    // `_lifecycle = run.then((_) {}, onError: (_) {})` looked equivalent and
    // was not: attaching onError to `run` registers a listener, which marks
    // the error handled globally, so an UNAWAITED call reached neither
    // Zone.handleUncaughtError nor FlutterError.onError. `initState()` cannot
    // await, so `store.initialize(dir);` fire-and-forget is the ordinary shape
    // — the one this lane's own comment cites — and over a 1.x store the
    // headline error of this release went nowhere at all. It also ate
    // _throwLegacySweepFailure, which throws instead of logging precisely so a
    // partial delete can never go unreported. Measured against a plain
    // unawaited async throw in the same zone: the control arrived, this did not.
    final gate = Completer<void>();
    final previous = _lifecycle;
    _lifecycle = gate.future;
    return previous.then((_) async {
      try {
        return await body();
      } finally {
        gate.complete();
      }
    });
  }

  /// Set when the store is armed but must NOT be read: the full message
  /// explaining why.
  ///
  /// `_client == null` collapsed three different facts into one value: never
  /// initialized (a caller error), initialized-but-cold (genuinely empty), and
  /// "there are documents on disk that we failed to read". The third read as
  /// the second — searchSimilar returned `[]`, getStats returned 0 — so an app
  /// whose corpus was intact but unreadable answered without context and said
  /// nothing about it. That is the defect this release exists to fix; leaving
  /// it on the read path would be shipping it under a new version number.
  ///
  /// Two things set it, and both used to be invisible to a reader:
  ///   * adoption failed — a shard is on disk and would not open;
  ///   * a 1.x store was found, which initialize() also throws for.
  ///
  /// The second is why this is a latch and not just a return value.
  /// initialize() arms `_databasePath` BEFORE it throws, so that clear() — the
  /// remedy its own message prescribes — stays reachable. Without a latch that
  /// left the object looking healthy: a caller that logged the exception and
  /// carried on got `getStats() == 0` and no search hits over an intact 1.x
  /// corpus. That is the exact defect this release exists to remove, in the one
  /// case the release is about. Measured, not reasoned about.
  ///
  /// Cleared once an open succeeds, and on initialize/clear/close.
  String? _unusableReason;

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

  @override
  /// The contract is "true if [initialize] was called successfully" — so a
  /// store whose initialize() threw must answer false, even though the path is
  /// still armed so clear() can reach it. Answering true told a caller it was
  /// ready when every operation on it refuses.
  bool get isInitialized => _databasePath != null && _unusableReason == null;

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
  Future<void> initialize(String databasePath) =>
      _serializeLifecycle(() => _initialize(databasePath));

  Future<void> _initialize(String databasePath) async {
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
    _unusableReason = null;
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
      // Latch BEFORE throwing. A caller that catches this and carries on, or
      // any other code path that reads, must not be told the store is empty.
      _unusableReason = _legacyStoreMessage(databasePath);
      throw QdrantLegacyStoreException(_unusableReason!);
    }

    try {
      final opened = await QdrantEdgeClient.openExisting(path: storeDir);
      if (opened == null) return;
      if (_generation != gen) {
        // initialize()/clear()/close() ran while we were opening.
        try {
          await opened.client.close();
        } catch (_) {
          // Best-effort, and bounded: a shard we cannot close keeps its WAL
          // lock for the process lifetime, but the next open reports that
          // loudly (WouldBlock -> latched) rather than answering "empty".
          // Nothing here can act on the cause, and the store we are unwinding
          // from is not the one the caller now owns.
        }
        return;
      }
      _client = opened.client;
      _dim = opened.dim;
      _unusableReason = null;
    } on QdrantException catch (e) {
      // Belt-and-suspenders, and honestly so: with lifecycle transitions
      // serialized, nothing can bump `_generation` while this method is
      // suspended, so this check is unreachable today — a mutation removing it
      // kills no test, because no test CAN reach it. It stays because it costs
      // one line and is the correct behaviour if the lane is ever bypassed;
      // the property it protects (a failure for the old path must not latch a
      // store since armed at a new one) is pinned by an outcome test instead.
      if (_generation != gen) return;
      // An earlier version of this comment said the failure was not fatal here
      // because the write path would retry "with the dimension the caller
      // intends". That was wrong: openExisting passes no dim at all
      // (`EdgeShard.load(path, config: null)`), so a dimension mismatch cannot
      // be why it failed. What can: an exclusive WAL held elsewhere, a
      // corrupted config, permissions. None of those are resolved by a write,
      // so a write must not paper over them either — addDocument asserts the
      // latch too. gemmaLog alone would not do: it is debug-only, so in a
      // release build nobody is told at all.
      // Two different situations, two different things to tell the caller.
      // They arrived as one generic error until the SDK gave the lock its own
      // type — and conflating "someone else has it open" with "this data is
      // damaged" is how a recovery step written for the second once ran
      // against the first.
      _unusableReason = e is QdrantShardLockedException
          ? 'The qdrant shard at $storeDir is open elsewhere, so this store '
                'cannot read it — and reporting no results would hide an '
                'intact corpus. Close the other store (or wait for it), then '
                'call initialize() again. Underlying error: $e'
          : 'A qdrant shard exists at $storeDir but could not be opened, so '
                'this store cannot tell you whether it is empty — reporting no '
                'results would hide an intact corpus. Call initialize() again '
                'once the cause is cleared. Underlying error: $e';
      gemmaLog('[QdrantVectorStore] could not adopt existing shard: $e');
      // And REPORT it. The contract says initialize() throws
      // VectorStoreException when initialization fails, and this failed: a
      // shard is on disk and we could not open it. Returning normally left the
      // caller believing the store was ready while `isInitialized` said false
      // and every read refused — the failure surfacing later, somewhere else,
      // as a surprise.
      throw VectorStoreException(_unusableReason!);
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

  /// What a caller is told when [databasePath] holds a 1.x store: what it is,
  /// why this release cannot read it, and the one call that clears it.
  static String _legacyStoreMessage(String databasePath) =>
      'Found a store written by flutter_gemma_rag_qdrant 1.x at $databasePath. '
      'Its on-disk format is not readable by 2.0, and this release never '
      'deletes files it cannot read: remove "${_legacyEntries.join('", "')}" '
      'from that directory yourself, then re-index. Anything else you keep '
      'there is left alone.';

  /// True when [databasePath] holds a shard written by 1.x. Such a store is
  /// invisible to this release — 2.0 only ever opens the owned subdir — so
  /// without this check the app comes up with an empty index, no error, and
  /// the old corpus still occupying disk.
  /// True when [databasePath] holds a store written by 1.x.
  ///
  /// It used to answer with four states, because "may I refuse?" and "may I
  /// delete?" needed different evidence and getting that wrong cost a caller
  /// their own `wal/` and `segments/` twice. clear() no longer deletes
  /// anything, so the second question is gone and one bool is enough.
  ///
  /// A marker we cannot READ still counts as present: refusing costs a user
  /// one manual cleanup, while missing a real 1.x store costs them a silently
  /// empty index over an intact corpus, which is what this release exists to
  /// prevent.
  static bool _hasLegacyStoreAt(String databasePath) {
    final marker = File(p.join(databasePath, _legacyEntries.first));
    if (!marker.existsSync()) return false;
    final hasPayload = _legacyEntries.skip(1).any((name) {
      final at = p.join(databasePath, name);
      return Directory(at).existsSync() || File(at).existsSync();
    });
    if (!hasPayload) return false; // a lone marker is a leftover, not a store
    try {
      // Readable and not JSON at all: positively someone else's file.
      return jsonDecode(marker.readAsStringSync()) is Map;
    } on FormatException {
      return false;
    } on FileSystemException {
      return true;
    }
  }

  /// Two refusals, one place.
  ///
  /// [VectorStoreRepository] documents `StateError` for an uninitialized store
  /// on addDocument/searchSimilar/getStats/removeDocument (and clear(), which
  /// raises it directly — it must stay callable on a LATCHED store, because
  /// clearing is the remedy). This one returned empty results instead, so the
  /// same misuse was loud in the sibling sqlite store and invisible here.
  ///
  /// The second refusal is the latch: armed, but holding data it cannot read.
  void _assertUsable(String operation) {
    final databasePath = _databasePath;
    if (databasePath == null) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }
    final reason = _unusableReason;
    if (reason != null) {
      throw VectorStoreException('$operation refused. $reason');
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
      // Everything the leader gets, the joiner must get too. Three ways this
      // used to differ, all reachable from the one call the doc above names as
      // the obvious way to index a corpus — Future.wait over addDocument:
      //
      //   * the leader's failure was wrapped into VectorStoreException at the
      //     bottom of this method; the joiner's await sat OUTSIDE that try, so
      //     joiners received a raw QdrantException — a type this package does
      //     not export, so `on VectorStoreException` (the documented contract)
      //     missed every one of them;
      //   * the joiner had no generation check, so a store re-initialized
      //     mid-open handed it a client bound to the previous path;
      //   * with _dim nulled by that transition, the dim comparison below
      //     reported "shard was opened with dim=null" — blaming the caller's
      //     vector for a lifecycle event.
      final gen = _generation;
      final QdrantEdgeClient c;
      try {
        c = await inFlight;
      } on QdrantException catch (e) {
        throw VectorStoreException(
          'Failed to open qdrant shard at ${_storeDirFor(databasePath)}',
          e,
        );
      }
      if (_generation != gen) {
        throw const VectorStoreException(
          'Vector store was re-initialized, cleared or closed while opening — '
          'retry the operation.',
        );
      }
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
      // Latch here too. initialize()'s copy does, and a store that reaches
      // this one first — a write before any read — must end up in the same
      // state, or the next read answers "empty" over the 1.x corpus.
      _unusableReason = _legacyStoreMessage(databasePath);
      throw QdrantLegacyStoreException(_unusableReason!);
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
      _unusableReason = null;
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
    // A shard we could not read is not a shard we may write into: appending to
    // it would merge into a corpus this store just refused to report, and the
    // successful open would clear the latch — erasing the only signal the user
    // ever gets.
    _assertUsable('addDocument');
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
  Future<void> clear() => _serializeLifecycle(_clear);

  Future<void> _clear() async {
    final databasePath = _databasePath;
    if (databasePath == null) {
      // The contract documents StateError here, and the sibling sqlite store
      // throws it. Returning silently made "I cleared the store" and "I was
      // never given a path" the same observable outcome.
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // Erase the documents, not the directory.
    //
    // Every destructive path this class used to carry — deleting the owned
    // subdirectory, the canonicalized boundary guard against a symlink escape,
    // the sweep over a 1.x layout, the marker-last ordering, the partial-sweep
    // report, a fault-injection seam that could silently skip a delete — grew
    // out of one sentence carried forward from the old Rust shim without ever
    // being rechecked against the SDK that replaced it: "qdrant-edge has no
    // truncate primitive".
    //
    // It has one. `deletePointsByFilter` with an empty filter matches every
    // point. Measured: 2 in, 0 after, directory intact, store still writable
    // and re-openable. So clear() no longer closes the client, no longer
    // touches the filesystem, and cannot delete anything that is not a point
    // it wrote — which retires the whole class of bug that reached a caller's
    // own `wal/` and `segments/` twice, and an intact 2.0 corpus once.
    if (_hasLegacyStoreAt(databasePath)) {
      // A 1.x layout cannot be emptied in place: this release cannot open it.
      // Refusing is the whole remedy now — we do not delete what we cannot
      // read, and we say exactly what to remove.
      throw QdrantLegacyStoreException(
        'Found a store written by flutter_gemma_rag_qdrant 1.x at '
        '$databasePath. Its on-disk format is not readable by 2.0, so clear() '
        'cannot empty it. Delete "${_legacyEntries.join('", "')}" from that '
        'directory yourself, then re-index. Files of your own alongside them '
        'are not touched by this package.',
      );
    }

    try {
      final open = _client;
      if (open != null) {
        await open.deleteAll();
        return;
      }
      // Nothing adopted yet. Do not go through _ensureClient — it takes a
      // dimension, and inventing one here would CREATE a shard in order to
      // report it empty.
      final storeDir = _storeDirFor(databasePath);
      if (!Directory(storeDir).existsSync()) return; // never written to
      final opened = await QdrantEdgeClient.openExisting(path: storeDir);
      if (opened == null) return; // a directory, but no shard in it
      _client = opened.client;
      _dim = opened.dim;
      _unusableReason = null;
      await opened.client.deleteAll();
    } on QdrantException catch (e) {
      throw VectorStoreException('Failed to clear the qdrant shard', e);
    }
  }

  @override
  Future<void> close() => _serializeLifecycle(_close);

  Future<void> _close() async {
    final c = _client;
    _client = null;
    _dim = null;
    _unusableReason = null;
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
