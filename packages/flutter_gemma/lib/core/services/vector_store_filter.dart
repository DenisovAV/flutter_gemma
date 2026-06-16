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
/// On native platforms backed by qdrant-edge (`flutter_gemma_rag_qdrant`),
/// filters are honored. On the web sqlite store (`flutter_gemma_rag_sqlite`,
/// wa-sqlite) they are silently ignored: pass a filter expecting it to be a
/// no-op rather than expecting it to throw.
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
