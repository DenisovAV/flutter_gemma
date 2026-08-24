---
title: ONNX Runtime
description: Run ONNX models on-device — text generation via ORT-GenAI and embeddings via plain ONNX Runtime — across five native platforms (dart:ffi) and the web (Transformers.js / onnxruntime-web).
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma's engines are **pluggable**: you register them in
`FlutterGemma.initialize(...)`, and the registry picks one per model by its
declared `ModelFileType`. `flutter_gemma_onnx` adds two of them from the
[ONNX Runtime](https://onnxruntime.ai) family:

- **`OnnxEngine`** — text generation via **ORT-GenAI**.
- **`OnnxEmbeddingBackend`** — embeddings via **plain ONNX Runtime** (no
  generation).

On **native** platforms both are pure `dart:ffi` — no JVM, no gRPC — and each
drives the native library from a long-lived worker isolate, so no FFI pointer
crosses an isolate boundary. On **Web** there is no FFI: generation runs through
Transformers.js and embeddings through onnxruntime-web, behind the same public
API. Either arm can be registered on its own — they don't depend on each other.

## Platforms

Native support is **arm64/x64-gated** — each host is device-verified end-to-end
(generation + embeddings):

| Platform | Runtime | `OnnxEngine` / `OnnxEmbeddingBackend` |
|----------|---------|----------------------------------------|
| macOS (Apple Silicon) | ORT-GenAI + ORT via `dart:ffi` | ✅ ~54 tok/s (M4 Pro) |
| Linux x64 | ORT-GenAI + ORT via `dart:ffi` | ✅ ~5.3–5.8 tok/s |
| Windows x64 | ORT-GenAI + ORT via `dart:ffi` | ✅ ~3.3 tok/s |
| Android (arm64) | ORT-GenAI + ORT via `dart:ffi` | ✅ ~10.4 tok/s (Pixel 8 Pro) |
| iOS (arm64) | ORT-GenAI + ORT via `dart:ffi` | ✅ device-verified |
| Web | Transformers.js + onnxruntime-web (WebGPU/WASM) | ✅ both arms |

> On an unsupported native host (macOS Intel, or any other native ABI)
> `OnnxEngine` politely declines and logs why, letting another registered engine
> take over. Android needs **`minSdk 24`** (both ORT and ORT-GenAI AARs declare
> `minSdkVersion=24`). The native library co-location — ORT loaded next to
> ORT-GenAI — is handled by the package's build hook; you don't configure
> anything.

## Setup

Add the package and register whichever arm(s) you use at startup:

```yaml
dependencies:
  flutter_gemma: latest_version
  flutter_gemma_onnx: latest_version   # ONNX Runtime engines
```

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';

await FlutterGemma.initialize(
  inferenceEngines: [OnnxEngine()],            // text generation
  embeddingBackends: [OnnxEmbeddingBackend()], // embeddings
);
```

## Install a model

ONNX models install with `fileType: ModelFileType.onnx`. What that means differs
by platform.

**Native — a directory, not a file.** An ORT-GenAI model is a **directory**
(`genai_config.json` + `model.onnx` [+ `model.onnx_data` for external weights] +
tokenizer files). `OnnxEngine` takes the tracked file's **parent directory** as
the model directory, so the whole bundle must already live on disk together
(e.g. shipped as an asset or pre-populated yourself):

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.onnx,
).fromFile('/path/to/my-model/genai_config.json').install();
```

**Web — fileless.** The model identity is a **Hugging Face repo id**;
Transformers.js resolves, fetches, and caches it the first time you run
inference. Install just marks the repo id active — core never downloads model
bytes:

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.onnx,
).fromNetwork('onnx-community/Qwen2.5-0.5B-Instruct').install();
```

From here the code is identical to any other engine:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
final session = await model.createSession();
await session.addQueryChunk(const Message(text: 'Hello!', isUser: true));
final response = await session.getResponse();
```

## Generation — `OnnxEngine`

Text-only, greedy decoding, one session at a time (v1): no vision, no audio, no
LoRA, no sampling parameters yet. Prompts use the model's own chat template
(ORT-GenAI's `OgaTokenizerApplyChatTemplate` natively; the model's
`chat_template` on Web) — the engine never builds turn markers itself.
`PreferredBackend.cpu` pins WASM on Web; anything else tries WebGPU first and
falls back to WASM.

## Embeddings — `OnnxEmbeddingBackend`

A plain ONNX Runtime forward pass over an `.onnx`/`.ort` embedding model. One
factory handles both tokenizer families, and the **output dimension is
model-dependent** (not a fixed 768):

- **WordPiece / BERT-style** models (e.g. all-MiniLM-L6-v2, 384-dim) —
  mean-pooled + normalized client-side.
- **SentencePiece** models (e.g. EmbeddingGemma-300M-ONNX) — the model's own
  pooled `sentence_embedding` output. **Native only** — on Web, embeddings are
  WordPiece/BERT-style only in this release (a pure-Dart SentencePiece parser is
  pending).

The output contract and mask requirements are discovered from the session's
actual graph once it opens — no per-model configuration. It registers at
priority 10 (above `LiteRtEmbeddingBackend`'s catch-all priority 0), so with
both registered an `.onnx`/`.ort` model routes here. See
[Embeddings & RAG](/docs/embeddings-and-rag) for the shared embedding API.

## Web setup

Web needs a small `web/index.html` shim before `FlutterGemma.initialize()` runs
(the same readiness-handshake pattern the other web arms use). Add the shim for
whichever arm(s) you register, in `<head>`, ahead of `flutter_bootstrap.js`:

```html
<!-- Transformers.js v4 — OnnxEngine web generation. -->
<script type="module">
window.transformersReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.2.0');
  window.transformers = m;
  return m;
})();
</script>

<!-- onnxruntime-web — OnnxEmbeddingBackend web embeddings. -->
<script type="module">
window.ortReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/onnxruntime-web@1.27.0/dist/ort.bundle.min.mjs');
  m.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.27.0/dist/';
  window.ort = m;
  return m;
})();
</script>
```

Dart awaits `window.transformersReady` / `window.ortReady` before touching
either module, so the shim must run before the Flutter app boots.

## See also

- [Embeddings & RAG](/docs/embeddings-and-rag) — the shared embedding API this
  backend plugs into.
- [Models](/docs/models) — the full supported-model matrix.
- [Packages](/docs/packages) — every opt-in engine and backend, including
  `flutter_gemma_onnx`.
