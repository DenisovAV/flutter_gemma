/// Payload filter applied alongside vector similarity search.
///
/// A [Filter] composes [Condition]s through three logical buckets:
///
///   * **must**       — every condition must match (AND)
///   * **should**     — at least one must match (OR)
///   * **mustNot**    — none may match (NOT)
///
/// Buckets are independent; combining `must` and `mustNot` is the common
/// "find docs matching X but not Y" idiom.
///
/// All conditions reference fields inside a document's metadata JSON. The
/// metadata schema is up to the caller — flutter_gemma does not impose one.
///
/// Backends honor filters over the fields a caller declares filterable via
/// [FilterSchema]: qdrant-edge (`flutter_gemma_rag_qdrant`) promotes them to
/// payload keys, and the sqlite-vec store (`flutter_gemma_rag_sqlite`) to
/// typed `vec0` columns on both native and web. A condition on an undeclared
/// field is a no-op, never an error — pass a filter expecting it to narrow or
/// to be ignored, never to throw.
///
/// Construction is intentionally verbose to keep the rule clear at the
/// call site. Typical usage:
///
/// ```dart
/// final filter = Filter(
///   must: [
///     FieldEquals(key: 'lang', value: 'en'),
///     FieldRange(key: 'price', gte: 10.0, lte: 100.0),
///   ],
///   mustNot: [
///     FieldEquals(key: 'archived', value: true),
///   ],
/// );
/// ```
class Filter {
  /// All conditions in this list must match (logical AND).
  final List<Condition>? must;

  /// At least one condition in this list must match (logical OR).
  final List<Condition>? should;

  /// No condition in this list may match (logical NOT).
  final List<Condition>? mustNot;

  const Filter({this.must, this.should, this.mustNot});

  /// True when this filter has no active condition. Used internally by
  /// repositories to skip the filter argument entirely on the storage side.
  bool get isEmpty =>
      (must == null || must!.isEmpty) &&
      (should == null || should!.isEmpty) &&
      (mustNot == null || mustNot!.isEmpty);
}

/// A single predicate over one metadata field. Sealed because the storage
/// codec needs to switch over the concrete subtype — adding a new condition
/// without updating the codec would silently drop it.
sealed class Condition {
  const Condition();

  /// JSON key in the document's metadata payload that this condition tests.
  String get key;
}

/// `metadata[key] == value` exact match.
///
/// [value] must be one of `String`, `int`, `double`, `bool` — JSON scalars.
/// Lists and objects are not supported here; use [FieldMatchAny] for
/// "value is one of N" semantics instead.
///
/// **Numbers compare by value, not by JSON spelling.** `4` and `4.0` are the
/// same number and must match the same documents, whichever way either side
/// happens to be written. JSON does not distinguish them, so a store that does
/// is wrong — and both did, in opposite directions: qdrant compared an integer
/// with `as_i64()`, which silently matched nothing against a `4.0` payload and
/// rejected a `double` value outright, while SQLite coerced both and matched.
/// Backends must normalise; callers should not have to know which store they
/// are on.
///
/// Strings and bools compare exactly. A document that does not carry [key] at
/// all never satisfies this condition — so it is excluded by `must` and, by the
/// same rule, RETURNED by `mustNot`.
class FieldEquals extends Condition {
  @override
  final String key;
  final Object value;

  const FieldEquals({required this.key, required this.value})
    : assert(
        value is String || value is num || value is bool,
        'FieldEquals.value must be String, num, or bool',
      );
}

/// `gte <= metadata[key] <= lte` numeric range. Either bound may be null
/// for one-sided ranges (e.g. `gte: 10` matches anything >= 10).
///
/// **With NEITHER bound the condition constrains nothing, so it matches
/// everything** — it is a no-op, not an "is this key present" test. The two
/// backends used to disagree here in opposite directions: SQLite dropped the
/// clause (matching everything) while qdrant emitted an empty `range: {}`,
/// which its checker reads as an existence test and which therefore EXCLUDED
/// every document whose value is not numeric. One filter, opposite result sets.
///
/// Ranges apply to numeric fields only. On a string or bool field the condition
/// is a no-op rather than an error — see [Filter] on why filters do not throw.
/// ## Degenerate conditions
///
/// Two kinds of condition do nothing, and they are NOT the same thing:
///
///   * **Ignored** — the condition is skipped as if it were never written:
///     a key not declared in the [FilterSchema], or a [FieldRange] on a
///     non-numeric field. Both stores drop it from every bucket, so the result
///     is identical to omitting it. This is a contract choice (see [Filter] on
///     why filters do not throw), not a truth value.
///   * **Always true / always false** — the condition IS evaluated and has a
///     constant answer: an unbounded [FieldRange] matches every document, and
///     a [FieldMatchAny] over an empty list matches none.
///
/// The difference only shows once a bucket is not a conjunction. In `should`
/// (an OR) a condition that matches everything makes the whole bucket true, so
/// dropping it NARROWS the result; in `mustNot` the two swap places, because
/// the check is "no condition may match" — excluding something every document
/// satisfies leaves nothing, and excluding something no document satisfies
/// excludes nothing. Both stores encode this per bucket.
///
/// ## Non-finite numbers
///
/// NaN and ±Infinity have no JSON literal, so no stored payload can hold one:
/// a comparison against one matches nothing. Both stores implement exactly
/// that, and neither throws — measured, `jsonEncode` rejects all three, which
/// is how they used to escape qdrant's `searchSimilar`, and on sqlite
/// -Infinity is the absent-value sentinel, so `FieldEquals(f, -inf)` returned
/// precisely the documents that have no `f` at all. [FieldRange] additionally
/// asserts its bounds are finite — an early warning at the call site, not a
/// different rule; asserts vanish in release, where the stores' handling is
/// what holds.
class FieldRange extends Condition {
  @override
  final String key;

