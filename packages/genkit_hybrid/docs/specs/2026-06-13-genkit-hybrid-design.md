# Genkit Hybrid — Design

**Date:** 2026-06-13
**Status:** Approved skeleton, ready for implementation plan
**Package name:** `genkit_hybrid`
**Goal type:** Reusable, publishable community package (not an app-internal helper)

## Problem

Genkit is a provider-agnostic abstraction: an app calls a single `ai.generate(model: ...)` and any provider sits behind a plugin. On-device inference (`genkit_flutter_gemma`) and cloud inference (e.g. `googleAI/...`) are each exposed as ordinary Genkit `Model` actions.

What's missing is **hybrid routing**: the logic that decides, per request, whether to run on-device or in the cloud (and how to fall back when one is unavailable). Today every developer re-implements this `if/else`/`try/catch` by hand.

## Goal

A small, **provider-agnostic** package that lets a developer combine two or more existing Genkit models behind one routing policy, while preserving the core invariant: **the app still calls one `ai.generate`, and hybrid is just another `Model`.**

### Why a package (YAGNI justification)

This is a **publishable community package**, not an app-internal helper. The core routing logic is intentionally tiny — picking a branch is ~15 lines anyone could write. The package is justified by what is *easy to get wrong by hand* and worth standardizing:

1. **Correct streaming + fallback** (fall back only before the first token) — the part naive `try/catch` implementations get wrong (lost tokens / mid-stream re-route). This is the package's killer feature.
2. **A shared vocabulary / API** (`RoutingStrategy`, `PreRoutingStrategy`, `FallbackStrategy`) that examples and docs can teach against.
3. **Provider-agnostic reach** — usable for any pair of Genkit models, maximizing the audience and the package's reason to exist.

Implication: for v1, invest the care in **API readability, the streaming-fallback implementation + its tests, and a README of recipes** — not in adding more routing cleverness.

## Non-goals (v1)

- **Cascading by confidence** (try cheap model → escalate if low confidence). Out of scope because on-device runtimes (LiteRT-LM / flutter_gemma) do not expose a confidence signal (logprobs/entropy) through Genkit's `Model` contract. The `RoutingStrategy` interface leaves room to add it later. *(A heuristic "escalate on error/empty" degenerates into fallback, which we already cover.)*
- **A registered Genkit plugin** with a named action (`hybrid/smart`). The core is a factory; a thin plugin wrapper over the factory is a possible future addition if users need Dev-UI discovery or config-by-string-name. Not in v1.
- **Bundling any provider SDK.** The package depends only on `genkit`. It never imports `flutter_gemma` or any cloud SDK.

## Architecture

The package is a **combinator, not a provider**. It does not open new model sources; it composes existing `Model` actions the app already holds. The factory returns an ordinary `Model`, so hybrid is indistinguishable from any other model to the caller — this is what preserves the invariant.

```
   app code            ai.generate(model: myHybrid)
                                    │
                                    ▼
   genkit_hybrid        hybridModel(...) → Model           ← an ordinary Genkit Model
   (this package)         └─ RoutingStrategy.route()       ← decides order of branches
                                │            │
                       delegate │            │ delegate
   other plugins   ┌────────────▼──┐     ┌───▼────────────┐
   (not ours)      │ Model "onDevice"│    │ Model "cloud"   │
                   │ flutter-gemma/… │    │ googleAI/…       │
                   └─────────────────┘    └──────────────────┘
```

### Three responsibilities, strictly separated

1. **`hybridModel(...)` (factory)** — assembles a `Model`; forwards the incoming request to the chosen branch(es); returns the response/stream. Knows the Genkit `Model` contract; knows nothing about *how* a branch is chosen.
2. **`RoutingStrategy` (interface)** — the single place the "where to route" logic lives. Receives a routing context; returns an ordered list of branch keys to try. Independently testable.
3. **Child models** — passed in from outside as ready `Model`s. The package neither creates them nor knows their nature (on-device vs cloud is irrelevant to it).

### Two entry points into one engine

Hard core = N named branches. A binary façade for the common on-device/cloud case is a **thin wrapper over the core**, not a second implementation.

```dart
// CORE — N named branches
Model hybridModel({
  required Map<String, Model> branches,   // {'onDevice': A, 'cloud': B, 'cloud-pro': C}
  required RoutingStrategy strategy,
});

// FAÇADE — binary, built on top of the core
Model hybridModelOnDeviceCloud({          // named constructor / helper
  required Model onDevice,
  required Model cloud,
  required RoutingStrategy strategy,
});
// internally: branches = {kOnDevice: onDevice, kCloud: cloud}
```

Branch keys are strings (the strategy returns keys, not indexes/booleans — readable in logs/observability, extensible). The façade uses fixed constants `kOnDevice` / `kCloud` to avoid typos.

## Components & contracts

