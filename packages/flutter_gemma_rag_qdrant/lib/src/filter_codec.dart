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
    var impossible = false;

    // A `must` bucket: everything must hold. A condition matching everything
    // adds nothing; one matching nothing sinks the whole filter.
    final must = <Map<String, Object>>[];
    for (final c in _declared(filter.must, schema)) {
      switch (_encodeCondition(c, schema)) {
        case _Ignored():
          break;
        case _MatchesAll():
          break;
        case _MatchesNone():
          impossible = true;
        case _Clause(:final json):
          must.add(json);
      }
    }
    if (must.isNotEmpty) map['must'] = must;

    // A `should` bucket: at least one must hold. This is where dropping a
    // no-op silently NARROWED the result — a condition that matches everything
    // makes the whole disjunction true, so the bucket must disappear, not lose
    // one arm. And if every arm matches nothing, the bucket is unsatisfiable.
    final shouldConditions = _declared(filter.should, schema);
    if (shouldConditions.isNotEmpty) {
      final should = <Map<String, Object>>[];
      var alwaysTrue = false;
      for (final c in shouldConditions) {
        switch (_encodeCondition(c, schema)) {
          case _Ignored():
            break;
          case _MatchesAll():
            alwaysTrue = true;
          case _MatchesNone():
            break;
          case _Clause(:final json):
            should.add(json);
        }
      }
      if (!alwaysTrue) {
        if (should.isEmpty) {
          impossible = true;
        } else {
          map['should'] = should;
        }
      }
    }

    // A `must_not` bucket: qdrant's check is all(|c| !check(c)), so the two
    // degenerate cases swap places relative to `must`. Excluding something no
    // point matches excludes nothing; excluding something EVERY point matches
    // leaves nothing.
    final mustNot = <Map<String, Object>>[];
    for (final c in _declared(filter.mustNot, schema)) {
      switch (_encodeCondition(c, schema)) {
        case _Ignored():
          break;
        case _MatchesAll():
          impossible = true;
        case _MatchesNone():
          break;
        case _Clause(:final json):
          mustNot.add(json);
      }
    }
    if (mustNot.isNotEmpty) map['must_not'] = mustNot;

    if (impossible) {
      // An empty interval: `Range::check_range` is inclusive at both ends, so
      // `1 <= v <= 0` holds for no number, and a non-numeric payload fails the
      // range check outright. Encoded on a key we actually saw, so the shape
      // stays a well-formed condition rather than a special token.
      final key = _anyKey(filter) ?? '';
      return jsonEncode({
        'must': [
          {
            'key': key,
            'range': {'gte': 1, 'lte': 0},
          },
        ],
      });
    }
    if (map.isEmpty) return null; // every condition was undeclared → no-op
    return jsonEncode(map);
  }

  static Iterable<Condition> _declared(
    List<Condition>? conditions,
    FilterSchema schema,
  ) => (conditions ?? const <Condition>[]).where(
    (c) => schema.fieldFor(c.key) != null,
  );

  static String? _anyKey(Filter filter) {
    for (final bucket in [filter.must, filter.should, filter.mustNot]) {
      if (bucket != null && bucket.isNotEmpty) return bucket.first.key;
    }
    return null;
  }

  static _Contribution _encodeCondition(Condition c, FilterSchema schema) {
    final field = schema.fieldFor(c.key)!;
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
          if (!_isFinite(value)) return const _MatchesNone();
          return _Clause({
            'key': key,
            'range': {'gte': value, 'lte': value},
          });
        }
        if (field.type == FilterFieldType.bool) {
          return _Clause({'should': _boolSpellings(key, value)});
        }
        return _Clause({
          'key': key,
          'match': {'value': value},
        });

      case FieldMatchAny(:final key, :final values):
        // Same trap as FieldEquals above, and it was left here when that one
        // was fixed. AnyVariants is Strings(IndexSet<String>) |
        // Integers(IndexSet<i64>) — no float arm — and the checker compares
        // with `stored.as_i64()`. So `[2020]` misses a `2020.0` payload, and a
        // Dart double in the list fails deserialization outright, throwing out
        // of searchSimilar and breaking the never-throws guarantee.
        //
        // A nested `should` of degenerate ranges says "is one of" in a form
        // qdrant compares numerically. Condition::Filter(Filter) is a legal
        // member of the untagged enum, so this nests.
        // A bool field has two JSON spellings per value (see _boolSpellings),
        // so it always needs the expanded form.
        if (field.type == FilterFieldType.bool) {
          final arms = [for (final v in values) ..._boolSpellings(key, v)];
          if (arms.isEmpty) return const _MatchesNone();
          return _Clause({'should': arms});
        }

        if (values.any((v) => v is num)) {
          final arms = <Map<String, Object>>[];
          for (final v in values) {
            if (v is num) {
              // Non-finite members are dropped, not encoded: they can match no
              // stored value, so they add nothing to a disjunction. Encoding
              // one would have reached jsonEncode, which refuses NaN and
              // ±Infinity and would have thrown the whole search.
              if (!_isFinite(v)) continue;
              arms.add({
                'key': key,
                'range': {'gte': v, 'lte': v},
              });
            } else {
              arms.add({
                'key': key,
                'match': {'value': v},
              });
            }
          }
          if (arms.isEmpty) return const _MatchesNone();
          return _Clause({'should': arms});
        }

        // No numbers and no bools: `match.any` says it directly, and qdrant
        // compares strings by equality, so the compact form is exact.
        // "is one of nothing" matches nothing — the same reading the sqlite arm
        // gives an empty set, and the reason its negation is a no-op.
        if (values.isEmpty) return const _MatchesNone();
        return _Clause({
          'key': key,
          'match': {'any': values},
        });

      case FieldRange(:final key, :final gte, :final lte):
        // A range only means something over a numeric column. On a string or
        // bool field it is ignored — skipped in every bucket — which is what
        // the sqlite arm does and what core documents. Encoding it here made
        // the same filter answer oppositely on the two backends.
        if (field.type != FilterFieldType.number) return const _Ignored();
        // A range with neither bound constrains nothing, so it matches
        // everything — the same reading the SQLite arm applies. Emitting an
        // empty `range: {}` instead turns it into an existence test there,
        // which EXCLUDES every document whose value is not numeric: the same
        // filter then returns opposite sets on the two backends.
        if (gte == null && lte == null) return const _MatchesAll();
        // A non-finite bound cannot be satisfied by any JSON number, and
        // jsonEncode refuses to write it at all.
        if (!_isFinite(gte) || !_isFinite(lte)) return const _MatchesNone();
        final range = <String, Object>{};
        if (gte != null) range['gte'] = gte;
        if (lte != null) range['lte'] = lte;
        return _Clause({'key': key, 'range': range});
    }
  }

  /// Both JSON spellings of a boolean, as a disjunction.
  ///
  /// qdrant stores the payload value verbatim, so `{"archived": true}` is
  /// Bool(true) and `{"archived": 1}` is Integer(1) — two different variants of
  /// an untagged enum, and `match: {value: true}` matches only the first. The
  /// sqlite store coerces both to the integer 1 in a BOOLEAN column, so the
  /// identical filter over identical documents answered differently on the two
  /// backends. Accepting both spellings here is the query-side half of that
  /// fix; it needs no migration of shards already written.
  static List<Map<String, Object>> _boolSpellings(String key, Object? value) {
    final asBool = value is bool ? value : (value is num ? value == 1 : null);
    if (asBool == null) {
      return [
        {
          'key': key,
          'match': {'value': value as Object},
        },
      ];
    }
    return [
      {
        'key': key,
        'match': {'value': asBool},
      },
      {
        'key': key,
        'range': {'gte': asBool ? 1 : 0, 'lte': asBool ? 1 : 0},
      },
    ];
  }

  /// True for a value that is either absent or a number JSON can represent.
  ///
  /// NaN and ±Infinity have no JSON literal, so no stored payload holds one and
  /// no comparison against one can be satisfied. They also make `jsonEncode`
  /// throw (measured: JsonUnsupportedObjectError), which is how they used to
  /// leave `searchSimilar` — breaking the contract that a filter never throws.
  static bool _isFinite(num? value) =>
      value == null || value is! double || value.isFinite;
}

/// What one condition contributes to its bucket.
///
/// A single nullable clause used to stand for both "constrains nothing" and
/// "can never match". Those are opposites in a `should` bucket — dropping the
/// first narrows the result, when it should have made the whole disjunction
/// true — and they swap places again under `must_not`. Naming them apart is
/// what lets the bucket assembler treat each correctly.
sealed class _Contribution {
  const _Contribution();
}

class _MatchesAll extends _Contribution {
  const _MatchesAll();
}

/// Skipped as if never written — a contract choice, not a truth value.
///
/// Core's Condition dartdoc names three degenerate cases and this codec
/// implemented two, so a FieldRange on a declared string/bool field took the
/// _MatchesAll path: `mustNot: [FieldRange(key: 'tag')]` over a string field
/// returned every document on sqlite (which ignores it) and none on qdrant.
/// An ignored condition contributes nothing to ANY bucket, which is exactly
/// what neither of the other two variants means.
class _Ignored extends _Contribution {
  const _Ignored();
}

class _MatchesNone extends _Contribution {
  const _MatchesNone();
}

class _Clause extends _Contribution {
  const _Clause(this.json);
  final Map<String, Object> json;
}
