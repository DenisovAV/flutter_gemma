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
const _schema = FilterSchema(
  fields: [
    FilterField(name: 'lang', type: FilterFieldType.string),
    FilterField(name: 'tag', type: FilterFieldType.string),
    FilterField(name: 'price', type: FilterFieldType.number),
    FilterField(name: 'archived', type: FilterFieldType.bool),
    FilterField(name: 'k', type: FilterFieldType.number),
  ],
);

void main() {
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
