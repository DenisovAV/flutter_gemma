# genkit_hybrid

Provider-agnostic hybrid routing for [Genkit](https://pub.dev/packages/genkit). Combine
existing Genkit models (on-device, cloud, anything) behind one routing policy. The result
is an ordinary `Model` — your app still calls a single `ai.generate`.

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_hybrid/genkit_hybrid.dart';

final ai = Genkit();

// onDeviceModel and cloudModel are ordinary Genkit Models you already have —
// e.g. from genkit_flutter_gemma (on-device) and genkit_google_genai (cloud).
final smart = hybridModelOnDeviceCloud(
  onDevice: onDeviceModel,
  cloud: cloudModel,
  strategy: ConnectivityStrategy(
    isOnline: () => connectivity.isOnline,
    online: kCloud,
    offline: kOnDevice,
  ),
);

// The hybrid model is an ordinary Model — register it, then use it like any other.
ai.registry.register(smart);

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
| `WithFallback(s, fallbackOrder: order)` | any strategy's pick + a guaranteed fallback tail |

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
      PreRoutingStrategy((c) => userOptedOutOfCloud ? kOnDevice : ''), // '' = no decision
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

## Error policy

Fallback fires on **transient/availability** failures (network/timeout/OOM, or `GenkitException`
with `UNAVAILABLE` / `DEADLINE_EXCEEDED` / `RESOURCE_EXHAUSTED` / `INTERNAL`). **Permanent**
errors (`INVALID_ARGUMENT`, `PERMISSION_DENIED`, `UNAUTHENTICATED`, `FAILED_PRECONDITION`,
`NOT_FOUND`) propagate immediately — they would fail the same way on every branch.

## Not in v1

- Cascading by confidence (on-device runtimes don't expose a confidence signal).
- A registered Genkit plugin with a named action (the factory returns a `Model` directly).
