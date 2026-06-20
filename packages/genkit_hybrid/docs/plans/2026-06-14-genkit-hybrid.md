# Genkit Hybrid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `genkit_hybrid`, a provider-agnostic Dart package that combines existing Genkit `Model` actions behind a routing policy, returning an ordinary `Model` so the app still calls one `ai.generate`.

**Architecture:** A combinator factory `hybridModel(branches, strategy)` that delegates each request to a branch chosen by a `RoutingStrategy.route()` (returns an ordered list of branch keys: single = pre-routing, multi = fallback). Delegation calls the child model's public `fn(request, context)` directly. Streaming falls back only before the first emitted token, detected by wrapping the `sendChunk` callback.

**Tech Stack:** Dart, `genkit` ^0.13.0 (provides `Model`, `ModelRequest`, `ModelResponse`, `ModelResponseChunk`, `ActionFnArg` record, `GenkitException`, `StatusCodes`). Tests via `package:test`.

**Key API facts (verified against genkit 0.13.2 source):**
- `Model({required String name, required fn})` where `fn` is `Future<ModelResponse> Function(ModelRequest? request, ActionFnArg<ModelResponseChunk, ModelRequest, void> context)`.
- `Action.fn` is a public field → a child model is invoked directly as `child.fn(request, context)`.
- `ActionFnArg` is a record: `({bool streamingRequested, StreamingCallback<ModelResponseChunk> sendChunk, ...})`. We construct our own record to wrap `sendChunk`.
- `StreamingCallback<Chunk> = void Function(Chunk chunk)`.
- Import surface: `package:genkit/genkit.dart` (types) and `package:genkit/plugin.dart` (`Model`, `GenkitException`, `StatusCodes`).

---

## File Structure

```
genkit_hybrid/                          # new package (sibling repo or path dep)
  pubspec.yaml                          # name: genkit_hybrid, dep: genkit ^0.13.0
  lib/
    genkit_hybrid.dart                  # public exports
    src/
      routing_context.dart              # RoutingContext (request + branchKeys + isStreaming)
      routing_strategy.dart             # RoutingStrategy interface
      hybrid_model.dart                 # hybridModel factory (core + binary façade) + key constants
      strategies/
        pre_routing.dart                # PreRoutingStrategy
        fallback.dart                   # FallbackStrategy
        connectivity.dart               # ConnectivityStrategy
        input_size.dart                 # InputSizeStrategy
        first_match.dart                # FirstMatch combinator
        with_fallback.dart              # WithFallback combinator
  test/
    fakes.dart                          # fakeModel(...) helpers
    routing_strategy_test.dart          # strategies in isolation
    hybrid_model_test.dart              # factory: routing, fallback, streaming
  README.md                             # recipes
  example/
    genkit_hybrid_example.dart
```

Each file has one responsibility. Strategies are one-per-file under `strategies/`. The factory owns delegation + fallback + streaming. Context and interface are tiny standalone types.

---

## Task 1: Scaffold the package

**Files:**
- Create: `genkit_hybrid/pubspec.yaml`
- Create: `genkit_hybrid/lib/genkit_hybrid.dart` (empty exports for now)
- Create: `genkit_hybrid/analysis_options.yaml`

- [ ] **Step 1: Create pubspec.yaml**

```yaml
name: genkit_hybrid
description: Provider-agnostic hybrid routing for Genkit — combine on-device and cloud models behind one routing policy.
version: 0.1.0
repository: https://github.com/DenisovAV/genkit_flutter_gemma
environment:
  sdk: ^3.5.0
dependencies:
  genkit: ^0.13.0
dev_dependencies:
  test: ^1.25.0
  lints: ^4.0.0
```

- [ ] **Step 2: Create analysis_options.yaml**

```yaml
include: package:lints/recommended.yaml
linter:
  rules:
    prefer_single_quotes: true
    prefer_const_constructors: true
```

- [ ] **Step 3: Create empty public export file**

`lib/genkit_hybrid.dart`:
```dart
/// Provider-agnostic hybrid routing for Genkit.
library;

// Exports added in later tasks.
```

- [ ] **Step 4: Get dependencies**

Run: `cd genkit_hybrid && dart pub get`
Expected: resolves `genkit ^0.13.0` and dev deps with no errors.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/pubspec.yaml genkit_hybrid/analysis_options.yaml genkit_hybrid/lib/genkit_hybrid.dart
git commit -m "feat(genkit_hybrid): scaffold package"
```

---

## Task 2: RoutingContext

**Files:**
- Create: `genkit_hybrid/lib/src/routing_context.dart`
- Test: `genkit_hybrid/test/routing_strategy_test.dart` (created here, extended later)

- [ ] **Step 1: Write the failing test**

`test/routing_strategy_test.dart`:
```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/routing_context.dart';
import 'package:test/test.dart';

