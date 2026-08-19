import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_rag_qdrant/src/filter_codec.dart';

Map<String, dynamic> _decode(String? json) {
  expect(json, isNotNull);
  return jsonDecode(json!) as Map<String, dynamic>;
}

/// Schema declaring every field the tests filter on. Conditions on a field NOT
/// in the schema are skipped (no-op), so all happy-path tests declare theirs.
final _schema = FilterSchema(
  fields: [
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'tag', type: FilterFieldType.string),
    FilterField(name: 'price', type: FilterFieldType.number),
    FilterField(name: 'archived', type: FilterFieldType.bool),
    FilterField(name: 'k', type: FilterFieldType.number),
  ],
);

void main() {
  _crossBackendParityTests();

  group('FilterCodec.encode', () {
    test('null filter → null output', () {
      expect(FilterCodec.encode(null, _schema), isNull);
    });

    test('empty filter → null output (skips the FFI filter branch)', () {
      expect(FilterCodec.encode(const Filter(), _schema), isNull);
    });

    test('undeclared key → null output (no-op, same hits as filter:null)', () {
      // Mirrors the sqlite-vec store: a condition on a field not in the schema
      // is skipped rather than narrowing the search to zero.
      expect(
        FilterCodec.encode(
          const Filter(
            must: [FieldEquals(key: 'not_declared', value: 'x')],
          ),
          _schema,
        ),
        isNull,
      );
    });

    test('declared + undeclared in one bucket → only declared survives', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(
            must: [
              FieldEquals(key: 'lang', value: 'en'),
              FieldEquals(key: 'not_declared', value: 'x'),
            ],
          ),
          _schema,
        ),
      );
      expect(json['must'], hasLength(1));
      expect(json['must'][0]['key'], 'lang');
    });

    test('FieldEquals encodes to match.value', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(
            must: [FieldEquals(key: 'lang', value: 'en')],
          ),
          _schema,
        ),
      );
      expect(json, {
        'must': [
          {
            'key': 'lang',
            'match': {'value': 'en'},
          },
        ],
      });
    });

    test('FieldMatchAny encodes to match.any', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(
            should: [
              FieldMatchAny(key: 'tag', values: ['a', 'b', 'c']),
            ],
          ),
          _schema,
        ),
      );
      expect(json, {
        'should': [
          {
            'key': 'tag',
            'match': {
              'any': ['a', 'b', 'c'],
            },
          },
        ],
      });
    });

    test('FieldRange encodes to range with optional gte/lte', () {
      final both = _decode(
        FilterCodec.encode(
          const Filter(must: [FieldRange(key: 'price', gte: 10.0, lte: 100.0)]),
          _schema,
        ),
      );
      expect(both['must'][0]['range'], {'gte': 10.0, 'lte': 100.0});

      final gteOnly = _decode(
        FilterCodec.encode(
          const Filter(must: [FieldRange(key: 'price', gte: 10.0)]),
          _schema,
        ),
      );
      expect(gteOnly['must'][0]['range'], {'gte': 10.0});
      expect(gteOnly['must'][0]['range'].containsKey('lte'), isFalse);

      final lteOnly = _decode(
        FilterCodec.encode(
          const Filter(must: [FieldRange(key: 'price', lte: 100.0)]),
          _schema,
        ),
      );
      expect(lteOnly['must'][0]['range'], {'lte': 100.0});
      expect(lteOnly['must'][0]['range'].containsKey('gte'), isFalse);
    });

    test('mustNot serializes to snake_case must_not (qdrant wire format)', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(mustNot: [FieldEquals(key: 'archived', value: true)]),
          _schema,
        ),
      );
      expect(json.keys, contains('must_not'));
      expect(json.keys, isNot(contains('mustNot')));
    });

    test('combined must + mustNot serializes all buckets', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(
            must: [
              FieldEquals(key: 'lang', value: 'en'),
              FieldRange(key: 'price', gte: 50.0),
            ],
            mustNot: [FieldEquals(key: 'archived', value: true)],
          ),
          _schema,
        ),
      );
      expect(json['must'], hasLength(2));
      expect(json['must_not'], hasLength(1));
      expect(
        json.containsKey('should'),
        isFalse,
        reason: 'empty buckets are omitted, not serialized as []',
      );
    });

    test('empty buckets are omitted from output', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(
            must: [FieldEquals(key: 'k', value: 1)],
            should: [],
          ),
          _schema,
        ),
      );
      expect(json.keys, equals({'must'}));
    });
  });
}

/// One filter, both encodings, same meaning.
///
/// Findings 3, 4 and 8 of the RAG audit were all the same shape: SQLite and
/// qdrant answered the SAME filter differently, and nothing compared them. The
/// canonical semantics now live in the core dartdoc (`vector_store_filter.dart`
/// on [FieldEquals] and [FieldRange]); these assert the qdrant half honours
/// them, so a future divergence fails here instead of in a user's results.
void _crossBackendParityTests() {
  group('canonical semantics — qdrant half', () {
    test('numeric equality is encoded by value, not by JSON spelling', () {
      // `match` cannot carry it: ValueVariants is untagged String|Integer|Bool,
      // so a double is rejected at deserialization and an integer is compared
      // with as_i64(), which returns None for a payload of 4.0. A degenerate
      // range compares numerically and accepts both spellings.
      for (final value in <num>[4, 4.0]) {
        final json = _decode(
          FilterCodec.encode(
            Filter(must: [FieldEquals(key: 'price', value: value)]),
            _schema,
          ),
        );
        final cond = (json['must'] as List).single as Map<String, dynamic>;
        expect(cond['match'], isNull, reason: 'match cannot express 4 == 4.0');
        expect(cond['range'], {'gte': value, 'lte': value});
      }
    });

    test('a string equality still uses match', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(must: [FieldEquals(key: 'lang', value: 'en')]),
          _schema,
        ),
      );
      final cond = (json['must'] as List).single as Map<String, dynamic>;
      expect(cond['match'], {'value': 'en'});
    });

    test('a range with neither bound contributes no clause', () {
      // Not `range: {}` — qdrant reads that as an existence test and excludes
      // every non-numeric document, the opposite of the SQLite arm's no-op.
      final json = FilterCodec.encode(
        const Filter(must: [FieldRange(key: 'price')]),
        _schema,
      );
      expect(json, isNull, reason: 'a no-op condition leaves nothing to send');
    });

    test('a one-sided range still encodes that bound', () {
      final json = _decode(
        FilterCodec.encode(
          const Filter(must: [FieldRange(key: 'price', gte: 10)]),
          _schema,
        ),
      );
      final cond = (json['must'] as List).single as Map<String, dynamic>;
      expect(cond['range'], {'gte': 10});
    });
  });
}
