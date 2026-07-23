# flutter_gemma_litertlm

LiteRT-LM (`.litertlm`) on-device inference engine for [flutter_gemma](https://pub.dev/packages/flutter_gemma),
via `dart:ffi`. Opt-in package — add it only if you run `.litertlm` models.
Android, iOS, macOS, Linux, Windows.

This package **owns** the shared LiteRT-LM native library (`libLiteRtLm`); it is
also shared by [flutter_gemma_embeddings](https://pub.dev/packages/flutter_gemma_embeddings).

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
| Windows  | ✅ FFI (CPU + Intel NPU; ⚠️ discrete GPU regressed — see below) |
| Web      | ✅ via `@litert-lm/core` (CDN, early preview) |

> ⚠️ **Known regression (1.2.0 / LiteRT-LM v0.14.0):** Windows **discrete GPUs**
> crash in the upstream WebGPU/Dawn stack
> ([LiteRT-LM #2957](https://github.com/google-ai-edge/LiteRT-LM/issues/2957)) —
> use `PreferredBackend.cpu` or `.npu` on Windows until upstream fixes it.
> macOS/Linux GPU and Windows CPU/NPU are unaffected.

The native library is fetched at build time by `hook/build.dart` (Native Assets)
from a SHA256-verified GitHub release — no manual setup on native platforms.

## Troubleshooting

### `dlopen` / "library not found" (`libLiteRtLm`) after removing `flutter_gemma_embeddings`

`flutter_gemma_litertlm` and `flutter_gemma_embeddings` share one native library
(`libLiteRtLm`), bundled exactly once by whichever package's build hook ran
first ("the owner"). If you **had both packages, then removed the owner** and
rebuilt **without** a clean, a stale ownership marker in the shared cache can
leave the library unbundled, surfacing as an opaque `dlopen` "no such file" on
the first inference. Fix:

```bash
flutter clean
rm -rf ~/Library/Caches/flutter_gemma/native        # macOS / Linux
# Windows: rmdir /s "%LOCALAPPDATA%\flutter_gemma\native"  (path may vary)
flutter pub get
```

This is a known limitation of Dart's Native Assets build hooks: a hook is
sandboxed and cannot detect which sibling packages are present in the current
build, so it cannot recompute the registrant per-build (see
[dart-lang/native#190](https://github.com/dart-lang/native/issues/190)). It only
triggers in the narrow remove-the-owner-without-clean case.
