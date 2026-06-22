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
class FilterField {
  /// Metadata JSON key promoted to a filterable storage field.
  final String name;

  /// Storage type used when promoting and when binding [Filter] predicates.
  final FilterFieldType type;

  const FilterField({required this.name, required this.type});
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