  /// Inclusive lower bound. Null means no lower bound.
  final double? gte;

  /// Inclusive upper bound. Null means no upper bound.
  final double? lte;

  const FieldRange({required this.key, this.gte, this.lte})
    : assert(
        gte == null ||
            gte != double.infinity &&
                gte != double.negativeInfinity &&
                gte == gte,
        'FieldRange.gte must be finite',
      ),
      assert(
        lte == null ||
            lte != double.infinity &&
                lte != double.negativeInfinity &&
                lte == lte,
        'FieldRange.lte must be finite',
      );
}

/// `metadata[key] in values` set membership. Equivalent to N [FieldEquals]
/// wrapped in a `should` bucket, but expressed in one place and serialized
/// more efficiently on the storage side.
class FieldMatchAny extends Condition {
  @override
  final String key;

  /// At least one of these values must equal `metadata[key]`. Empty list is
  /// allowed and acts as "match nothing" (the condition can never be true).
  final List<Object> values;

  const FieldMatchAny({required this.key, required this.values});
}

/// The storage type of a declared filterable metadata field.
///
/// Maps a [FilterField] onto the typed column / payload type the backend
/// promotes it to, so that [Filter] predicates can be pushed down to the
/// storage engine (vec0 typed metadata columns, qdrant top-level payload keys)
/// instead of being evaluated in Dart.
enum FilterFieldType { string, number, bool }

/// A single metadata field a store is told to make filterable.
///
/// Declared up-front via [FilterSchema] (see [VectorStoreRepository.configure]).
/// The [name] is the metadata JSON key, shared verbatim across backends so the
/// same schema means the same namespace on qdrant and sqlite/vec0.
///
/// ## Name rules
///
/// [name] must match [namePattern] — an ASCII letter, then ASCII letters,
/// digits or underscores (`^[A-Za-z][A-Za-z0-9_]*$`). Anything else is rejected
/// by [validateName], which each store calls from `configure()` — so the throw
/// lands when the schema is handed to a store, NOT at the `FilterField(…)`
/// declaration. The constructor is `const` and can only assert (see below), so
/// it catches an empty name in development and nothing at all in release.
///
/// The rule is not a stylistic preference, it is the intersection of what the
/// backends can express, and `vec0` is the binding constraint:
///
///   * `vec0` promotes each declared field to a real column in its
///     `CREATE VIRTUAL TABLE … USING vec0(…)` DDL, which is parsed by
///     sqlite-vec's own tokenizer, not SQLite's. That tokenizer accepts an
///     identifier as `[A-Za-z][A-Za-z0-9_]*` and nothing else — measured on
///     vec0 0.1.9, `doc-type TEXT` fails with
///     `vec0 constructor error: Could not parse 'doc-type TEXT'`.
///   * Quoting cannot rescue it. `"doc-type"`, `[doc-type]` and
///     `` `doc-type` `` were each measured against vec0 0.1.9 and each fails
///     the same way — sqlite-vec's DDL grammar has no quoted-identifier form
///     at all. So an out-of-set name is unrepresentable, not merely unescaped,
///     and rejecting it is the only option.
///   * A name carrying a comma is worse than an error: the store renders
///     `'$name $type'` into the DDL, so `FilterField(name: 'a TEXT, b')`
///     silently declares **two** columns (measured: `pragma_table_info`
///     reports both `a` and `b`) and the schema no longer describes the table.
///   * qdrant payload keys are free-form UTF-8, so this set is a strict subset
///     of what qdrant accepts — every name that passes here means the same
///     thing on both backends. That is the point of the shared schema, and it
///     is why the rule is enforced here rather than inside one store.
///   * `.` is rejected for a reason that holds on qdrant independently: qdrant
///     reads `.` as a nested payload-path separator, so `doc.type` would mean
///     "field `type` nested inside `doc`" there and a flat column on vec0. The
///     same declaration would denote two different things.
///
/// The constructor stays `const` — `const FilterSchema(fields: [FilterField(…)])`
/// is the documented idiom and dropping it would break every caller. A `const`
/// constructor can only `assert`, and asserts vanish in release, so the assert
/// here is the fast path for development only: the load-bearing check is
/// [validateName], called by each store in `configure()` where it runs in every
/// build. A name computed at runtime — from a config file or JSON — is caught
/// there rather than reaching the DDL.
class FilterField {
  /// The only shape [name] may take: an ASCII letter followed by ASCII
  /// letters, digits or underscores. Mirrors sqlite-vec's `vec0` identifier
  /// tokenizer, which is the narrowest grammar the name must survive.
  static final RegExp namePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  /// Metadata JSON key promoted to a filterable storage field.
  final String name;

