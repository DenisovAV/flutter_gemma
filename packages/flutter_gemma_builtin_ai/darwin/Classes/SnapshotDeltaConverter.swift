import Foundation

/// Converts the CUMULATIVE snapshots emitted by
/// `LanguageModelSession.ResponseStream` into per-token DELTAS.
///
/// Apple's `streamResponse` yields each element as the *accumulated* string so
/// far (snapshot `N+1` contains everything in snapshot `N` plus the new text),
/// but the shared Dart stream contract expects each `partialResult` to be only
/// the NEW fragment. This tracks the length already emitted and returns the tail.
///
/// Pure value type with no FoundationModels dependency, so it compiles on the
/// iOS-16 / macOS-10.15 floor and is unit-testable by inspection. Create (or
/// `reset()`) one per generation.
///
/// The length bookkeeping counts Swift `Character`s (grapheme clusters), so a
/// snapshot that only *re-normalizes* earlier text (same count, no growth)
/// yields an empty delta rather than corrupting the offset.
struct SnapshotDeltaConverter {
  /// Number of characters already emitted as deltas.
  private var lastLength: Int = 0

  /// Returns the newly-added tail of `cumulative` versus the previous snapshot,
  /// and advances the internal cursor. If the snapshot did not grow (or, in the
  /// pathological case, shrank), returns "".
  mutating func delta(from cumulative: String) -> String {
    let count = cumulative.count
    guard count > lastLength else {
      // No growth (or a shrink from re-normalization) — nothing new to emit.
      // Keep the cursor at the max seen so a later grow still lines up.
      lastLength = max(lastLength, count)
      return ""
    }
    let tail = String(cumulative.dropFirst(lastLength))
    lastLength = count
    return tail
  }

  /// Resets the cursor so the converter can drive a fresh generation.
  mutating func reset() {
    lastLength = 0
  }
}
