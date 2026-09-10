---
name: flutter-gemma-onnx
description: Use when running ONNX models through flutter_gemma_onnx — ORT-GenAI text generation or ORT embeddings. An ORT-GenAI model is a DIRECTORY, not a single file, so the ordinary single-file network install does not apply; the package is also gated to five specific host architectures.
---

# The ONNX engine

`flutter_gemma_onnx` provides two things over `dart:ffi` in a worker isolate:
text generation via ORT-GenAI (`OnnxEngine`) and embeddings via plain ORT
(`OnnxEmbeddingBackend`).

```dart
await FlutterGemma.initialize(
  inferenceEngines: [OnnxEngine()],
  embeddingBackends: [OnnxEmbeddingBackend()],
);
```

## An ORT-GenAI model is a DIRECTORY

This is the difference that breaks the usual mental model. The model is not one
file:

```
phi-3.5-mini/
  genai_config.json
  model.onnx
  model.onnx_data        # weights, often several GB
  tokenizer.json
```

`OnnxEngine.createModel` takes that directory's `genai_config.json` and loads
the **parent directory**. The single-file `.fromNetwork(url)` install used for
`.litertlm` and `.task` does not cover this — the files must arrive together,
by bundling them as assets or fetching them into one directory yourself.

Embeddings are the exception: a plain `.onnx` embedding model is a single file
and installs normally.

## Only five host architectures

`OnnxEngine.canHandle` is gated to **macOS arm64, Linux x64, Windows x64,
Android arm64 and iOS arm64**, in lockstep with the build hook that bundles the
native archives. Anywhere else it declines and logs why, so the registry falls
through to another engine rather than failing at load.

`OnnxEmbeddingBackend.canHandle` stays extension-based on every platform — so
that LiteRT's catch-all cannot silently claim an `.onnx` file — and gates inside
`createModel` instead. The error therefore arrives at model creation, not at
registration.

## Memory

Phi-3.5-mini 3.8B int4 peaks around **3.74 GB RSS**. That needs a 6 GB+ phone;
below that the OS kills the app during load rather than reporting an error you
can catch.

Measured throughput: macOS M4 Pro ~54 tok/s, Pixel 8 Pro ~10.4 tok/s, Linux
~5.3-5.8 tok/s, Windows ~3.3 tok/s on CPU test VMs. Treat ONNX as the
portability option, not the fast one — `.litertlm` is faster where both run.

## No web

There is no web arm. Use `.task` through MediaPipe or `.litertlm` in the
browser.

## Native libraries

Fetched at build time from Microsoft's own GitHub releases by the package's
`hook/build.dart` (Native Assets), not from a repo tag. On iOS the ORT runtime
is statically linked into the GenAI framework, so there is one binary rather
than two.
