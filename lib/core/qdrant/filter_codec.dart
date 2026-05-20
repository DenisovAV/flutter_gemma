import 'dart:convert';

import 'package:flutter_gemma/core/services/vector_store_filter.dart';

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

  /// Encodes [filter] to a compact JSON string. Returns null for empty
  /// filters (callers should skip the filter-aware FFI entry point).
  static String? encode(Filter? filter) {
    if (filter == null || filter.isEmpty) return null;
    final map = <String, Object>{};
    if (filter.must != null && filter.must!.isNotEmpty) {
      map['must'] = filter.must!.map(_encodeCondition).toList();
    }
    if (filter.should != null && filter.should!.isNotEmpty) {
      map['should'] = filter.should!.map(_encodeCondition).toList();
    }
    if (filter.mustNot != null && filter.mustNot!.isNotEmpty) {
      map['must_not'] = filter.mustNot!.map(_encodeCondition).toList();
    }
    return jsonEncode(map);
  }

  static Map<String, Object> _encodeCondition(Condition c) {
    switch (c) {
      case FieldEquals(:final key, :final value):
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
        final range = <String, Object>{};
        if (gte != null) range['gte'] = gte;
        if (lte != null) range['lte'] = lte;
        return {'key': key, 'range': range};
    }
  }
}