### `RoutingContext`
What the strategy sees when deciding.
- `request` — the incoming Genkit generate request (messages/prompt + config).
- `branchKeys` — the set of available branch keys.
- *(possibly)* `isStreaming` — whether this is a streaming call (lets a strategy behave differently; see streaming policy).

### `RoutingStrategy` (interface)
```dart
abstract class RoutingStrategy {
  /// Returns branch keys to try, in priority order.
  /// A single-element list = a pure pick (pre-routing).
  /// A multi-element list = pick + fallback.
  /// An EMPTY list = "no decision" (used by combinators like FirstMatch to
  /// signal "skip me, try the next strategy").
  List<String> route(RoutingContext context);
}
```
The ordered-list contract generalizes "pick one" (list of length 1) and "fallback" (length 2+) into one mechanism. Returned keys must exist in `branches`; an empty list from a top-level strategy is a configuration error and the factory throws (it cannot route nowhere).

### Built-in strategies (v1) — "batteries included"

The package ships a set of ready strategies. A strategy can only decide from what the Genkit contract exposes (request + branch keys + streaming flag). Therefore app-specific signals like "privacy" or "task complexity" are **not** baked in as named strategies — they go through `PreRoutingStrategy(fn)`, the universal escape hatch. Only strategies whose signal is **universal and self-computable** (connectivity, input length, fixed priority) ship as named.

All strategies return the same thing (`List<String>` of branch keys). They differ only in **where the decision signal comes from** — this is what distinguishes `PreRoutingStrategy` (an empty blank: rule lives in your function) from the rest (rule baked in):

| Strategy | Decision signal | Who computes it |
|---|---|---|
| `PreRoutingStrategy(fn)` | **external** — your arbitrary function | the app |
| `ConnectivityStrategy` | network availability | package (via app-supplied `isOnline`) |
| `InputSizeStrategy` | prompt length | **the package itself** (measures the request) |
| `FallbackStrategy` | none — fixed order | package (just returns the list) |
| `FirstMatch` / `WithFallback` | results of other strategies | package (composition) |

`InputSizeStrategy` ships but `ComplexityStrategy` does not: input length is objectively measurable (token/char count); "complexity" is not, without a classifier model — baking it in would be fake. The named set is drawn exactly along this line: only objectively-measurable signals are baked in; everything else is `PreRoutingStrategy(fn)`.

**Base (2):**

1. **`PreRoutingStrategy`** — wraps a developer-supplied function. The escape hatch for any custom rule (privacy, cost, user tier, anything).
   ```dart
   PreRoutingStrategy((context) => userOptedOutOfCloud ? 'onDevice' : 'cloud');
   ```
   Returns `[selectedKey]` (single element). (Slide "Pre-routing", schema A.)

2. **`FallbackStrategy`** — fixed priority order.
   ```dart
   FallbackStrategy(['onDevice', 'cloud']); // PREFER_ON_DEVICE
   FallbackStrategy(['cloud', 'onDevice']); // PREFER_IN_CLOUD
   ```
   Returns the fixed order; the factory tries each until one succeeds.

**Self-computable from a universal signal (2):**

3. **`ConnectivityStrategy`** — routes by network availability. The app supplies an `isOnline` provider (callback / sync flag); the package does not depend on any connectivity SDK.
   ```dart
   ConnectivityStrategy(isOnline: () => connectivity.isOnline,
                        online: 'cloud', offline: 'onDevice');
   ```

4. **`InputSizeStrategy`** — routes by input length (prompt token/char count, measured by the package). Short → one branch, long → another.
   ```dart
   InputSizeStrategy(threshold: 2000, small: 'onDevice', large: 'cloud');
   ```

**Combinators — strategies built from strategies (2):**

5. **`FirstMatch`** — tries each child strategy in order; the first to return a non-empty result wins (a chain of rules).
   ```dart
   FirstMatch([privacyRule, ConnectivityStrategy(...), FallbackStrategy([...])]);
   ```

6. **`WithFallback`** — takes any strategy's pick and **appends a fallback tail**, turning a pure pick into pick + fallback. The key composition primitive.
   ```dart
   WithFallback(ConnectivityStrategy(...), fallbackOrder: ['onDevice']);
   // picks by connectivity, then guarantees on-device as a safety net
   ```

These compose: e.g. `WithFallback(FirstMatch([...]), ['onDevice'])` = chain of rules to pick a primary, with a guaranteed fallback.

## Data flow

**Pre-routing (single branch):**
`request → hybridModel → strategy.route() → ['cloud'] → cloud.generate(request) → response`

**Fallback (ordered list):**
`request → strategy.route() → ['onDevice','cloud'] → try onDevice.generate() → ❌ fail → try cloud.generate() → response`

The factory has **two internal paths** — a non-streaming path (`generate`) and a streaming path (`stream`) — sharing the same `strategy.route()` decision but differing in fallback semantics (see Streaming policy).

