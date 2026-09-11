---
name: flutter-gemma-onnx
description: Use when running ONNX models with flutter_gemma_onnx — ORT-GenAI text generation (e.g. Phi-3.5-mini) or ONNX embeddings — on macOS arm64, Linux x64, Windows x64, Android arm64, iOS arm64, or in the browser through Transformers.js. Also use when an ONNX install is routed to the wrong engine, genai_config.json is missing, or getActiveModel throws "No inference engine can handle this model" on another platform. Not for .litertlm or .task models.
---

# The ONNX engine

## Rules

1. Declare `fileType: ModelFileType.onnx`. Without it the install defaults to `task` and never reaches `OnnxEngine`.
2. An ORT-GenAI model is a directory — `genai_config.json`, the `.onnx` graph, its weights and a tokenizer. Install it with `fromHuggingFace(repo)`, which downloads the whole folder, or point `fromFile` at a local `genai_config.json`. A single-file download or a Flutter asset cannot produce it.
3. Native generation runs on macOS arm64, Linux x64, Windows x64, Android arm64 and iOS arm64. Anywhere else no engine accepts the model and `getActiveModel` throws `No inference engine can handle this model`.
4. Android needs `minSdk 24`. Phi-3.5-mini peaks near 3.7 GB of RAM — target 8 GB devices.
5. Text only: no images, no audio, no LoRA.

## Setup

```dart
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';

await FlutterGemma.initialize(
  inferenceEngines: [OnnxEngine()],
  embeddingBackends: [OnnxEmbeddingBackend()],
);

await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.onnx,
).fromHuggingFace('microsoft/Phi-3.5-mini-instruct-onnx').install();

final model = await FlutterGemma.getActiveModel(maxTokens: 4096);
```

A repo with several execution-provider folders resolves to its CPU/mobile folder automatically — the bundled runtime is CPU-only.

A bundle you ship yourself:

```dart
await FlutterGemma.installModel(
  modelType: ModelType.general,
  fileType: ModelFileType.onnx,
).fromFile('$path/genai_config.json').install();
```

## Web

On web `OnnxEngine` runs the model through Transformers.js. The model is a Hugging Face repo id (e.g. `onnx-community/Qwen2.5-0.5B-Instruct`) that the browser downloads and caches on first use. `PreferredBackend.cpu` forces WASM; anything else tries WebGPU first.

Add to `web/index.html` `<head>`, before Flutter boots — the first script for generation, the second for embeddings:

```html
<script type="module">
window.transformersReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.2.0');
  window.transformers = m;
  return m;
})();
</script>
<script type="module">
window.ortReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/onnxruntime-web@1.27.0/dist/ort.bundle.min.mjs');
  m.env.wasm.wasmPaths = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.27.0/dist/';
  window.ort = m;
  return m;
})();
</script>
```

## Embeddings

`OnnxEmbeddingBackend` handles single-file `.onnx` embedding models, installed with `FlutterGemma.installEmbedder()` like any other — see the flutter-gemma-rag skill for the indexing flow.
