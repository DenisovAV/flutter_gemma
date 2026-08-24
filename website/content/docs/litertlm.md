---
title: LiteRT-LM
description: The default flutter_gemma engine — .litertlm on-device inference over dart:ffi (LiteRT-LM C API) on all five native platforms plus a text-only web preview, with CPU / GPU / NPU acceleration and a LiteRT embedding backend.
image: https://fluttergemma.dev/images/og-image.png
---

`flutter_gemma_litertlm` is flutter_gemma's **default inference engine**. It runs
`.litertlm` models through `dart:ffi` straight onto the **LiteRT-LM C API** — no
JVM, no gRPC — and it is the **only engine for desktop** (macOS, Windows, Linux).
The native library is fetched at build time via **Native Assets** (SHA256-verified,
from the `native-v0.16.0` GitHub release), so there's no manual native setup.

The same package also ships **`LiteRtEmbeddingBackend`**, the LiteRT C API
embedding backend — see [Embeddings & RAG](/docs/embeddings-and-rag).

## Platforms

| Platform | Support |
|----------|---------|
| Android | ✅ FFI (GPU via OpenCL, NPU on Qualcomm Snapdragon) |
| iOS | ✅ FFI (GPU via Metal on device; CPU on simulator) |
| macOS / Linux | ✅ FFI (GPU via Metal / Vulkan) |
| Windows | ✅ FFI (CPU + GPU via DirectX 12 + Intel NPU) |
| Web | ⚠️ early preview via `@litert-lm/core` (text-only) |

> **Web is a text-only preview.** It runs through `@litert-lm/core` (WebGPU/WASM)
> and does **not** support vision, audio, thinking mode, function calling, or
> LoRA. Native platforms have the full feature set. On web you also need the JS
> handshake in `web/index.html` (see [Web setup](#web-setup)).

## Setup

Add the package and register `LiteRtLmEngine()` at startup, alongside any other
engines your app uses:

```yaml
dependencies:
  flutter_gemma: latest_version
  flutter_gemma_litertlm: latest_version   # .litertlm inference engine
```

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

await FlutterGemma.initialize(
  inferenceEngines: const [LiteRtLmEngine()],
);
```

`LiteRtLmEngine` claims models whose declared `ModelFileType` is `litertlm`; pass
it alongside `MediaPipeEngine` (from `flutter_gemma_mediapipe`) if your app also
uses `.task` models.

## Install a `.litertlm` model

> **Declare the file type.** `installModel` defaults `fileType` to
> `ModelFileType.task`, so a `.litertlm` model **must** set
> `fileType: ModelFileType.litertlm` explicitly — otherwise it is routed to
> MediaPipe instead of this engine.

```dart
await FlutterGemma.installModel(
  modelType: ModelType.gemma4,
  fileType: ModelFileType.litertlm,
).fromNetwork(
  'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  token: 'hf_...',
).install();

// Create the model once and keep it for the app's lifetime.
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,
);

final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
await for (final chunk in session.getResponseAsync()) {
  print(chunk);
}
await session.close();
```

## Backends & acceleration

Pick the accelerator with `preferredBackend:` on `getActiveModel`:

| Backend | Where |
|---------|-------|
| `cpu` | All native platforms |
| `gpu` | Metal (Apple), DirectX 12 / WebGPU (Windows), Vulkan / WebGPU (Linux); required on web |
| `npu` | Android (Qualcomm Snapdragon, `.litertlm`) and Windows (Intel LunarLake / PantherLake) |

Windows NPU ships the Intel dispatch stack — `LiteRtDispatch.dll` + the OpenVino
runtime + TBB — inside the Windows native archive. Android bundles the Qualcomm
QNN dispatch stack. No extra downloads for either NPU path.

## `maxTokens` is the CONTEXT window, not the reply length

`maxTokens` (on `getActiveModel` / `createModel`) sizes the whole **context
window** — system prompt + history + message **plus** the generated output (the
KV-cache budget), not the response length. `.litertlm` models bake a fixed
`kv_cache_max_len` of 1024, so this engine **clamps `maxTokens` up to 1024** (with
a log warning) to avoid a native KV-cache crash.

To cap **generation length**, use `maxOutputTokens` on the session:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096); // context
final session = await model.createSession(maxOutputTokens: 100);  // reply cap
```

## Web setup

`.litertlm` web inference runs via `@litert-lm/core`. The ESM doesn't assign
window globals, so add this handshake to your `web/index.html` `<head>` — Dart
awaits `window.litertLmReady` (which resolves to the `Engine` constructor):

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

## See also

- [Desktop Support](/docs/desktop) — the FFI path on macOS / Windows / Linux.
- [Embeddings & RAG](/docs/embeddings-and-rag) — the `LiteRtEmbeddingBackend` this package ships.
- [Packages](/docs/packages) — the full opt-in package matrix and APIs.
