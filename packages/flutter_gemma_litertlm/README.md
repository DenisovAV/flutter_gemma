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