**Factory core (non-streaming path), in pseudocode:**
```dart
Model hybridModel({branches, strategy}) => Model(fn: (request) async {
  final order = strategy.route(RoutingContext(request, branches.keys));
  for (final key in order) {
    try {
      return await branches[key]!.generate(request);
    } catch (e) {
      if (key == order.last) rethrow;   // last branch failed → propagate
      // else try next branch (fallback)
    }
  }
});
```

**Streaming path (sketch):** iterate `order`; for each branch, start streaming; if it throws *before* the first token, move to the next branch; once the first token is emitted, pass tokens through and let any later failure propagate (no re-route). See Streaming policy.

## Error handling & "what counts as failure"

Fallback fires only on **transient/availability** failures, never on **permanent** ones. Falling back on a permanent error (bad request, bad auth) is a silent-failure anti-pattern: the next branch gets the same bad request and also fails — slower, costlier, and masking the real cause (e.g. a wrong cloud API key silently routing to on-device forever).

- **Triggers fallback (transient/availability):** any non-`GenkitException` throwable (network error, timeout, OOM), and `GenkitException` whose status is `UNAVAILABLE`, `DEADLINE_EXCEEDED`, or `RESOURCE_EXHAUSTED`.
- **Propagates immediately, no fallback (permanent):** `GenkitException` whose status is `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `UNAUTHENTICATED`, `FAILED_PRECONDITION`, or `NOT_FOUND`.
- If the **last** branch in the order fails (for any reason), the error is propagated to the caller (no silent empty result).
- An empty/garbage response is **not** treated as failure in v1 (that would require confidence/quality evaluation — out of scope). Fallback is about *availability*, not *quality*.

The classification lives in one private helper (`_isTransient(Object error)`) so the policy is testable and adjustable in one place.

## Immutability of inputs

Every component that stores a caller-supplied collection (the factory's `branches` map, `FallbackStrategy`'s order, `WithFallback`'s `fallbackOrder`) takes a defensive **unmodifiable copy at construction time**, so later mutation of the caller's collection cannot silently change routing behavior. Returned lists from `route()` are also unmodifiable.

## Streaming policy

- **Streaming + fallback = fallback only before the first token.** If a branch fails *before* emitting any token, the factory switches to the next branch transparently. Once the first token has been streamed, a mid-stream failure propagates as an error (cannot silently re-route a partially delivered response).
- This honestly covers the main real-world case (offline / unavailable → fails immediately, before any token).
- Pre-routing (single branch) streams that branch directly; failure propagates.

## Testing strategy

- The package is tested with **two fake `Model`s** + each strategy — no real provider needed.
- Cases to cover:
  - Pre-routing returns single branch → only that branch is called.
  - Fallback: primary throws → secondary is called → secondary's response returned.
  - Fallback: last branch throws → error propagates.
  - Streaming: branch fails before first token → next branch used.
  - Streaming: branch fails after first token → error propagates (no re-route).
  - Config/tools forwarded to the chosen branch unchanged.
  - `RoutingStrategy` implementations tested in isolation (pure `route()` calls):
    - `ConnectivityStrategy`: online → online-branch, offline → offline-branch.
    - `InputSizeStrategy`: below/above threshold → small/large branch.
    - `FirstMatch`: returns first non-empty child result; empty children skipped.
    - `WithFallback`: appends fallback tail to the inner pick; no duplicate keys.

## Package shape

```
genkit_hybrid/
  lib/
    genkit_hybrid.dart          # public exports
    src/
      hybrid_model.dart         # hybridModel factory (core + binary façade)
      routing_context.dart      # RoutingContext
      routing_strategy.dart     # RoutingStrategy interface
      strategies/
        pre_routing.dart        # PreRoutingStrategy
        fallback.dart           # FallbackStrategy
        connectivity.dart       # ConnectivityStrategy
        input_size.dart         # InputSizeStrategy
        first_match.dart        # FirstMatch (combinator)
        with_fallback.dart      # WithFallback (combinator)
  test/
    ...                         # fakes + strategy/factory tests
  README.md                     # recipes: pre-routing, PREFER_ON_DEVICE, PREFER_IN_CLOUD
```
Dependencies: `genkit` only. As a publishable package: README with recipes, example, and a clear pub description are part of v1 scope.

## Resolved decisions

1. **`RoutingContext.isStreaming` — included from v1.** It is a single field and the streaming policy depends on it (a strategy may behave differently for streaming calls). Cheaper to include now than to break the contract later.
2. **Timeout — left to the underlying models in v1.** Genkit/providers already support timeouts; a built-in per-branch timeout is retry/middleware territory and is deferred to Future. No built-in timeout in v1.
3. **README recipes** — covered during implementation: pre-routing by connectivity, PREFER_ON_DEVICE, PREFER_IN_CLOUD, plus one combinator example (`WithFallback(FirstMatch([...]), [...])`).

## Future (explicitly deferred)

- Cascading by confidence (once a runtime exposes a confidence signal).
- Thin Genkit plugin wrapper over the factory (named action + Dev-UI discovery).
- Per-branch timeout / retry middleware.
