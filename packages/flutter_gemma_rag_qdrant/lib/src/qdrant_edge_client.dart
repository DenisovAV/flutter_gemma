import 'dart:convert';
import 'dart:io';

import 'package:qdrant_edge/qdrant_edge.dart' as qe;

/// Distance metric used by a qdrant-edge shard. Set at open time and fixed
/// for the shard's lifetime.
enum Distance {
  /// 1 - cosine angle between vectors. Most common for text embeddings;
  /// expects (but does not require) unit-norm inputs.
  cosine('cosine'),

  /// Dot product. For unit-norm vectors equivalent to cosine.
  dot('dot'),

  /// Euclidean (L2) distance.
  euclid('euclid'),

  /// Manhattan (L1) distance.
  manhattan('manhattan');

  final String wireName;
  const Distance(this.wireName);

  qe.Distance get _native => switch (this) {
    Distance.cosine => qe.Distance.cosine,
    Distance.dot => qe.Distance.dot,
    Distance.euclid => qe.Distance.euclid,
    Distance.manhattan => qe.Distance.manhattan,
  };
}

/// One search hit returned by [QdrantEdgeClient.search].
class SearchHit {
  /// Point ID as stored — typically a UUIDv5 string for points written via
  /// flutter_gemma's high-level repository.
  final String id;

  /// Similarity score per the shard's [Distance] metric. Cosine returns
  /// in [-1, 1] (close to 1 = similar); for L2/Manhattan, lower = more
  /// similar (semantics inverted from cosine — be careful when threshold-
  /// filtering downstream).
  final double score;

  /// Decoded payload object if the point had one, otherwise null.
  final Map<String, dynamic>? payload;

  const SearchHit({required this.id, required this.score, this.payload});
}

/// Typed wrapper around any failure surfaced by the qdrant-edge engine. The
/// UniFFI layer raises typed [qe.EdgeException]s; we flatten them into a single
/// [message] so the rest of the package keeps catching one exception type.
class QdrantException implements Exception {
  final String message;
  const QdrantException(this.message);

  @override
  String toString() => 'QdrantException: $message';
}

/// High-level Dart wrapper over the official Qdrant Edge SDK ([qe.EdgeShard]).
///
/// This backs [QdrantVectorStore]; it is not meant for direct use by
/// application code. It owns exactly one [qe.EdgeShard] (the on-disk shard) and
/// adapts the typed SDK API to the JSON-payload / JSON-filter surface the rest
/// of flutter_gemma's RAG layer expects.
///
/// The native engine is delivered by the `qdrant_edge` package's Native Assets
/// build hook — there is no manual `DynamicLibrary.open`; the SDK's generated
/// binding resolves its symbols through the registered code asset, and
/// [qe.EdgeShard] carries its own finalizer, so a dropped client is still
/// released even without an explicit [close].
class QdrantEdgeClient {
  final qe.EdgeShard _shard;
  bool _closed = false;

  QdrantEdgeClient._(this._shard);

