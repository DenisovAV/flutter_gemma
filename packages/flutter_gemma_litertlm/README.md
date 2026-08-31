# flutter_gemma_litertlm

LiteRT-LM (`.litertlm`) on-device inference engine for [flutter_gemma](https://pub.dev/packages/flutter_gemma),
via `dart:ffi`. Opt-in package — add it only if you run `.litertlm` models.
Android, iOS, macOS, Linux, Windows.

This package **owns** the shared LiteRT-LM native library (`libLiteRtLm`) and
exposes the LiteRt interpreter FFI (`LiteRtBindings`); both are shared by
[flutter_gemma_speech](https://pub.dev/packages/flutter_gemma_speech). As of
1.5.0 this package also ships the LiteRT C API embedding backend
(`LiteRtEmbeddingBackend`) — see [Embeddings](#embeddings) below — built over
[flutter_gemma_embeddings](https://pub.dev/packages/flutter_gemma_embeddings)'s
runtime-agnostic embedding pipeline.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  inferenceEngines: [LiteRtLmEngine()],
);
```

`LiteRtLmEngine` handles `ModelFileType.litertlm` models; pass it alongside
other engines (e.g. `MediaPipeEngine` from `flutter_gemma_mediapipe`) if your app
uses both formats.

## Install from a Hugging Face repo (`litertlm_manifest.json`)

Repos that ship a
[`litertlm_manifest.json`](https://github.com/john-rocky/hf-to-litertlm/blob/main/manifest/SCHEMA.md)
deployment manifest describe every `.litertlm` file they contain — which
backends each is verified on, which file a given platform should pick, sha256/
size identity, and session guidance. `LitertlmManifestResolver` reads it so an
app installs "the right file for this device" without hardcoding filenames:

```dart
import 'dart:math' show max;

// LiteRtLmEngine carries this resolver, so registering the engine registers
// it too. Pass huggingFaceResolvers: only to override — e.g.
// [LitertlmManifestResolver(revision: 'abc123')] to pin a commit.
await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

final r = await FlutterGemma.resolveHuggingFace(
    'litert-community/Qwen3-4B-Thinking-2507',
    fileType: ModelFileType.litertlm);
await FlutterGemma.installModel(
      modelType: r.modelType ?? ModelType.general,
      fileType: r.fileType,
    )
    .fromNetwork(r.url) // authoritative: carries the resolver's revision pin
    .install();
final model = await FlutterGemma.getActiveModel(defaults: r.runtime);
final session = await model.createSession(
  enableThinking: r.runtime.isThinking ?? false,
  // minOutputTokens is a floor, not a cap: keep the app's own budget unless
  // the manifest asks for more.
  maxOutputTokens: max(1024, r.runtime.minOutputTokens ?? 0),
);
```

Everything the manifest returns is an overridable default (explicit argument >
manifest > SDK default); `r.notes` carries platform caveats and known issues
worth surfacing to developers. Repos without a manifest keep working through
`installModel(...).fromHuggingFace(repo, file: ...)`.

To resolve and install in one step, omit `file`: `fromHuggingFace(repo)` reads
the manifest at install time, installs the revision-pinned variant, and returns
the same defaults on `InferenceInstallation.runtime` (plus `notes`). The
two-step form above stays the offline-safe one — manifest mode needs the network
on every install, because the variant's filename is only known after the fetch.

## Embeddings

```dart
await FlutterGemma.initialize(
  embeddingBackends: [LiteRtEmbeddingBackend()],
);
```

`LiteRtEmbeddingBackend` runs Gecko / EmbeddingGemma `.tflite` models via the
LiteRT C API (moved here from `flutter_gemma_embeddings` in 1.5.0 — see that
package for the runtime-agnostic tokenization/pooling pipeline it's built on).
On web it runs via LiteRT.js instead; see
[flutter_gemma_embeddings' web setup](https://pub.dev/packages/flutter_gemma_embeddings#web-setup)
for the `<script>` tag your app needs.

## Web setup (early preview)

`.litertlm` web inference runs via `@litert-lm/core` (WebGPU/WASM, text-only).
Add the handshake below to your app's `web/index.html` `<head>` — the ESM doesn't
assign window globals and module scripts are deferred, so Dart awaits
`window.litertLmReady` (which resolves to the `Engine` constructor):

```html
<script type="module">
window.litertLmReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/@litert-lm/core@0.14.0/+esm');
  window.Engine = m.Engine;
  return m.Engine;
})();
</script>
```

Native platforms need no web setup.

## Platforms

| Platform | Support |
|----------|---------|
| Android  | ✅ FFI (GPU via OpenCL, NPU via `.litertlm` on Qualcomm) |
| iOS      | ✅ FFI (GPU via Metal on device; CPU on simulator) |
| macOS / Linux | ✅ FFI (GPU via Metal / Vulkan) |
| Windows  | ✅ FFI (CPU + GPU via DirectX 12 + Intel NPU) |
| Web      | ✅ via `@litert-lm/core` (CDN, early preview) |

> **Fixed in 1.4.0:** Windows **discrete GPUs** crashed on
> `PreferredBackend.gpu` in 1.2.0–1.3.1. Upgrade to 1.4.0; on the affected
> versions use `PreferredBackend.cpu` or `.npu`. macOS/Linux GPU and Windows
> CPU/NPU were never affected.

The native library is fetched at build time by `hook/build.dart` (Native Assets)
from a SHA256-verified GitHub release — no manual setup on native platforms.

## Troubleshooting

### Garbled or empty streams on Android (fixed in 1.5.2)

Symptom: a generation delivers zero chunks and throws
`Exception: Stream error: <U+FFFD>`, often followed by
`Callback invoked after it has been deleted` and a `SIGABRT` that Dart cannot
catch.

Cause: on Android the first `dlopen` of `libLiteRtLm` decides, for the whole
process, whether its exports are reachable from the default symbol search
scope, and bionic never promotes an already-loaded library afterwards. Before
1.5.2 the embeddings and speech entry point opened it locally, so an app that
embedded or transcribed anything before its first generation left the
stream-callback ABI probe unable to see the library — and the probe read that
as "old library" and registered the wrong callback shape.

Fix: upgrade to 1.5.2. If you load `libLiteRtLm` yourself from app or
third-party code, load it before flutter_gemma does and with `RTLD_GLOBAL`.
1.5.2 cannot repair that case — bionic never promotes an already-loaded library
— but it no longer generates corrupt text: a `.litertlm` generation raises a
`StateError` naming the condition, and embeddings or speech (which resolve
through their own handle and do not need the symbols to be ambient) log a
warning and carry on.
See [#447](https://github.com/DenisovAV/flutter_gemma/issues/447).

### `dlopen` / "library not found" (`libLiteRtLm`)

`flutter_gemma_litertlm` is the sole owner of the shared native library
(`libLiteRtLm`) and bundles it via its build hook — this package's own
`LiteRtEmbeddingBackend` and `flutter_gemma_speech` both use it directly. A
stale Native-Assets cache after a
native version bump can leave the library unbundled, surfacing as an opaque
`dlopen` "no such file" on the first inference. Fix with a clean rebuild:

```bash
flutter clean
rm -rf ~/Library/Caches/flutter_gemma/native        # macOS / Linux
# Windows: rmdir /s "%LOCALAPPDATA%\flutter_gemma\native"  (path may vary)
flutter pub get
```
