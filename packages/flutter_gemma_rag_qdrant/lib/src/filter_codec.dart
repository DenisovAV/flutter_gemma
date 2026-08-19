import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

/// Serializes [Filter] DSL into the JSON envelope accepted by
/// `qe_shard_search_with_filter`.
///
/// Output shape mirrors the qdrant `Filter` REST schema:
///
/// ```json
/// {
///   "must":     [{"key": "...", "match": {"value": ...}}, ...],
///   "should":   [...],
///   "must_not": [...]
/// }
/// ```
///
/// Each bucket is omitted entirely (not set to an empty array) when it
/// contains no conditions — matches the way the qdrant Rust deserializer
/// distinguishes "no constraint" from "match nothing".
///
/// Returns `null` for an [Filter.isEmpty] input, signalling to the caller
/// to use the no-filter codepath (`qe_shard_search` without the JSON
/// envelope) instead of passing an empty `{}` string.
class FilterCodec {
  const FilterCodec._();

  /// Encodes [filter] to a compact JSON string. Returns null for empty filters
  /// AND for filters that, after dropping conditions on fields not declared in
  /// [schema], have nothing left (callers should then skip the filter-aware FFI
  /// entry point and run an unfiltered search).
  ///
  /// Conditions whose key is not in [schema] are SKIPPED — they were never
  /// promoted to a top-level payload key (see [QdrantVectorStore.addDocument]),
  /// so matching on them would silently narrow to zero. Skipping makes an
  /// undeclared key a no-op (same hits as `filter: null`), honoring the
  /// `VectorStoreRepository` contract and matching the sqlite-vec store.
  static String? encode(Filter? filter, FilterSchema schema) {
    if (filter == null || filter.isEmpty) return null;
    final map = <String, Object>{};
    final must = _encodeBucket(filter.must, schema);
    if (must != null) map['must'] = must;
    final should = _encodeBucket(filter.should, schema);
    if (should != null) map['should'] = should;
    final mustNot = _encodeBucket(filter.mustNot, schema);
    if (mustNot != null) map['must_not'] = mustNot;
    if (map.isEmpty) return null; // every condition was undeclared → no-op
    return jsonEncode(map);
  }

  /// Encodes one bucket, dropping conditions on undeclared fields. Returns null
  /// when the bucket is empty or every condition was dropped.
  static List<Map<String, Object>>? _encodeBucket(
    List<Condition>? conditions,
    FilterSchema schema,
  ) {
    if (conditions == null || conditions.isEmpty) return null;
    final encoded = <Map<String, Object>>[
      for (final c in conditions)
        if (schema.fieldFor(c.key) != null)
          // Null means the condition constrains nothing (an unbounded range),
          // so it contributes no clause — the same no-op the SQLite arm applies.
          ?_encodeCondition(c),
    ];
    return encoded.isEmpty ? null : encoded;
  }

  static Map<String, Object>? _encodeCondition(Condition c) {
    switch (c) {
      case FieldEquals(:final key, :final value):
        // A NUMBER is compared by value, not by JSON spelling — `4` and `4.0`
        // are the same number, and a store must not disagree with its sibling
        // about that. qdrant's `match` cannot express it: ValueVariants is an
        // untagged String | Integer | Bool with no float arm (types.rs), so a
        // double `value` fails deserialization outright, and an integer is
        // compared with `as_i64()`, which returns None for a payload of `4.0`
        // and quietly matches nothing. A degenerate range says the same thing
        // in a form qdrant compares numerically.
        if (value is num) {
          return {
            'key': key,
            'range': {'gte': value, 'lte': value},
          };
        }
        return {
          'key': key,
          'match': {'value': value},
        };
      case FieldMatchAny(:final key, :final values):
        return {
          'key': key,
          'match': {'any': values},
        };
      case FieldRange(:final key, :final gte, :final lte):
        // A range with neither bound constrains nothing, so it must match
        // everything — the same no-op the SQLite arm applies. Emitting an empty
        // `range: {}` instead turns it into an existence test there, which
        // EXCLUDES every document whose value is not numeric: the same filter
        // then returns opposite sets on the two backends.
        if (gte == null && lte == null) return null;
        final range = <String, Object>{};
        if (gte != null) range['gte'] = gte;
        if (lte != null) range['lte'] = lte;
        return {'key': key, 'range': range};
    }
  }
}