  /// Open (or create) a shard on disk.
  ///
  /// `path` is a directory — qdrant-edge stores its WAL + segment files under
  /// it (created if absent). `dim` is the vector dimension; once a shard is
  /// created with a given dim, subsequent opens must pass the same value or the
  /// engine rejects the reopen.
  static Future<QdrantEdgeClient> open({
    required String path,
    required int dim,
    Distance distance = Distance.cosine,
  }) async {
    try {
      // The engine creates its WAL/segment subdirs UNDER `path` but does not
      // create `path` itself (non-recursive), so ensure the shard directory
      // exists first — matching the historical shim, which mkdir-p'd it.
      Directory(path).createSync(recursive: true);
      // Single unnamed vector field, mirroring the historical shim contract
      // (one vector per point, addressed by the empty name).
      final config = qe.EdgeConfig(
        vectorData: {
          '': qe.VectorDataConfig(size: dim, distance: distance._native),
        },
      );
      return QdrantEdgeClient._(qe.EdgeShard.load(path: path, config: config));
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Upsert one point. `payload` may be omitted (`null`) or any JSON-encodable
  /// Map — it is stored as a JSON string in the point payload.
  Future<void> upsert({
    required String id,
    required List<double> vector,
    Map<String, dynamic>? payload,
  }) async {
    _checkOpen();
    try {
      _shard.update(
        operation: qe.UpdateOperation.upsertPoints(
          points: [_point(id, vector, payload)],
        ),
      );
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Bulk upsert — one shard update carrying every point.
  Future<void> upsertBatch(
    List<({String id, List<double> vector, Map<String, dynamic>? payload})>
    points,
  ) async {
    _checkOpen();
    if (points.isEmpty) return;
    try {
      _shard.update(
        operation: qe.UpdateOperation.upsertPoints(
          points: [
            for (final p in points) _point(p.id, p.vector, p.payload),
          ],
        ),
      );
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Top-K nearest-neighbour search. Pass [filterJson] (the JSON envelope
  /// produced by `FilterCodec.encode`) to constrain by payload; pass null to
  /// run unfiltered.
  Future<List<SearchHit>> search({
    required List<double> queryVector,
    required int topK,
    String? filterJson,
  }) async {
    _checkOpen();
    try {
      final results = _shard.search(
        request: qe.SearchRequest(
          query: qe.NearestQuery(
            vector: qe.DenseNamedVector(queryVector),
            using: null,
          ),
          limit: topK,
          filter: _filterFromJson(filterJson),
          withPayload: qe.BoolWithPayload(true),
        ),
      );
      return [
        for (final sp in results)
          SearchHit(
            id: _idString(sp.id),
            score: sp.score,
            payload: _decodePayload(sp.payload),
          ),
      ];
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Delete points by IDs. No-op for IDs that don't exist.
  Future<void> delete(List<String> ids) async {
    _checkOpen();
    if (ids.isEmpty) return;
    try {
      _shard.update(
        operation: qe.UpdateOperation.deletePoints(
          pointIds: [for (final id in ids) qe.UuidPointId(id)],
        ),
      );
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Exact total number of points currently in the shard.
  Future<int> count() async {
    _checkOpen();
    try {
      return _shard.count(request: qe.CountRequest());
    } on qe.EdgeException catch (e) {
      throw QdrantException(_flatten(e));
    }
  }

  /// Close the shard. Idempotent — safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _shard.unload();
    } on qe.EdgeException {
      // Best-effort: an already-unloaded shard is fine to ignore on close.
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const QdrantException('QdrantEdgeClient is closed');
    }
  }

  qe.Point _point(String id, List<double> vector, Map<String, dynamic>? payload) {
    return qe.Point(
      id: qe.UuidPointId(id),
      vector: qe.SingleVector(vector),
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  static String _idString(qe.PointId id) => switch (id) {
    qe.UuidPointId(:final value) => value,
    qe.NumIdPointId(:final value) => value.toString(),
    _ => id.toString(),
  };

  static Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null) return null;
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static String _flatten(qe.EdgeException e) => e.toString();

  // ---- Filter bridge: qdrant JSON envelope → typed qe.Filter ----------------

  /// Translates the JSON filter envelope emitted by `FilterCodec.encode`
  /// (`{"must":[...],"should":[...],"must_not":[...]}`, each condition one of
  /// `{"key","match":{"value"|"any"}}` or `{"key","range":{...}}`) into the
  /// SDK's typed [qe.Filter]. Returns null for a null/empty envelope so the
  /// caller runs an unfiltered search.
  static qe.Filter? _filterFromJson(String? filterJson) {
    if (filterJson == null) return null;
    final map = jsonDecode(filterJson);
    if (map is! Map<String, dynamic>) return null;

    List<qe.Condition>? bucket(String key) {
      final raw = map[key];
      if (raw is! List || raw.isEmpty) return null;
      return [
        for (final c in raw)
          if (c is Map<String, dynamic>) _conditionFromJson(c),
      ];
    }

    final must = bucket('must');
    final should = bucket('should');
    final mustNot = bucket('must_not');
    if (must == null && should == null && mustNot == null) return null;
    return qe.Filter(must: must, should: should, mustNot: mustNot);
  }

  static qe.Condition _conditionFromJson(Map<String, dynamic> c) {
    final key = c['key'] as String;
    qe.Match? match;
    qe.RangeFloat? range;

    final m = c['match'];
    if (m is Map<String, dynamic>) {
      if (m.containsKey('value')) {
        match = qe.ValueMatch(_valueVariants(m['value']));
      } else if (m['any'] is List) {
        match = qe.AnyMatch(_anyVariants(m['any'] as List));
      }
    }

    final r = c['range'];
    if (r is Map<String, dynamic>) {
      double? n(Object? v) => (v as num?)?.toDouble();
      range = qe.RangeFloat(
        gte: n(r['gte']),
        gt: n(r['gt']),
        lte: n(r['lte']),
        lt: n(r['lt']),
      );
    }

    return qe.FieldConditionVariant(
      qe.FieldCondition(key: key, match: match, range: range),
    );
  }

  static qe.ValueVariants _valueVariants(Object? v) {
    if (v is bool) return qe.BoolValueVariants(v);
    if (v is int) return qe.IntegerValueVariants(v);
    return qe.StringValueVariants(v.toString());
  }

  static qe.AnyVariants _anyVariants(List values) {
    if (values.isNotEmpty && values.every((e) => e is int)) {
      return qe.IntegersAnyVariants(values.cast<int>());
    }
    return qe.StringsAnyVariants([for (final e in values) e.toString()]);
  }
}
