import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_gemma/flutter_gemma.dart';

/// Translates a [Filter] into a SQL `WHERE` fragment over vec0's declared
/// typed metadata columns, plus the ordered bind list.
///
/// It also owns the value dialect for the OTHER direction — the `INSERT` binds
/// both store arms promote a document's metadata into ([coerceForColumn],
/// [declaredColumnValues]). The two sides live together deliberately: a value
/// written into a typed vec0 column and a value bound into a predicate over
/// that column must be the same SQLite type, or the row is unfindable. They
/// used to live in three places and had already drifted (see
/// [coerceForColumn]).
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

  /// Wraps a declared [FilterField.name] in SQLite's double-quoted identifier
  /// form for use in statements **SQLite itself** parses (the `INSERT` column
  /// list, the KNN `WHERE`).
  ///
  /// Needed because [FilterField.namePattern] accepts names that are also SQL
  /// keywords. Measured on vec0 0.1.9: `order` passes the `vec0(…)` DDL (its
  /// tokenizer has no keyword table) but then
  /// `INSERT INTO t(id, embedding, order, …)` dies with
  /// `near "order": syntax error`. Quoting fixes it, and it is the right fix
  /// rather than banning keywords, because a keyword is a perfectly good
  /// qdrant payload key — a ban there would have no cross-backend
  /// justification.
  ///
  /// Quoting is applied **only** here, never in the `vec0(…)` DDL: sqlite-vec's
  /// own DDL grammar rejects every quoting form (see [FilterField]), so the
  /// column is created bare and referenced quoted.
  ///
  /// No escaping is needed: [FilterField.namePattern] has already excluded `"`
  /// (and every other non-word character), so the name cannot terminate the
  /// quoted identifier.
  ///
  /// Measured not to cost pushdown — `category = ?` and `"category" = ?` yield
  /// the identical vec0 plan (`SCAN t VIRTUAL TABLE INDEX 0:3{___}___&Aa_`)
  /// and the identical rows, because SQLite resolves the identifier before
  /// `xBestIndex` ever sees it.
  static String quoteColumn(String name) => '"$name"';

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

    final shouldSql = _joinConditions(
      _fuseOneFieldDisjunction(filter.should, schema),
      schema,
      binds,
      ' OR ',
    );
    if (shouldSql != null) groups.add('($shouldSql)');

    // mustNot = "no condition may match". The obvious rendering is
    // NOT (A OR B …), and that is what this used to emit — but vec0 accepts
    // only single-column comparison constraints in a KNN query, and `NOT (…)`
    // is not one. SQLite could not hand it to the virtual table, so vec0
    // returned the k nearest rows UNFILTERED and SQLite discarded afterwards:
    // a post-filter over a global top-k, which silently returns fewer than k
    // rows, or none at all, while looking like a filtered search.
    //
    // Measured on vec0 0.1.9: `NOT (category = 'a')` at k=2 over a 4-row
    // corpus returned 0 rows (EXPLAIN plan `0:3{___}___`, nothing pushed),
    // while `category != 'a'` returned the right 2 (plan `…&Aa_`, pushed).
    //
    // So apply De Morgan and negate each condition into its own pushable
    // comparison: NOT (A OR B) ≡ (NOT A) AND (NOT B).
    final mustNotSql = _joinNegatedConditions(filter.mustNot, schema, binds);
    if (mustNotSql != null) groups.add(mustNotSql);

    if (groups.isEmpty) {
      return (whereSql: '', binds: const []);
    }
    return (whereSql: groups.join(' AND '), binds: binds);
  }

  /// Rewrites a `should` bucket that is entirely set membership over ONE
  /// declared field into the single [FieldMatchAny] it already means, so the
  /// rendering of that shape is decided here rather than by SQLite.
  ///
  /// `should` is an OR, and SQLite rewrites `year = ? OR year = ?` into
  /// `year IN (?, ?)` on its own — measured, for bound parameters as well as
  /// literals. On a FLOAT column that rewrite throws out of `prepare` (see
  /// [_numberSetMembership]), so the bug reached callers who never wrote a
  /// [FieldMatchAny] at all. Fusing first means the number case takes the
  /// pushable-envelope path, and the string/bool case emits the same `IN` the
  /// optimiser would have produced, explicitly.
  ///
  /// Anything else — two different fields, a [FieldRange] in the mix — is
  /// returned untouched: SQLite folds only same-column equalities, so those
  /// shapes never reach the refusal.
  static List<Condition>? _fuseOneFieldDisjunction(
    List<Condition>? conditions,
    FilterSchema schema,
  ) {
    if (conditions == null || conditions.length < 2) return conditions;
    String? key;
    final values = <Object>[];
    for (final condition in conditions) {
      // Undeclared keys contribute no fragment at all, so they cannot make the
      // bucket a mixed-column OR either.
      if (schema.fieldFor(condition.key) == null) continue;
      if (key != null && condition.key != key) return conditions;
      key = condition.key;
      switch (condition) {
        case FieldEquals(:final value):
          values.add(value);
        case FieldMatchAny(values: final members):
          values.addAll(members);
        case FieldRange():
          return conditions; // not set membership
      }
    }
    if (key == null) return conditions; // every condition was undeclared
    return [FieldMatchAny(key: key, values: values)];
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

  /// Renders `mustNot` as AND-joined per-condition negations, each one a
  /// comparison vec0 can push into the KNN scan. Returns null when no
  /// condition contributes a constraint.
  static String? _joinNegatedConditions(
    List<Condition>? conditions,
    FilterSchema schema,
    List<Object?> binds,
  ) {
    if (conditions == null || conditions.isEmpty) return null;
    final fragments = <String>[];
    for (final condition in conditions) {
      final field = schema.fieldFor(condition.key);
      if (field == null) continue; // undeclared key — documented no-op
      final sql = _encodeNegatedCondition(condition, field, binds);
      if (sql != null) fragments.add(sql);
    }
    if (fragments.isEmpty) return null;
    return fragments.join(' AND ');
  }

  /// The negation of [condition], written as a constraint vec0 can push.
  /// Null when the condition constrains nothing, so its negation constrains
  /// nothing either.
  static String? _encodeNegatedCondition(
    Condition condition,
    FilterField field,
    List<Object?> binds,
  ) {
    final column = quoteColumn(field.name);
    switch (condition) {
      case FieldEquals(:final value):
        final bind = coerceForColumn(value, field.type);
        // Unstorable value → no stored row equals it → excluding it excludes
        // nothing. Emit no constraint (binding NULL into a pushed `!=` would
        // be handed to vec0, whose comparison is not SQL NULL semantics).
        if (bind == null) return null;
        binds.add(bind);
        return '$column != ?';

      case FieldRange(:final gte, :final lte):
        if (field.type != FilterFieldType.number) return null;
        // Two-sided is the one shape that cannot be rescued: measured, vec0
        // pushes neither `NOT BETWEEN` nor the `< a OR > b` rewrite, because
        // OR across bounds is not a single comparison. It therefore keeps the
        // old post-filter behaviour — for this shape alone, instead of for
        // every mustNot. Fixing it needs over-fetching at the store level.
        if (gte != null && lte != null) {
          binds.add(gte);
          binds.add(lte);
          return '$column NOT BETWEEN ? AND ?';
        }
        if (gte != null) {
          binds.add(gte);
          return '$column < ?';
        }
        if (lte != null) {
          binds.add(lte);
          return '$column > ?';
        }
        return null; // constrains nothing, so neither does its negation

      case FieldMatchAny(:final values):
        // "match none of []" excludes nothing, so emit no constraint. Same for
        // a list of values no row could hold. The positive side emits the
        // always-false sentinel '0'; its negation would be an always-true '1',
        // which is not pushable and would drag the whole group back to a
        // post-filter.
        final unwanted = _coerceSet(values, field.type);
        if (unwanted.isEmpty) return null;
        // A chain of `!=`, NOT `NOT IN`. Measured on vec0 0.1.9 at k=1 over a
        // 4-row corpus: `category NOT IN ('a')` returned 0 rows (not pushed),
        // while `category != 'a' AND category != 'b'` returned the right row.
        // Same logic, and only one of the two reaches the KNN scan.
        //
        // This is also why the negated side needs no FLOAT special case: a
        // conjunction of `!=` is exactly what vec0 pushes, on every column
        // kind including FLOAT (measured, plan `…&Af_&Af_`). It is the
        // positive disjunction that has no pushable form, not this.
        final parts = <String>[];
        for (final value in unwanted) {
          binds.add(value);
          parts.add('$column != ?');
        }
        return parts.length == 1 ? parts.first : '(${parts.join(' AND ')})';
    }
  }

  /// Encodes one declared [condition] onto the column for [field], appending
  /// binds (coerced to the column's vec0 storage type). Returns null when the
  /// condition expresses no constraint (e.g. a range with both bounds null).
  static String? _encodeCondition(
    Condition condition,
    FilterField field,
    List<Object?> binds,
  ) {
    final column = quoteColumn(field.name);
    switch (condition) {
      case FieldEquals(:final value):
        final bind = coerceForColumn(value, field.type);
        // Unstorable value → no stored row can equal it. Match nothing rather
        // than binding NULL into a comparison vec0 will push.
        if (bind == null) return '0';
        binds.add(bind);
        return '$column = ?';

      case FieldRange(:final gte, :final lte):
        // A range only makes sense over a numeric column. If the declared field
        // is TEXT/BOOLEAN, treat the condition as unsupported and skip it (a
        // documented no-op), rather than emitting a typed comparison that
        // silently mis-filters.
        if (field.type != FilterFieldType.number) return null;
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
          // The one positive shape the absent-number sentinel leaks into:
          // -Infinity is <= every bound, so a document MISSING this field
          // would satisfy `year <= 2020`. Measured. Exclude it with a second
          // conjunct — and note both push (plan `…&Bc_&Bb_`), so this costs no
          // pushdown, unlike the OR it replaces.
          binds.add(lte);
          binds.add(absentNumber);
          return '($column <= ? AND $column > ?)';
        }
        return null; // no bound → no constraint, skip

      case FieldMatchAny(:final values):
        // Empty list is "match nothing" (see FieldMatchAny dartdoc); vec0 has
        // no `IN ()` literal, so emit an always-false fragment with no binds.
        // Same for a list whose every member is unstorable in this column.
        final wanted = _coerceSet(values, field.type);
        if (wanted.isEmpty) return '0';

        // One member is not a set — and `=` is pushable on every column kind,
        // including FLOAT, where `IN` is not (below).
        if (wanted.length == 1) {
          binds.add(wanted.first);
          return '$column = ?';
        }

        if (field.type != FilterFieldType.number) {
          binds.addAll(wanted);
          final placeholders = List.filled(wanted.length, '?').join(', ');
          return '$column IN ($placeholders)';
        }
        return _numberSetMembership(column, wanted.cast<double>(), binds);
    }
  }

  /// Set membership over a FLOAT column, which vec0 will not accept as `IN`.
  ///
  /// Measured on vec0 0.1.9: `year IN (2023.0, 2024.0)` does not just fail to
  /// push, it *throws* out of `sqlite3_prepare` —
  /// `'xxx in (...)' is only available on INTEGER or TEXT metadata columns.` —
  /// which breaks [VectorStoreRepository]'s promise that a filter never
  /// throws. (TEXT and INTEGER columns do take `IN`, and it is pushed: plan
  /// `…&Ca_`. Only FLOAT and BOOLEAN kinds refuse, in vec0's `xBestIndex`.)
  ///
  /// The obvious rewrite does NOT work: SQLite's OR-to-IN optimisation folds
  /// `year = ? OR year = ?` back into `year IN (?, ?)` before the virtual
  /// table is consulted, so the OR chain throws identically — measured, with
  /// bound parameters as well as with literals. That fold is also why a
  /// `should` bucket of several [FieldEquals] on one FLOAT column used to
  /// throw without ever naming `IN`.
  ///
  /// So the exact test is written as a `CASE`, which SQLite cannot turn into
  /// an `IN` under any optimisation. The cost, stated plainly: **a `CASE` is
  /// not pushable**. vec0's KNN takes a conjunction of single-column
  /// comparisons and nothing else, so a disjunction over one column has no
  /// pushable exact form at all — the `CASE` runs as a post-filter over rows
  /// vec0 already chose, and a post-filter can only ever return FEWER than `k`
  /// rows, never reach past them.
  ///
  /// What can be pushed is the set's envelope, `BETWEEN min AND max`, which is
  /// a superset of it (measured pushed: plan `…&Ae_&Ac_`) and so discards no
  /// match. Emitting both makes vec0 pick its `k` from inside the envelope
  /// instead of from the whole table, which turns the common contiguous case
  /// into an exact, fully-pushed filter. Measured over a 5-row corpus at k=2,
  /// wanting `{2021, 2022}` while the two nearest rows are 1998/1999: the
  /// `CASE` alone returned 0 rows, envelope + `CASE` returned both. Only the
  /// gaps in a non-contiguous set are still paid for as a post-filter.
  static String _numberSetMembership(
    String column,
    List<double> wanted,
    List<Object?> binds,
  ) {
    binds.add(wanted.reduce(math.min));
    binds.add(wanted.reduce(math.max));
    binds.addAll(wanted);
    final whens = List.filled(wanted.length, 'WHEN ? THEN 1').join(' ');
    return '($column BETWEEN ? AND ? AND CASE $column $whens ELSE 0 END)';
  }

  /// The ONE Dart→SQLite mapping for a declared vec0 column, used by both the
  /// `INSERT` binds and the KNN `WHERE` binds, on both the native and the web
  /// store arm:
  ///   * [FilterFieldType.string] → the `String` (vec0 TEXT column);
  ///   * [FilterFieldType.number] → `double` (vec0 FLOAT column);
  ///   * [FilterFieldType.bool]   → `0`/`1` (declared INTEGER, since a bound
  ///     parameter has no boolean literal).
  ///
  /// It has to be one function, because a vec0 metadata column is strictly
  /// typed on write. Measured on vec0 0.1.9, inserting an INTEGER `2024` into
  /// a FLOAT column fails outright:
  /// `Expected float for FLOAT metadata column year, received INTEGER`.
  /// The rule used to be spelled three times — once here for predicates, once
  /// in each store for inserts — and the copies had drifted: the web arm
  /// coerced only the bool case, so `addDocument` with metadata
  /// `{"year": 2024}` stored fine on native (bound `2024.0`) and threw on web
  /// (bound `2024`). Same document, same schema, same package version.
  ///
  /// Returns null when [value] has no representation in the column (absent,
  /// or a JSON type the column cannot hold — a `String` for a FLOAT column,
  /// say). Null means different things to the two callers, and neither of them
  /// may bind it:
  ///   * predicates: a value that cannot be stored can never equal a stored
  ///     one, so the condition is rendered as the always-false `0` (or, when
  ///     negated, dropped) rather than binding NULL;
  ///   * inserts: the column has no value — and vec0 metadata columns are NOT
  ///     nullable (measured: `Expected float for FLOAT metadata column year,
  ///     received NULL`), so the document cannot be stored. That is a vec0
  ///     constraint we cannot paper over; what matters here is that both arms
  ///     now hit it on exactly the same inputs.
  static Object? coerceForColumn(Object? value, FilterFieldType type) {
    switch (type) {
      case FilterFieldType.string:
        return value is String ? value : null;
      case FilterFieldType.number:
        // `bool` is not a `num` in Dart, so booleans fall through to null.
        return value is num ? value.toDouble() : null;
      case FilterFieldType.bool:
        if (value is bool) return value ? 1 : 0;
        // JSON often carries booleans as 0/1; anything else is not a boolean
        // and inventing a truthiness rule for it would answer filters wrongly.
        if (value is num && (value == 0 || value == 1)) {
          return value == 1 ? 1 : 0;
        }
        return null;
    }
  }

  /// Sentinels written for a declared field a document does not carry.
  ///
  /// vec0 type-checks every declared metadata column and exempts nothing —
  /// `sqlite-vec.c` around 8189-8221 rejects NULL for TEXT, FLOAT and INTEGER
  /// alike, and an omitted column IS a NULL. So once a [FilterSchema] declares
  /// a field, a document without it could not be inserted at all: heterogeneous
  /// metadata, the normal RAG case, threw a raw SqliteException.
  ///
  /// A sentinel is a real value, chosen so no user value can equal it:
  ///   * TEXT — a NUL-led marker. A bare NUL is not enough: RFC 8259 forbids
  ///     only RAW control characters, and Dart's jsonDecode accepts the
  ///     `\u0000` escape, so `{"a":"\u0000"}` is legal JSON.
  ///   * FLOAT — negative infinity. NOT NaN: measured, SQLite converts NaN to
  ///     NULL before vec0 sees it (`typeof(9e999*0)` is `null`, and binding
  ///     `double.nan` binds NULL), so a NaN sentinel would throw the very error
  ///     this fixes.
  ///   * INTEGER (bool) — the minimum 64-bit integer. Legal because bool fields
  ///     are declared INTEGER, not BOOLEAN; vec0's BOOLEAN kind accepts only
  ///     0 and 1.
  ///
  /// Why a real value rather than a companion "is present" column: `mustNot`
  /// must return a document that lacks the field — qdrant's `must_not` excludes
  /// only points that SATISFY the condition, and a missing key never does — and
  /// a real sentinel gives that for free, since `col != ?` is true of it and
  /// pushes into the KNN scan. A presence column would need `present = 0 OR
  /// col != ?`, and an OR is exactly what vec0 cannot push, dragging every
  /// mustNot back into the post-filter this file exists to avoid.
  static const String absentText = '\u0000__absent__';
  static const double absentNumber = double.negativeInfinity;
  static const int absentBool = -9223372036854775808;

  /// The sentinel for [type].
  static Object absentValue(FilterFieldType type) => switch (type) {
    FilterFieldType.string => absentText,
    FilterFieldType.number => absentNumber,
    FilterFieldType.bool => absentBool,
  };

  /// Decodes a document's raw [metadata] JSON into the declared typed columns,
  /// one entry per [FilterSchema] field in declaration order, coerced by
  /// [coerceForColumn]. Absent keys, non-object metadata and unparseable
  /// metadata all yield the per-type sentinel for that column, never a throw.
  ///
  /// Shared by both store arms for the same reason [coerceForColumn] is: this
  /// is the write half of the same dialect, and while each arm owned a copy
  /// they disagreed about what `{"year": 2024}` means.
  static Map<String, Object?> declaredColumnValues(
    String? metadata,
    FilterSchema schema,
  ) {
    if (schema.isEmpty) return const {};
    Object? decoded;
    if (metadata != null && metadata.isNotEmpty) {
      try {
        decoded = jsonDecode(metadata);
      } on FormatException {
        decoded = null;
      }
    }
    final json = decoded is Map ? decoded : const {};
    return {
      for (final field in schema.fields)
        field.name:
            coerceForColumn(json[field.name], field.type) ??
            absentValue(field.type),
    };
  }

  /// The distinct, storable members of a [FieldMatchAny] value list, in the
  /// order given. Values with no representation in the column are dropped —
  /// they can never equal a stored value, so they widen nothing.
  static List<Object> _coerceSet(List<Object> values, FilterFieldType type) {
    final out = <Object>[];
    for (final value in values) {
      final bind = coerceForColumn(value, type);
      if (bind == null || out.contains(bind)) continue;
      out.add(bind);
    }
    return out;
  }
}
