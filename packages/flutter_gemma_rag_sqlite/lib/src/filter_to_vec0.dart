import 'package:flutter_gemma/flutter_gemma.dart';

/// Translates a [Filter] into a SQL `WHERE` fragment over vec0's declared
/// typed metadata columns, plus the ordered bind list.
///
/// vec0 KNN only filters on columns declared in the `vec0(...)` DDL
/// (TEXT/INT/FLOAT/BOOLEAN, max 16), with operators `= != > >= < <= BETWEEN IN`.
/// `json_extract` and auxiliary `+` columns are NOT filterable — so this
/// translator maps each [Condition] onto a single declared column by its
/// [FilterField.name].
///
/// Contract (mirrors [VectorStoreRepository]'s never-throws filter guarantee):
///   * A condition whose key is NOT in [FilterSchema] is **skipped** — a
///     documented no-op, never an error. The same applies to a [FieldRange]
///     with both bounds null (no constraint to express).
///   * An empty / all-skipped [Filter] yields an empty `whereSql` and empty
///     `binds`; the caller runs the unfiltered KNN.
///   * Booleans bind as `0`/`1` (vec0 has no boolean literal in bound params).
///
/// Bucket semantics match [Filter]:
///   * `must`    — conditions AND-joined.
///   * `should`  — conditions OR-joined, wrapped in one parenthesised group.
///   * `mustNot` — conditions AND-joined, negated as `NOT (...)`.
/// Buckets are themselves AND-joined together.
class FilterToVec0 {
  const FilterToVec0._();

  /// Translates [filter] against [schema] into a vec0 `WHERE` fragment.
  ///
  /// The returned [whereSql] does NOT include the leading `WHERE`/`AND` — the
  /// caller splices it in after `embedding MATCH ? AND k = ?`. It is empty when
  /// there is nothing to filter on.
  static ({String whereSql, List<Object?> binds}) translate(
    Filter? filter,
    FilterSchema schema,
  ) {
    if (filter == null || filter.isEmpty) {
      return (whereSql: '', binds: const []);
    }

    final binds = <Object?>[];
    final groups = <String>[];

    final mustSql = _joinConditions(filter.must, schema, binds, ' AND ');
    if (mustSql != null) groups.add(mustSql);

    final shouldSql = _joinConditions(filter.should, schema, binds, ' OR ');
    if (shouldSql != null) groups.add('($shouldSql)');

    final mustNotSql = _joinConditions(filter.mustNot, schema, binds, ' AND ');
    if (mustNotSql != null) groups.add('NOT ($mustNotSql)');

    if (groups.isEmpty) {
      return (whereSql: '', binds: const []);
    }
    return (whereSql: groups.join(' AND '), binds: binds);
  }

  /// Renders one bucket's conditions, appending their binds to [binds] in SQL
  /// order. Skipped conditions (undeclared key, empty range) contribute
  /// nothing. Returns null when the bucket has no usable condition.
  static String? _joinConditions(
    List<Condition>? conditions,
    FilterSchema schema,
    List<Object?> binds,
    String separator,
  ) {
    if (conditions == null || conditions.isEmpty) return null;
    final fragments = <String>[];
    for (final condition in conditions) {
      final field = schema.fieldFor(condition.key);
      if (field == null) continue; // undeclared key → documented no-op
      final fragment = _encodeCondition(condition, field, binds);
      if (fragment != null) fragments.add(fragment);
    }
    if (fragments.isEmpty) return null;
    return fragments.join(separator);
  }

  /// Encodes one declared [condition] onto the column for [field], appending
  /// binds (coerced to the column's vec0 storage type). Returns null when the
  /// condition expresses no constraint (e.g. a range with both bounds null).
  static String? _encodeCondition(
    Condition condition,
    FilterField field,
    List<Object?> binds,
  ) {
    final column = field.name;
    switch (condition) {
      case FieldEquals(:final value):
        binds.add(_bind(value, field.type));
        return '$column = ?';

      case FieldRange(:final gte, :final lte):
        // Range columns are always numeric (FLOAT) — bind as double.
        if (gte != null && lte != null) {
          binds.add(gte);
          binds.add(lte);
          return '$column BETWEEN ? AND ?';
        }
        if (gte != null) {
          binds.add(gte);
          return '$column >= ?';
        }
        if (lte != null) {
          binds.add(lte);
          return '$column <= ?';
        }
        return null; // no bound → no constraint, skip

      case FieldMatchAny(:final values):
        // Empty list is "match nothing" (see FieldMatchAny dartdoc); vec0 has
        // no `IN ()` literal, so emit an always-false fragment with no binds.
        if (values.isEmpty) return '0';
        final placeholders = List.filled(values.length, '?').join(', ');
        for (final value in values) {
          binds.add(_bind(value, field.type));
        }
        return '$column IN ($placeholders)';
    }
  }

  /// Coerces a [value] to the bind type its vec0 column expects:
  ///   * [FilterFieldType.bool]   → `0`/`1` (vec0 INTEGER column);
  ///   * [FilterFieldType.number] → `double` (vec0 FLOAT column rejects an int);
  ///   * [FilterFieldType.string] → unchanged.
  static Object? _bind(Object value, FilterFieldType type) {
    if (value is bool) return value ? 1 : 0;
    if (type == FilterFieldType.number && value is num) return value.toDouble();
    return value;
  }
}
