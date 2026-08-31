# flutter_gemma_builtin_ai

Built-in OS AI engine for [flutter_gemma](https://pub.dev/packages/flutter_gemma): runs inference
against the **system/browser-provided** on-device model instead of a bundled Gemma checkpoint —
Gemini Nano via ML Kit GenAI (AICore) on Android, Apple Foundation Models on iOS/macOS, and Gemini
Nano via the Chrome **Prompt API** on Web. Opt-in package: add it only if you want your app to use
whatever model the platform already ships, with no model file to download or bundle.

Because the platform owns the weights, there's nothing to fetch: installation just records which
built-in model you want to use, and `BuiltInAi.ensureReady()` makes sure the feature itself is
turned on (and downloaded, the first time it's used).

## Supported devices & OS floors

| Platform | Model | Minimum devices | Notes |
|----------|-------|------------------|-------|
| Android | Gemini Nano (ML Kit GenAI / AICore) | Pixel 9+, Galaxy S25+ | Best experience on Pixel 10. **Consumer apps require `minSdk 26`** (this package declares it; raise your app's `minSdk` to match). |
| iOS / macOS | Apple Foundation Models | iPhone 15 Pro+, Apple Silicon (M-series) Macs | Requires Apple Intelligence enabled in **Settings → Apple Intelligence & Siri**. Builds from **iOS 15.0** / macOS 10.15 — every Foundation Models call is availability-gated, so the package links and runs below OS 26 and simply reports unavailable. |
| Web | Gemini Nano (Chrome **Prompt API**) | Desktop Chrome/Chromium-Edge only | **Not** Chrome-Android/iOS, **not** Firefox/Safari. Floor: ~22 GB free disk + a GPU with >4 GB VRAM (or a 16 GB-RAM CPU-only path). See [Web setup](#web-setup) — the feature is gated behind an origin trial or a local flag as of this writing. |

Vision (image input) requires **OS 27+** on Apple platforms — on OS 26 Apple Foundation Models is
**text-only**; sending an image throws a platform error instead of being silently ignored. Android
Gemini Nano supports vision on every supported device. The **Web** arm is **text-only in this
release** — image/audio input is accepted by the API surface but dropped with a one-time log
warning (tracked for a follow-up once `expectedInputs:[{type:'image'}]` is verified end-to-end).

Availability is a runtime property of the device/OS/browser, not something this package can
guarantee at build time — always probe it with `BuiltInAi.availability()` or
`BuiltInAi.ensureReady()` before creating a model.

## Web setup

Unlike `flutter_gemma_litertlm`'s web arm, there is **no CDN `<script>` tag to add to
`web/index.html`** — the Chrome Prompt API is a bare global (`self.LanguageModel`) the browser
itself exposes; there is nothing to load. What you need instead is for the browser to have the
feature **enabled**:

- **Production**: register your origin for the [Prompt API origin
  trial](https://developer.chrome.com/origintrials) and add the issued token to `web/index.html`:
  ```html
  <meta http-equiv="origin-trial" content="YOUR_TOKEN_HERE">
  ```
- **Local development**: enable `chrome://flags/#prompt-api-for-gemini-nano` in your own Chrome and
  restart the browser.

⚠️ **Verify before you ship**: whether the Prompt API is still origin-trial/flag-gated on plain web
pages, or has shipped in stable Chrome without a token, changes over time (it has been stable in
*Chrome Extensions* since Chrome 138, but its status on ordinary web pages is the thing to check
against the Chrome version your users actually run). `BuiltInAi.availability()` reports
`unavailableDeviceUnsupported` on any browser/version where the feature isn't on — always probe
before creating a model rather than assuming it's available.

## Quick start

Register the engine at startup, alongside any other engines your app uses:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';

void main() async {
  await FlutterGemma.initialize(
    inferenceEngines: const [BuiltInAiEngine()],
  );
  runApp(MyApp());
}
```

Install a built-in model. Built-in models have no file to download, so installation just records
the identity — pass `fileType: ModelFileType.builtIn` and use `.fromBundled(...)` with one of the
ready-made specs' `name`:

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.builtIn,
).fromBundled(BuiltInAiModels.geminiNano.name).install();
```

Or reference the spec objects directly if you're building your own model list — each is a plain
`InferenceModelSpec`:

```dart
final spec = defaultTargetPlatform == TargetPlatform.android
    ? BuiltInAiModels.geminiNano
    : BuiltInAiModels.appleFoundationModels;
```

Before creating the model, make sure the OS feature is actually ready — this also drives the
Android on-device download the first time the feature is used:

```dart
await BuiltInAi.ensureReady(
  onProgress: (percent) => print('Preparing built-in AI: $percent%'),
);
```

Then load and use the model exactly like any other flutter_gemma engine:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
final response = await session.getResponse();
```

## Feature parity vs. bundled Gemma engines

| Feature | Android (Gemini Nano) | iOS / macOS (Apple FM) | Web (Chrome Prompt API) |
|---------|------------------------|-------------------------|--------------------------|
| Streaming responses | ✅ | ✅ | ✅ |
| Vision (image input) | ✅ | ✅ on OS 27+ only (text-only on OS 26) | ❌ (v1, tracked) |
| Audio input | ❌ | ❌ | ❌ |
| Function calling | ✅ (prompt-based) | ✅ (prompt-based) | ✅ (prompt-based) |
| Thinking mode | ❌ | ❌ | ❌ |
| `sizeInTokens` | ✅ native token count | ✅ on OS 26.4+, built with Xcode 26.4+ (estimate otherwise) | ✅ `measureContextUsage` |
| LoRA weights | ❌ | ❌ | ❌ |

`sizeInTokens` on Apple needs BOTH conditions. `SystemLanguageModel.tokenCount` is
`@available(iOS 26.4, macOS 26.4)`, so the declaration is absent from earlier SDKs —
a package built with Xcode 26.1 cannot call it at all, and one built with 26.4+ still
falls back when RUNNING on an older OS. The fallback is core's `text.length / 4`
estimate, reported through a `TOKENIZER_UNAVAILABLE` error that names which of the two
conditions was missing.

The Chrome Prompt API also supports a web-only JSON-schema `responseConstraint` for structured
output; it is intentionally **not** part of the cross-platform contract above (native has no
equivalent) and is not yet exposed by this package — tracked as a follow-up.

"Prompt-based" function calling means tool definitions are woven into the prompt (by core
`InferenceChat`) rather than using a native structured tool-calling API — the OS models don't
expose a usable one. On **Web**, Chrome's Prompt API native tool use is **experimental and not
production-usable** (verified Chrome 151, Aug 2026): the `tools` option in `create()` is only
accepted behind `chrome://flags/#enable-experimental-web-platform-features`, the structured
`tool-call` output modality still fails `create()`, there is no auto-execute, and even when
accepted the model does not reliably route to the declared tools (it falls back to a built-in
`google_search` pattern or answers as plain text). Function calling therefore goes through the
prompt-based path, which Gemini Nano handles for single-turn calls. Multi-turn agent chaining is
not supported on Web (see `flutter_gemma_agent`).

## Troubleshooting

`BuiltInAi.availability()` / `BuiltInAi.ensureReady()` report a `BuiltInAiAvailability` status
(surfaced via `BuiltInAiUnavailableException.status` when `ensureReady()` fails). The same enum is
shared across all three platforms; the Web column notes how Chrome maps onto it — Chrome's own
`LanguageModel.availability()` only has four states, so `unavailableOsTooOld` /
`unavailableDisabled` never occur on Web.

| Status | Meaning | User-facing remedy | Web notes |
|--------|---------|---------------------|-----------|
| `available` | Ready to use now. | — | — |
| `downloadable` | Feature exists but isn't downloaded yet. | Call `BuiltInAi.ensureReady()` — it triggers the download and reports progress via `onProgress`. | On Web, `ensureReady()` reports a *real* percentage from the browser's `downloadprogress` event. |
| `downloading` | A download is already in progress. | Call `BuiltInAi.ensureReady()` and wait; it polls until ready or the `timeout` elapses. | Same on Web. |
| `unavailableDeviceUnsupported` | This device/browser doesn't have AICore (Android), Apple Intelligence hardware (Apple), or the Prompt API (Web). | Fall back to a bundled model — the device can't run the built-in one. | Also returned when `'LanguageModel' in self` is `false` — wrong browser, wrong platform, or the feature isn't enabled (see [Web setup](#web-setup)). |
| `unavailableOsTooOld` | The OS version is below what the built-in model requires. | Prompt the user to update the OS, or fall back to a bundled model. | Never returned on Web. |
| `unavailableDisabled` | The feature exists but is turned off. | Ask the user to enable it: Apple Intelligence in **Settings → Apple Intelligence & Siri** (iOS/macOS), or the equivalent AICore/Gemini Nano toggle on Android. | Never returned on Web (Chrome folds this into `unavailableDeviceUnsupported`/`unavailableOther`). |
| `unavailableOther` | Unclassified failure. | Fall back to a bundled model; check device/console logs for detail. | Chrome's `'unavailable'` maps here — the browser doesn't report *why* (disk floor, VRAM, flag/origin-trial missing). |

`ensureReady()` throws `BuiltInAiUnavailableException` immediately for every `unavailable*` status
(no download is attempted); it only drives a download from `downloadable`/`downloading`.
