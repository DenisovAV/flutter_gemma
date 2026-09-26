import 'dart:async';

import 'package:flutter_gemma/core/registry/runtime_config.dart'
    show ActiveEmbedderParams;
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart' show EmbeddingModel;

/// The cached embedder, the rule for reusing it, and the serialisation that
/// makes the rule mean anything.
///
/// Each of the three shells (mobile/desktop/web) used to hold this state as its
/// own private fields and re-implement the decision over them. Three copies is
/// three chances to get it wrong, and all three were wrong in different ways:
/// desktop gated the comparison on a field that is only assigned after the
/// build returns (so a second caller arriving during a build fell through and
/// started another one), web joined an in-flight build without comparing
/// anything at all (so asking for a different model file handed back the first
/// model's vectors), and mobile dropped its baseline only after awaiting the old
/// model's `close()` (so a matching caller could be handed a model that was
/// already closing). One object, one rule; the shells keep the wiring.
///
/// There is deliberately no `Completer` here. Its only job was to let a
/// concurrent caller join a build already in flight, which [serialize] makes
/// impossible — and a completer that outlives its build is exactly what turned
/// one misconfiguration into a permanent hang: a throw between "completer
/// installed" and the enclosing `try` left every later caller awaiting
/// something nobody would ever complete.
class EmbedderCache {
  /// One field, so "a model with no idea what it was built from" is not a state
  /// this class can be in. As two fields it was representable, which is why the
  /// web shell carried a defensive "no recorded config for the cached embedder"
  /// branch — a branch for a state that should not exist.
  _CachedEmbedder? _cached;
  Future<void> _lane = Future<void>.value();

  /// The cached embedder, or null when none is built.
  EmbeddingModel? get model => _cached?.model;

  /// What [model] was built from. Null exactly when [model] is null.
  ActiveEmbedderParams? get params => _cached?.params;

  /// Runs [body] after every earlier `serialize` call on this cache has
  /// settled, so that resolving paths, deciding on reuse and building are one
  /// indivisible step.
  ///
  /// Without this the three steps have awaits between them and two callers can
  /// both finish deciding before either records a model: two worker isolates,
  /// two compiles, and the loser orphaned with nobody to close it. It also
  /// removes the reordering hazard — moving an await earlier in the entry point
  /// silently widened that window once already.
  Future<T> serialize<T>(Future<T> Function() body) {
    final previous = _lane;
    // The lane advances on a completer of its own rather than on a handler
    // attached to the returned future. Attaching one there marks the caller's
    // error as HANDLED, so a fire-and-forget `createEmbeddingModel()` that
    // failed reported nothing at all — the silence this whole change is
    // against. `gate` only ever completes with a value, so a failure belongs
    // to its own caller and still cannot reach the next one in line.
    final gate = Completer<void>();
    _lane = gate.future;
    return previous.then((_) => body()).whenComplete(gate.complete);
  }

  /// The cached embedder when it matches [requested], else null for "build one".
  ///
  /// A mismatch closes the cached model before returning, so the caller only
  /// ever has to handle "reuse this" or "build a new one".
  Future<EmbeddingModel?> reuseOrInvalidate(
    ActiveEmbedderParams requested, {
    required String label,
  }) async {
    final cached = _cached;
    if (cached == null) return null;

    final changedParam = cached.params.firstDifference(requested);
    if (changedParam == null) {
      gemmaLog('ℹ️  Reusing existing embedding model instance for $label');
      return cached.model;
    }

    gemmaLog(
      '⚠️  Embedder config changed ($changedParam) for $label — rebuilding',
    );
    // Dropped BEFORE the await, not after: while a close is in flight the
    // cached model is no longer a valid answer to anybody.
    _cached = null;
    gemmaLog('🔄 Closing old embedding model and creating new one...');
    await cached.model.close();
    return null;
  }

  /// Records a freshly built [model] and what it was built from.
  void record(EmbeddingModel model, ActiveEmbedderParams params) {
    _cached = _CachedEmbedder(model, params);
    model.addCloseListener(() {
      // Identity-guarded, as the inference singleton and the session layer
      // already are. Without it a late close of a SUPERSEDED model clears
      // whatever is registered now — including a newer, live model, whose next
      // caller then reloads weights that are already in memory while the live
      // one leaks with nobody left to close it.
      if (!identical(_cached?.model, model)) return;
      _cached = null;
    });
  }

  /// Forgets the cached embedder without closing it.
  ///
  /// For a build that failed: there is nothing to close, and leaving the
  /// bookkeeping behind is what made a one-off error permanent.
  void invalidate() => _cached = null;
}

/// A built embedder and the params it was built from, which only ever travel
/// together.
class _CachedEmbedder {
  const _CachedEmbedder(this.model, this.params);

  final EmbeddingModel model;
  final ActiveEmbedderParams params;
}