  /// Storage type used when promoting and when binding [Filter] predicates.
  final FilterFieldType type;

  const FilterField({required this.name, required this.type})
    : assert(
        // Development-only: see validateName for the check that survives
        // release. Duplicated as a literal because a const assert cannot call
        // a method or touch a static field.
        name != '',
        'FilterField.name must not be empty',
      );

  /// Throws [ArgumentError] when [name] cannot be represented as a storage
  /// identifier. Stores call this from `configure()`, so it runs in release
  /// builds too — unlike the constructor's assert.
  ///
  /// Measured against vec0 0.1.9: `doc-type TEXT` fails the table constructor
  /// outright, and `a TEXT, b` silently declares TWO columns. No quoting form
  /// helps — `"doc-type"`, `[doc-type]` and backticks all fail, because
  /// sqlite-vec parses its own DDL with a hand-rolled tokenizer that has no
  /// quoted-identifier production. So the name has to be rejected, not escaped.
  ///
  /// The charset is not a preference: it is vec0's identifier grammar, the
  /// narrowest the name must survive. qdrant payload keys are free-form UTF-8,
  /// so every accepted name means the same thing on both backends — and `.` is
  /// excluded on its own merits, since qdrant reads it as a nested-payload
  /// separator.
  /// Names the sqlite arm cannot use, because its `vec0` table already
  /// declares them.
  ///
  /// MEASURED against vec0 0.1.9, not assumed: declaring any of these as a
  /// filter field makes the CREATE VIRTUAL TABLE fail outright —
  /// `vec0 constructor error: could not declare virtual table`. Not a silent
  /// mis-read, a hard refusal.
  ///
  /// Two reasons this belongs in core rather than in the sqlite store. The
  /// failure is LATE: the table is created lazily on the first addDocument, so
  /// a schema the developer wrote at startup blows up much later and points at
  /// an insert. And it is one-sided: qdrant namespaces its own payload keys
  /// (`__flutter_gemma_*`), so the same schema works there — the same
  /// FilterSchema succeeding on one backend and failing on the other is the
  /// divergence this file exists to prevent.
  static const reservedNames = {
    'id',
    'embedding',
    'content',
    'metadata',
    'distance',
  };

  /// Rejects a [FilterSchema] that no backend could implement identically.
  ///
  /// Called from each store's `configure()`. It replaced three copies of the
  /// same loop — and the copies had already stopped agreeing about what a
  /// schema means, which is exactly how a shared contract rots.
  static void validateSchema(FilterSchema schema) {
    final seen = <String>{};
    for (final field in schema.fields) {
      validateName(field.name);
      // A duplicate is meaningless — fieldFor returns the first match — and it
      // is not harmless: the native sqlite arm builds its INSERT from
      // `schema.fields` (duplicates kept) while the web arm builds it from the
      // declaredColumnValues map (duplicates collapsed), so the two arms
      // emitted different column lists for the same document.
      if (!seen.add(field.name)) {
        throw ArgumentError.value(
          field.name,
          'FilterSchema.fields',
          'duplicate filter field name',
        );
      }
    }
  }

  static void validateName(String name) {
    if (reservedNames.contains(name)) {
      throw ArgumentError.value(
        name,
        'FilterField.name',
        'reserved: the sqlite vec0 table already declares this column '
            '(measured: the table refuses to be created)',
      );
    }
    if (!namePattern.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'FilterField.name',
        'must match ^[A-Za-z][A-Za-z0-9_]*\$ (an ASCII letter, then letters, '
            'digits or underscores). It is promoted to a sqlite-vec `vec0` '
            'column, whose DDL grammar has no quoted identifier form, so this '
            'name cannot be represented there',
      );
    }
  }
}

/// The set of metadata fields a store should make filterable.
///
/// Passed once at registration through `FlutterGemma.initialize(filterSchema:)`
/// and handed to the store via [VectorStoreRepository.configure] before
/// [VectorStoreRepository.initialize]. An empty schema (the default) leaves
/// every store in its existing "filters are a safe no-op" mode.
class FilterSchema {
  /// Declared filterable fields. Empty by default → no filterable columns.
  final List<FilterField> fields;

  const FilterSchema({this.fields = const []});

  /// True when no field is declared (filtering stays a no-op).
  bool get isEmpty => fields.isEmpty;

  /// The declared field for [name], or null when [name] is not in the schema.
  ///
  /// Backends use this to skip undeclared keys (documented no-op, never a
  /// throw) when translating a [Filter].
  FilterField? fieldFor(String name) {
    for (final field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }
}
