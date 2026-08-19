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

  // The name is interpolated bare into sqlite-vec's `vec0(...)` DDL, whose
  // grammar accepts an identifier as `[A-Za-z][A-Za-z0-9_]*` and offers no
  // quoted form to escape into. Measured against vec0 0.1.9:
  //   * `doc-type TEXT` -> `vec0 constructor error: Could not parse
  //     'doc-type TEXT'`, and `"doc-type"` / `[doc-type]` / backticks all fail
  //     the same way;
  //   * `a TEXT, b TEXT` (what `FilterField(name: 'a TEXT, b')` renders)
  //     succeeds and silently declares TWO columns.
  // So the name is validated at declaration. These must throw in release too,
  // hence a real throw rather than an assert.
  group('FilterField.name validation', () {
    test('accepts letters, digits and underscores after a leading letter', () {
      for (final name in ['lang', 'docType', 'doc_type', 'a1', 'x', 'order']) {
        expect(
          FilterField(name: name, type: FilterFieldType.string).name,
          name,
          reason: '$name is a legal bare vec0 identifier',
        );
      }
    });

    test('rejects a hyphen — the measured vec0 DDL parse failure', () {
      expect(
        () => FilterField.validateName('doc-type'),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 'doc-type')
              .having((e) => e.name, 'name', 'FilterField.name'),
        ),
      );
    });

    test('rejects a comma — the measured silent two-column declaration', () {
      expect(
        () => FilterField.validateName('a TEXT, b'),
        throwsArgumentError,
      );
    });

    test('rejects a dot — qdrant would read it as a nested payload path', () {
      expect(
        () => FilterField.validateName('doc.type'),
        throwsArgumentError,
      );
    });

    test('rejects a double quote — it could terminate a quoted identifier', () {
      expect(
        () => FilterField.validateName('a"b'),
        throwsArgumentError,
      );
    });

    test('rejects empty, leading digit, leading underscore and whitespace', () {
      for (final name in [
        '',
        '1lang',
        '_lang',
        'doc type',
        'lang\n',
        ' lang',
      ]) {
        expect(
          () => FilterField.validateName(name),
          throwsArgumentError,
          reason: '"$name" is not a legal bare vec0 identifier',
        );
      }
    });

    test('rejects non-ASCII letters vec0 is_alpha() does not accept', () {
      for (final name in ['naïve', 'категория', '语言']) {
        expect(
          () => FilterField.validateName(name),
          throwsArgumentError,
          reason: 'vec0 is_alpha() is ASCII-only',
        );
      }
    });

    test('validation survives release mode (a real throw, not an assert)', () {
      // Guards against a regression to `assert(...)`. The constructor stays
      // const — `const FilterSchema(fields: [FilterField(…)])` is the
      // documented idiom and dropping it would break every caller — so the
      // load-bearing check lives in validateName, which each store calls from
      // configure(). An assert there would be stripped in release, exactly
      // where a name read from config at runtime reaches the DDL. Assert on
      // the MECHANISM: the type thrown must be ArgumentError, which an assert
      // never produces.
      Object? thrown;
      try {
        FilterField.validateName('doc-type');
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ArgumentError>());
      expect(thrown, isNot(isA<AssertionError>()));
    });
  });
}