void main() {
  test('RoutingContext exposes request, branchKeys and isStreaming', () {
    final request = ModelRequest(messages: []);
    const ctx = RoutingContext(
      request: null,
      branchKeys: {'onDevice', 'cloud'},
      isStreaming: true,
    );
    expect(ctx.branchKeys, contains('cloud'));
    expect(ctx.isStreaming, isTrue);
    expect(ctx.request, isNull);

    final ctx2 = RoutingContext(
      request: request,
      branchKeys: const {'a'},
      isStreaming: false,
    );
    expect(ctx2.request, same(request));
    expect(ctx2.isStreaming, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `routing_context.dart` not found / `RoutingContext` undefined.

- [ ] **Step 3: Write minimal implementation**

`lib/src/routing_context.dart`:
```dart
import 'package:genkit/genkit.dart';

/// What a [RoutingStrategy] sees when deciding where to route a request.
class RoutingContext {
  const RoutingContext({
    required this.request,
    required this.branchKeys,
    required this.isStreaming,
  });

  /// The incoming generate request (may be null, mirroring Genkit's contract).
  final ModelRequest? request;

  /// The set of available branch keys to choose from.
  final Set<String> branchKeys;

  /// Whether the caller requested a streaming response.
  final bool isStreaming;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/routing_context.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add RoutingContext"
```

---

## Task 3: RoutingStrategy interface

**Files:**
- Create: `genkit_hybrid/lib/src/routing_strategy.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/routing_strategy_test.dart` imports:
```dart
import 'package:genkit_hybrid/src/routing_strategy.dart';
```
Add test inside `main()`:
```dart
  test('RoutingStrategy can be implemented and returns ordered keys', () {
    final s = _ConstStrategy(['cloud', 'onDevice']);
    const ctx = RoutingContext(
      request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false,
    );
    expect(s.route(ctx), ['cloud', 'onDevice']);
  });
```
Add at file bottom:
```dart
class _ConstStrategy implements RoutingStrategy {
  _ConstStrategy(this.keys);
  final List<String> keys;
  @override
  List<String> route(RoutingContext context) => keys;
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `routing_strategy.dart` not found / `RoutingStrategy` undefined.

- [ ] **Step 3: Write minimal implementation**

`lib/src/routing_strategy.dart`:
```dart
import 'routing_context.dart';

/// Decides which branch(es) to try for a request.
abstract class RoutingStrategy {
  /// Returns branch keys to try, in priority order.
  ///
  /// - A single-element list = a pure pick (pre-routing).
  /// - A multi-element list = pick + fallback.
  /// - An empty list = "no decision" (used by combinators such as
  ///   [FirstMatch] to signal "skip me, try the next strategy"). At the top
  ///   level the factory treats an empty result as a configuration error.
  List<String> route(RoutingContext context);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/routing_strategy.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add RoutingStrategy interface"
```

---

## Task 4: Test fakes

**Files:**
- Create: `genkit_hybrid/test/fakes.dart`

- [ ] **Step 1: Write the fakes (no separate test; used by later tests)**

`test/fakes.dart`:
```dart
import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart';

/// A fake Model whose behavior is controlled by callbacks.
///
/// [onCall] records each invocation key. [response] is returned for blocking
/// calls. [chunks] are streamed via context.sendChunk before resolving.
/// If [throwBeforeToken] is true, the model throws immediately (no chunk).
/// If [throwAfterToken] is true, it sends the first chunk then throws.
Model fakeModel({
  required String name,
  String text = 'ok',
  List<String> chunks = const [],
  bool throwBeforeToken = false,
  bool throwAfterToken = false,
  void Function()? onCall,
}) {
  return Model(
    name: name,
    fn: (request, context) async {
      onCall?.call();
      if (throwBeforeToken) {
        throw StateError('fail-before-token:$name');
      }
      if (context.streamingRequested) {
        for (final c in chunks) {
          context.sendChunk(
            ModelResponseChunk(content: [TextPart(text: c)]),
          );
          if (throwAfterToken) {
            throw StateError('fail-after-token:$name');
          }
        }
      }
      return ModelResponse(
        message: Message(role: Role.model, content: [TextPart(text: text)]),
      );
    },
  );
}
```

> Note: if `TextPart`/`Message`/`Role` names differ in genkit 0.13, adjust to the actual constructors (check `package:genkit/genkit.dart` exports). The shapes used here match `ModelResponse`/`ModelResponseChunk` in genkit 0.13.2.

- [ ] **Step 2: Verify fakes compile**

Run: `cd genkit_hybrid && dart analyze test/fakes.dart`
Expected: No errors (warnings about unused are fine until used).

- [ ] **Step 3: Commit**

```bash
git add genkit_hybrid/test/fakes.dart
git commit -m "test(genkit_hybrid): add fake Model helper"
```

---

## Task 5: hybridModel factory — blocking path + routing

**Files:**
- Create: `genkit_hybrid/lib/src/hybrid_model.dart`
- Test: Create `genkit_hybrid/test/hybrid_model_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/hybrid_model_test.dart`:
```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/src/hybrid_model.dart';
import 'package:genkit_hybrid/src/routing_context.dart';
import 'package:genkit_hybrid/src/routing_strategy.dart';
import 'package:test/test.dart';
import 'fakes.dart';

class _Pick implements RoutingStrategy {
  _Pick(this.keys);
  final List<String> keys;
  @override
  List<String> route(RoutingContext c) => keys;
}

ModelRequest _req() => ModelRequest(messages: []);
final _blockingCtx = (
  streamingRequested: false,
  sendChunk: (ModelResponseChunk _) {},
  context: <String, dynamic>{},
  abortSignal: null,
  trace: null,
);

void main() {
  test('pre-routing: only the chosen branch is called', () async {
    var deviceCalls = 0, cloudCalls = 0;
    final model = hybridModel(
      branches: {
        'onDevice': fakeModel(name: 'd', text: 'from-device', onCall: () => deviceCalls++),
        'cloud': fakeModel(name: 'c', text: 'from-cloud', onCall: () => cloudCalls++),
      },
      strategy: _Pick(['cloud']),
    );
    final res = await model.fn(_req(), _blockingCtx);
    expect(cloudCalls, 1);
    expect(deviceCalls, 0);
    expect((res.message!.content.first as TextPart).text, 'from-cloud');
  });

  test('fallback: primary throws → secondary returns', () async {
    var cloudCalls = 0;
    final model = hybridModel(
      branches: {
        'onDevice': fakeModel(name: 'd', throwBeforeToken: true),
        'cloud': fakeModel(name: 'c', text: 'recovered', onCall: () => cloudCalls++),
      },
      strategy: _Pick(['onDevice', 'cloud']),
    );
    final res = await model.fn(_req(), _blockingCtx);
    expect(cloudCalls, 1);
    expect((res.message!.content.first as TextPart).text, 'recovered');
  });

  test('fallback: last branch throws → error propagates', () async {
    final model = hybridModel(
      branches: {
        'onDevice': fakeModel(name: 'd', throwBeforeToken: true),
        'cloud': fakeModel(name: 'c', throwBeforeToken: true),
      },
      strategy: _Pick(['onDevice', 'cloud']),
    );
    expect(() => model.fn(_req(), _blockingCtx), throwsA(isA<StateError>()));
  });

  test('empty route at top level throws config error', () async {
    final model = hybridModel(
      branches: {'cloud': fakeModel(name: 'c')},
      strategy: _Pick([]),
    );
    expect(() => model.fn(_req(), _blockingCtx), throwsA(isA<GenkitException>()));
  });

  test('unknown branch key throws config error', () async {
    final model = hybridModel(
      branches: {'cloud': fakeModel(name: 'c')},
      strategy: _Pick(['nope']),
    );
    expect(() => model.fn(_req(), _blockingCtx), throwsA(isA<GenkitException>()));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd genkit_hybrid && dart test test/hybrid_model_test.dart`
Expected: FAIL — `hybrid_model.dart` not found / `hybridModel` undefined.

- [ ] **Step 3: Write minimal implementation (blocking path only)**

`lib/src/hybrid_model.dart`:
```dart
import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart';

import 'routing_context.dart';
import 'routing_strategy.dart';

/// Branch key for the on-device model in the binary façade.
const String kOnDevice = 'onDevice';

/// Branch key for the cloud model in the binary façade.
const String kCloud = 'cloud';

/// Builds a hybrid [Model] that routes each request to one of [branches]
/// according to [strategy]. The result is an ordinary [Model]: callers use it
/// via `ai.generate(model: theResult)` exactly like any other model.
Model hybridModel({
  required Map<String, Model> branches,
  required RoutingStrategy strategy,
}) {
  if (branches.isEmpty) {
    throw ArgumentError.value(branches, 'branches', 'must not be empty');
  }
  return Model(
    name: 'hybrid',
    fn: (request, context) async {
      final order = strategy.route(RoutingContext(
        request: request,
        branchKeys: branches.keys.toSet(),
        isStreaming: context.streamingRequested,
      ));

      if (order.isEmpty) {
        throw GenkitException(
          'RoutingStrategy returned no branch to route to.',
          status: StatusCodes.FAILED_PRECONDITION,
        );
      }
      for (final key in order) {
        if (!branches.containsKey(key)) {
          throw GenkitException(
            'RoutingStrategy returned unknown branch key "$key". '
            'Available: ${branches.keys.join(', ')}.',
            status: StatusCodes.FAILED_PRECONDITION,
          );
        }
      }

      // Blocking path (streaming handled in a later task).
      for (var i = 0; i < order.length; i++) {
        final key = order[i];
        final isLast = i == order.length - 1;
        try {
          return await branches[key]!.fn(request, context);
        } catch (_) {
          if (isLast) rethrow;
        }
      }
      // Unreachable: loop either returns or rethrows on the last branch.
      throw StateError('unreachable');
    },
  );
}

/// Binary façade over [hybridModel] for the common on-device/cloud case.
Model hybridModelOnDeviceCloud({
  required Model onDevice,
  required Model cloud,
  required RoutingStrategy strategy,
}) {
  return hybridModel(
    branches: {kOnDevice: onDevice, kCloud: cloud},
    strategy: strategy,
  );
}
```

> Note on the context record: the blocking tests pass a literal `ActionFnArg` record with fields `streamingRequested`, `sendChunk`, `context`, `abortSignal`, `trace`. If genkit 0.13.2's record has different/additional fields, copy the exact field set from `package:genkit` `ActionFnArg` typedef when writing `_blockingCtx` in the test. The factory itself only reads `context.streamingRequested` and forwards `context` unchanged on the blocking path.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd genkit_hybrid && dart test test/hybrid_model_test.dart`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/hybrid_model.dart genkit_hybrid/test/hybrid_model_test.dart
git commit -m "feat(genkit_hybrid): hybridModel factory with routing + blocking fallback"
```

---

## Task 6: Streaming path — fallback only before first token

**Files:**
- Modify: `genkit_hybrid/lib/src/hybrid_model.dart`
- Test: extend `genkit_hybrid/test/hybrid_model_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/hybrid_model_test.dart`. First a streaming context helper that records chunks:
```dart
({List<String> received, dynamic ctx}) _streamingCtx() {
  final received = <String>[];
  final ctx = (
    streamingRequested: true,
    sendChunk: (ModelResponseChunk chunk) {
      final part = chunk.content.first;
      if (part is TextPart) received.add(part.text);
    },
    context: <String, dynamic>{},
    abortSignal: null,
    trace: null,
  );
  return (received: received, ctx: ctx);
}
```
Then the tests:
```dart
  test('streaming: branch fails before first token → next branch used', () async {
    final s = _streamingCtx();
    final model = hybridModel(
      branches: {
        'onDevice': fakeModel(name: 'd', throwBeforeToken: true),
        'cloud': fakeModel(name: 'c', text: 'done', chunks: ['he', 'llo']),
      },
      strategy: _Pick(['onDevice', 'cloud']),
    );
    final res = await model.fn(_req(), s.ctx);
    expect(s.received, ['he', 'llo']);
    expect((res.message!.content.first as TextPart).text, 'done');
  });

  test('streaming: branch fails AFTER first token → error propagates, no re-route', () async {
    final s = _streamingCtx();
    var cloudCalls = 0;
    final model = hybridModel(
      branches: {
        'onDevice': fakeModel(name: 'd', chunks: ['partial'], throwAfterToken: true),
        'cloud': fakeModel(name: 'c', text: 'should-not-run', onCall: () => cloudCalls++),
      },
      strategy: _Pick(['onDevice', 'cloud']),
    );
    expect(() => model.fn(_req(), s.ctx), throwsA(isA<StateError>()));
    // The first token was already delivered to the caller.
    expect(s.received, ['partial']);
    // Cloud must NOT have been called — no silent re-route mid-stream.
    expect(cloudCalls, 0);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd genkit_hybrid && dart test test/hybrid_model_test.dart`
Expected: FAIL — the "after first token" test currently re-routes to cloud (blocking loop catches and falls back), so `cloudCalls` is 1, not 0.

- [ ] **Step 3: Implement the streaming path**

In `lib/src/hybrid_model.dart`, replace the blocking-only loop body inside `fn` with a streaming-aware version:
```dart
      // Decide path by streaming flag.
      if (!context.streamingRequested) {
        // Blocking path: try each branch, fall back on failure.
        for (var i = 0; i < order.length; i++) {
          final key = order[i];
          final isLast = i == order.length - 1;
          try {
            return await branches[key]!.fn(request, context);
          } catch (_) {
            if (isLast) rethrow;
          }
        }
        throw StateError('unreachable');
      }

      // Streaming path: fall back ONLY before the first token is emitted.
      for (var i = 0; i < order.length; i++) {
        final key = order[i];
        final isLast = i == order.length - 1;
        var firstTokenSent = false;
        // Wrap sendChunk to detect the first emitted token.
        final wrappedContext = (
          streamingRequested: true,
          sendChunk: (ModelResponseChunk chunk) {
            firstTokenSent = true;
            context.sendChunk(chunk);
          },
          context: context.context,
          abortSignal: context.abortSignal,
          trace: context.trace,
        );
        try {
          return await branches[key]!.fn(request, wrappedContext);
        } catch (e) {
          // If a token was already streamed, we cannot re-route — propagate.
          if (firstTokenSent || isLast) rethrow;
          // else: failed before first token → try next branch.
        }
      }
      throw StateError('unreachable');
```

> Note: construct `wrappedContext` with the EXACT field set of genkit 0.13.2's `ActionFnArg` record. The fields shown (`streamingRequested`, `sendChunk`, `context`, `abortSignal`, `trace`) must match; copy missing fields straight from the typedef if the real record differs. We change only `sendChunk`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd genkit_hybrid && dart test test/hybrid_model_test.dart`
Expected: PASS (all tests, including both streaming cases).

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/hybrid_model.dart genkit_hybrid/test/hybrid_model_test.dart
git commit -m "feat(genkit_hybrid): streaming fallback only before first token"
```

---

## Task 7: PreRoutingStrategy

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/pre_routing.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

Add import to `test/routing_strategy_test.dart`:
```dart
import 'package:genkit_hybrid/src/strategies/pre_routing.dart';
```
Add test:
```dart
  test('PreRoutingStrategy wraps a function and returns single key', () {
    final s = PreRoutingStrategy((c) => c.isStreaming ? 'cloud' : 'onDevice');
    const stream = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: true);
    const block = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(stream), ['cloud']);
    expect(s.route(block), ['onDevice']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `pre_routing.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/pre_routing.dart`:
```dart
import '../routing_context.dart';
import '../routing_strategy.dart';

/// Picks a single branch using a developer-supplied function.
///
/// The universal escape hatch for any app-specific rule (privacy, cost,
/// user tier, etc.) that the package cannot compute itself.
class PreRoutingStrategy implements RoutingStrategy {
  PreRoutingStrategy(this._select);

  final String Function(RoutingContext context) _select;

  @override
  List<String> route(RoutingContext context) => [_select(context)];
}
```

> Note: in Task 14 this is hardened so that a returned empty string `''` means
> "no decision" (returns `[]`), enabling the `FirstMatch` recipe. The minimal
> version here is correct for this task's test; the empty-string idiom is added later.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/pre_routing.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add PreRoutingStrategy"
```

---

## Task 8: FallbackStrategy

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/fallback.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

Add import:
```dart
import 'package:genkit_hybrid/src/strategies/fallback.dart';
```
Add test:
```dart
  test('FallbackStrategy returns its fixed order regardless of context', () {
    final s = FallbackStrategy(['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `fallback.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/fallback.dart`:
```dart
import '../routing_context.dart';
import '../routing_strategy.dart';

/// Returns a fixed priority order of branch keys. The factory tries each in
/// turn until one succeeds (e.g. `['onDevice','cloud']` = PREFER_ON_DEVICE).
class FallbackStrategy implements RoutingStrategy {
  FallbackStrategy(this._order)
      : assert(_order.length > 0, 'order must not be empty');

  final List<String> _order;

  @override
  List<String> route(RoutingContext context) => List.unmodifiable(_order);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/fallback.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add FallbackStrategy"
```

---

## Task 9: ConnectivityStrategy

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/connectivity.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

Add import:
```dart
import 'package:genkit_hybrid/src/strategies/connectivity.dart';
```
Add test:
```dart
  test('ConnectivityStrategy routes by online/offline', () {
    var online = true;
    final s = ConnectivityStrategy(
      isOnline: () => online,
      online: 'cloud',
      offline: 'onDevice',
    );
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud']);
    online = false;
    expect(s.route(ctx), ['onDevice']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `connectivity.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/connectivity.dart`:
```dart
import '../routing_context.dart';
import '../routing_strategy.dart';

/// Routes by network availability. The app supplies [isOnline]; the package
/// depends on no connectivity SDK.
class ConnectivityStrategy implements RoutingStrategy {
  ConnectivityStrategy({
    required bool Function() isOnline,
    required String online,
    required String offline,
  })  : _isOnline = isOnline,
        _online = online,
        _offline = offline;

  final bool Function() _isOnline;
  final String _online;
  final String _offline;

  @override
  List<String> route(RoutingContext context) =>
      [_isOnline() ? _online : _offline];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/connectivity.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add ConnectivityStrategy"
```

---

## Task 10: InputSizeStrategy

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/input_size.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

The size signal = total character count of all text parts across all messages in `request`. A null request counts as size 0.

- [ ] **Step 1: Write the failing test**

Add import:
```dart
import 'package:genkit_hybrid/src/strategies/input_size.dart';
```
Add test:
```dart
  test('InputSizeStrategy routes by total prompt char length', () {
    final s = InputSizeStrategy(threshold: 10, small: 'onDevice', large: 'cloud');
    final shortReq = ModelRequest(messages: [
      Message(role: Role.user, content: [TextPart(text: 'hi')]),
    ]);
    final longReq = ModelRequest(messages: [
      Message(role: Role.user, content: [TextPart(text: 'this is a long prompt')]),
    ]);
    RoutingContext ctx(ModelRequest r) =>
        RoutingContext(request: r, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx(shortReq)), ['onDevice']);
    expect(s.route(ctx(longReq)), ['cloud']);
  });

  test('InputSizeStrategy treats null request as size 0 (small)', () {
    final s = InputSizeStrategy(threshold: 10, small: 'onDevice', large: 'cloud');
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `input_size.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/input_size.dart`:
```dart
import 'package:genkit/genkit.dart';

import '../routing_context.dart';
import '../routing_strategy.dart';

/// Routes by input length: total character count of all text parts in the
/// request. At or below [threshold] → [small] branch, above → [large] branch.
class InputSizeStrategy implements RoutingStrategy {
  InputSizeStrategy({
    required this.threshold,
    required this.small,
    required this.large,
  });

  final int threshold;
  final String small;
  final String large;

  @override
  List<String> route(RoutingContext context) {
    final size = _charCount(context.request);
    return [size > threshold ? large : small];
  }

  int _charCount(ModelRequest? request) {
    if (request == null) return 0;
    var total = 0;
    for (final message in request.messages) {
      for (final part in message.content) {
        if (part is TextPart) total += part.text.length;
      }
    }
    return total;
  }
}
```

> Note: confirm `ModelRequest.messages`, `Message.content`, and `TextPart.text` names against genkit 0.13.2 (`request_converter.dart` in this repo already iterates `request.messages` and message content, so these names are correct for this version).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/input_size.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add InputSizeStrategy"
```

---

## Task 11: FirstMatch combinator

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/first_match.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

- [ ] **Step 1: Write the failing test**

Add import:
```dart
import 'package:genkit_hybrid/src/strategies/first_match.dart';
```
Add test (reuses `_ConstStrategy` defined at the bottom of the file):
```dart
  test('FirstMatch returns first non-empty child result; skips empty', () {
    final s = FirstMatch([
      _ConstStrategy([]),            // no decision → skipped
      _ConstStrategy(['cloud']),     // first match
      _ConstStrategy(['onDevice']),  // never reached
    ]);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud']);
  });

  test('FirstMatch returns empty when all children are empty', () {
    final s = FirstMatch([_ConstStrategy([]), _ConstStrategy([])]);
    const ctx = RoutingContext(request: null, branchKeys: {'cloud'}, isStreaming: false);
    expect(s.route(ctx), isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `first_match.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/first_match.dart`:
```dart
import '../routing_context.dart';
import '../routing_strategy.dart';

/// Tries each child strategy in order; the first to return a non-empty result
/// wins. Returns empty if no child decides (which is a config error at the top
/// level, but valid when nested inside another combinator).
class FirstMatch implements RoutingStrategy {
  FirstMatch(this._children);

  final List<RoutingStrategy> _children;

  @override
  List<String> route(RoutingContext context) {
    for (final child in _children) {
      final result = child.route(context);
      if (result.isNotEmpty) return result;
    }
    return const [];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/first_match.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add FirstMatch combinator"
```

---

## Task 12: WithFallback combinator

**Files:**
- Create: `genkit_hybrid/lib/src/strategies/with_fallback.dart`
- Test: extend `genkit_hybrid/test/routing_strategy_test.dart`

`WithFallback` takes an inner strategy's pick and appends a fallback tail, de-duplicating keys already present in the inner result (preserving order, inner keys first).

- [ ] **Step 1: Write the failing test**

Add import:
```dart
import 'package:genkit_hybrid/src/strategies/with_fallback.dart';
```
Add test:
```dart
  test('WithFallback appends fallback tail to inner pick', () {
    final s = WithFallback(_ConstStrategy(['cloud']), fallbackOrder: ['onDevice']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['cloud', 'onDevice']);
  });

  test('WithFallback de-dupes keys already chosen by inner strategy', () {
    final s = WithFallback(_ConstStrategy(['onDevice']), fallbackOrder: ['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });

  test('WithFallback returns just the tail when inner is empty', () {
    final s = WithFallback(_ConstStrategy([]), fallbackOrder: ['onDevice', 'cloud']);
    const ctx = RoutingContext(request: null, branchKeys: {'onDevice', 'cloud'}, isStreaming: false);
    expect(s.route(ctx), ['onDevice', 'cloud']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: FAIL — `with_fallback.dart` not found.

- [ ] **Step 3: Write minimal implementation**

`lib/src/strategies/with_fallback.dart`:
```dart
import '../routing_context.dart';
import '../routing_strategy.dart';

/// Wraps an [inner] strategy and appends a fixed [fallbackOrder] tail to its
/// pick, turning a pure pick into pick + fallback. Keys already produced by
/// [inner] are not duplicated (inner order preserved, then remaining tail).
class WithFallback implements RoutingStrategy {
  WithFallback(this._inner, {required List<String> fallbackOrder})
      : _fallbackOrder = fallbackOrder;

  final RoutingStrategy _inner;
  final List<String> _fallbackOrder;

  @override
  List<String> route(RoutingContext context) {
    final result = <String>[..._inner.route(context)];
    for (final key in _fallbackOrder) {
      if (!result.contains(key)) result.add(key);
    }
    return result;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/routing_strategy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/lib/src/strategies/with_fallback.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "feat(genkit_hybrid): add WithFallback combinator"
```

---

## Task 13: Public exports

**Files:**
- Modify: `genkit_hybrid/lib/genkit_hybrid.dart`
- Test: Create `genkit_hybrid/test/exports_test.dart`

- [ ] **Step 1: Write the failing test**

`test/exports_test.dart`:
```dart
import 'package:genkit_hybrid/genkit_hybrid.dart';
import 'package:test/test.dart';

void main() {
  test('public API is exported', () {
    // These references compile only if exported from the barrel file.
    expect(kOnDevice, 'onDevice');
    expect(kCloud, 'cloud');
    expect(FallbackStrategy(['cloud']).route(
      const RoutingContext(request: null, branchKeys: {'cloud'}, isStreaming: false),
    ), ['cloud']);
    expect(PreRoutingStrategy((_) => 'cloud'), isA<RoutingStrategy>());
    expect(ConnectivityStrategy(isOnline: () => true, online: 'cloud', offline: 'onDevice'),
        isA<RoutingStrategy>());
    expect(InputSizeStrategy(threshold: 1, small: 'a', large: 'b'), isA<RoutingStrategy>());
    expect(FirstMatch(const []), isA<RoutingStrategy>());
    expect(WithFallback(FallbackStrategy(['cloud']), fallbackOrder: const []),
        isA<RoutingStrategy>());
    expect(hybridModel, isNotNull);
    expect(hybridModelOnDeviceCloud, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd genkit_hybrid && dart test test/exports_test.dart`
Expected: FAIL — names not exported / undefined.

- [ ] **Step 3: Write the barrel file**

`lib/genkit_hybrid.dart`:
```dart
/// Provider-agnostic hybrid routing for Genkit.
///
/// Combine existing Genkit models behind one routing policy and use the
/// result as an ordinary `Model` via `ai.generate`.
library;

export 'src/routing_context.dart';
export 'src/routing_strategy.dart';
export 'src/hybrid_model.dart' show hybridModel, hybridModelOnDeviceCloud, kOnDevice, kCloud;
export 'src/strategies/pre_routing.dart';
export 'src/strategies/fallback.dart';
export 'src/strategies/connectivity.dart';
export 'src/strategies/input_size.dart';
export 'src/strategies/first_match.dart';
export 'src/strategies/with_fallback.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd genkit_hybrid && dart test test/exports_test.dart`
Expected: PASS.

- [ ] **Step 5: Run full suite + analyze**

Run: `cd genkit_hybrid && dart analyze && dart test`
Expected: No analyzer issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add genkit_hybrid/lib/genkit_hybrid.dart genkit_hybrid/test/exports_test.dart
git commit -m "feat(genkit_hybrid): public exports + barrel test"
```

---

## Task 14: README with recipes

**Files:**
- Create: `genkit_hybrid/README.md`
- Create: `genkit_hybrid/example/genkit_hybrid_example.dart`

- [ ] **Step 1: Write the README**

`README.md`:
````markdown
# genkit_hybrid

Provider-agnostic hybrid routing for [Genkit](https://pub.dev/packages/genkit). Combine
existing Genkit models (on-device, cloud, anything) behind one routing policy. The result
is an ordinary `Model` — your app still calls a single `ai.generate`.

```dart
import 'package:genkit_hybrid/genkit_hybrid.dart';

// onDeviceModel and cloudModel are ordinary Genkit Models you already have.
final smart = hybridModelOnDeviceCloud(
  onDevice: onDeviceModel,
  cloud: cloudModel,
  strategy: ConnectivityStrategy(
    isOnline: () => connectivity.isOnline,
    online: kCloud,
    offline: kOnDevice,
  ),
);

final res = await ai.generate(model: smart, prompt: 'Hello!');
```

## Strategies

| Strategy | What it decides on |
|---|---|
| `PreRoutingStrategy(fn)` | your own function (privacy, cost, user tier…) |
| `FallbackStrategy(order)` | fixed priority order (PREFER_ON_DEVICE / PREFER_IN_CLOUD) |
| `ConnectivityStrategy(...)` | network availability |
| `InputSizeStrategy(...)` | prompt length |
| `FirstMatch([...])` | first child strategy that decides (chain of rules) |
| `WithFallback(s, order)` | any strategy's pick + a guaranteed fallback tail |

### Recipe: PREFER_ON_DEVICE
```dart
hybridModelOnDeviceCloud(
  onDevice: onDeviceModel, cloud: cloudModel,
  strategy: FallbackStrategy([kOnDevice, kCloud]),
);
```

### Recipe: PREFER_IN_CLOUD
```dart
hybridModelOnDeviceCloud(
  onDevice: onDeviceModel, cloud: cloudModel,
  strategy: FallbackStrategy([kCloud, kOnDevice]),
);
```

### Recipe: route by rule, then fall back
```dart
hybridModelOnDeviceCloud(
  onDevice: onDeviceModel, cloud: cloudModel,
  strategy: WithFallback(
    FirstMatch([
      PreRoutingStrategy((c) => userOptedOutOfCloud ? kOnDevice : ''),  // '' = no decision
      ConnectivityStrategy(isOnline: () => net.isOnline, online: kCloud, offline: kOnDevice),
    ]),
    fallbackOrder: [kOnDevice],
  ),
);
```

## Streaming + fallback

Fallback during streaming happens **only before the first token**. If a branch fails
before emitting any token, the next branch is tried transparently. Once the first token has
streamed, a later failure propagates as an error (a partially delivered response cannot be
silently re-routed).

## Not in v1

- Cascading by confidence (on-device runtimes don't expose a confidence signal).
- A registered Genkit plugin with a named action (the factory returns a `Model` directly).
````

> Note: in the `FirstMatch` recipe, `PreRoutingStrategy` returns `''` to mean "no decision". Confirm the empty-string-as-skip behavior: `PreRoutingStrategy` returns `[select(c)]`, so `''` yields `['']` which is non-empty and would be treated as a (bogus) decision. **Fix in this task:** make `PreRoutingStrategy` treat an empty-string return as "no decision" → returns `[]`. Update `pre_routing.dart` accordingly and add a test (see Step 2).

- [ ] **Step 2: Harden PreRoutingStrategy for the "no decision" idiom**

Update `lib/src/strategies/pre_routing.dart` `route`:
```dart
  @override
  List<String> route(RoutingContext context) {
    final key = _select(context);
    return key.isEmpty ? const [] : [key];
  }
```
Add test to `test/routing_strategy_test.dart`:
```dart
  test('PreRoutingStrategy treats empty-string return as no decision', () {
    final s = PreRoutingStrategy((_) => '');
    const ctx = RoutingContext(request: null, branchKeys: {'cloud'}, isStreaming: false);
    expect(s.route(ctx), isEmpty);
  });
```

- [ ] **Step 3: Write the example**

`example/genkit_hybrid_example.dart`:
```dart
import 'package:genkit_hybrid/genkit_hybrid.dart';

/// Minimal illustration. `onDeviceModel` and `cloudModel` are ordinary Genkit
/// Models provided by the host app (e.g. from genkit_flutter_gemma and googleAI).
void buildHybrid(/* Model onDeviceModel, Model cloudModel */) {
  // Prefer on-device, fall back to cloud on failure/offline:
  // final smart = hybridModelOnDeviceCloud(
  //   onDevice: onDeviceModel,
  //   cloud: cloudModel,
  //   strategy: FallbackStrategy([kOnDevice, kCloud]),
  // );
}
```

- [ ] **Step 4: Run full suite + analyze**

Run: `cd genkit_hybrid && dart analyze && dart test`
Expected: No analyzer issues; all tests pass (including the new PreRouting empty-string test).

- [ ] **Step 5: Commit**

```bash
git add genkit_hybrid/README.md genkit_hybrid/example/genkit_hybrid_example.dart genkit_hybrid/lib/src/strategies/pre_routing.dart genkit_hybrid/test/routing_strategy_test.dart
git commit -m "docs(genkit_hybrid): README recipes + example; PreRouting empty=no-decision"
```

---

## Task 15: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `cd genkit_hybrid && dart analyze`
Expected: "No issues found!"

- [ ] **Step 2: Full test suite**

Run: `cd genkit_hybrid && dart test`
Expected: All tests pass. Confirm count covers: RoutingContext, RoutingStrategy, all 6 strategies, factory routing, blocking fallback, streaming before/after first token, config errors, exports.

- [ ] **Step 3: Dry-run publish check**

Run: `cd genkit_hybrid && dart pub publish --dry-run`
Expected: Package validates (warnings about example/CHANGELOG acceptable; no errors). Add a minimal `CHANGELOG.md` if the tool flags it missing.

- [ ] **Step 4: Final commit (if CHANGELOG added)**

```bash
git add genkit_hybrid/CHANGELOG.md
git commit -m "docs(genkit_hybrid): add CHANGELOG for 0.1.0"
```
