import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Filter.isEmpty', () {
    test('default constructor is empty', () {
      expect(const Filter().isEmpty, isTrue);
    });

    test('explicit empty lists are empty', () {
      expect(const Filter(must: [], should: [], mustNot: []).isEmpty, isTrue);
    });

    test('any non-empty bucket flips isEmpty to false', () {
      expect(
        const Filter(must: [FieldEquals(key: 'k', value: 1)]).isEmpty,
        isFalse,
      );
      expect(
        const Filter(should: [FieldEquals(key: 'k', value: 1)]).isEmpty,
        isFalse,
      );
      expect(
        const Filter(mustNot: [FieldEquals(key: 'k', value: 1)]).isEmpty,
        isFalse,
      );
    });
  });
}
