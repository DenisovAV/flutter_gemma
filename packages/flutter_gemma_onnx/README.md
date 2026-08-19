# flutter_gemma_onnx

ONNX Runtime engines for [flutter_gemma](https://pub.dev/packages/flutter_gemma):
**text generation** via ORT-GenAI (`OnnxEngine`) and **embeddings** via plain
ONNX Runtime (`OnnxEmbeddingBackend`). Both are pure `dart:ffi` — no JVM, no
gRPC — and both drive the native library from a long-lived worker isolate so
no FFI pointer ever has to cross an isolate boundary.

## Register

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';

await FlutterGemma.initialize(
  inferenceEngines: [OnnxEngine()],
  embeddingBackends: [OnnxEmbeddingBackend()],
);
```

Either arm can be registered on its own — they don't depend on each other.

## Platform matrix (v1)

| Platform | Native archives | `OnnxEngine`/`OnnxEmbeddingBackend` enabled |
|---|---|---|
| macOS (Apple Silicon) | ✅ bundled | ✅ |
| macOS (Intel) | ❌ | ❌ |
| Linux x64 | ✅ bundled | ⏳ device throughput gate |
| Windows x64 | ✅ bundled | ⏳ device throughput gate |
| Android | ❌ not yet (AAR extraction pending) | ⏳ device throughput/RAM gate |
| iOS | ❌ not yet | ⏳ device throughput/RAM gate |
| Web | ❌ never (no WASM build of ORT-GenAI or ORT) | ❌ never |

`OnnxEngine.canHandle`/`OnnxEmbeddingBackend.createModel` are **hard-gated
to macOS arm64 today, independent of which native archives are bundled** —
Linux and Windows archives are fetched by `hook/build.dart` (checksum-verified
from Microsoft's own GitHub releases) so the FFI layer can be exercised on
real hardware for the device throughput/RAM go/no-go measurement, but the
public engine won't select itself there until that measurement passes and
the gate is deliberately widened. On an unsupported host `OnnxEngine`
politely declines (logs why, lets another registered engine — or core's own
"no engine can handle this" error — take over) instead of dlopen-ing a
library the app may or may not have bundled. `OnnxEmbeddingBackend.canHandle`
stays extension-based on every platform for a different reason (so a
catch-all embedding backend like `LiteRtEmbeddingBackend` never silently
claims an `.onnx`/`.ort` file); its platform gate lives in `createModel`
instead, as a loud `StateError`.

Android's archive is a differently-shaped AAR (per-ABI `.so` under `jni/`,
plus manifest/jar noise) rather than a flat tarball — extracting it is left
for whoever runs the Android go/no-go gate. iOS is blocked on the same
device measurement.

## Inference — `OnnxEngine`

Text-only, greedy decoding, one session at a time (v1). No vision, no audio,
no LoRA. Models install as `ModelFileType.onnx` and use ORT-GenAI's own chat
template (`OgaTokenizerApplyChatTemplate`) — the engine never builds turn
markers itself.

### Model layout: a directory, not a file

An ORT-GenAI model is a **directory**, not a single file:

```
my-model/
├── genai_config.json
├── model.onnx (+ model.onnx_data for the external-weights case)
└── tokenizer files (tokenizer.json, tokenizer_config.json, …)
```

`FlutterGemma.installModel()` currently downloads and tracks exactly one
file per spec. `OnnxEngine.createModel` takes that tracked file's **parent
directory** as the model directory, so v1 only works when the whole bundle
already lives alongside it on disk (e.g. a directory you ship as an asset or
pre-populate yourself) — not yet a real multi-file network install. Pointing
`modelPath` at a directory missing `genai_config.json` fails loudly with a
`StateError` naming the gap, rather than a confusing native error. Wiring a
real multi-file bundle install (mirroring the TTS package's `artifactPaths`
pattern) is a known follow-on.

### `ORT_LIB_PATH` — you don't need to configure anything

ORT-GenAI resolves the plain ONNX Runtime library at its own native
`InitApi()` time via a **bare-name `dlopen("libonnxruntime.dylib")`**, with a
`dladdr`-based "look next to my own binary" fallback. Under Flutter's Native
Assets `.framework` wrapping, `onnxruntime` and `onnxruntime-genai` land in
two *separate* `.framework` bundles, so that fallback can't find it. Before
opening the GenAI library, `GenAiFfiClient` `dladdr`-resolves the already-open
ORT library's real on-disk path and exports it as the `ORT_LIB_PATH`
environment variable — GenAI's own sanctioned override, checked first inside
`InitApi()`. This needs no Podfile step, no packaging change, no app-level
configuration; it just works.

For host tests / local dev, `FLUTTER_GEMMA_ORT_GENAI_LIBS` (a directory
containing both platform-default-named dylibs) bypasses the CodeAsset bundle
entirely — see `test/onnx_generation_host_smoke_test.dart`.

## Embeddings — `OnnxEmbeddingBackend`

A plain ONNX Runtime forward pass (no ORT-GenAI, no text generation) over an
`.onnx`/`.ort` embedding model directory. One factory handles both:

- **WordPiece / BERT-style** models (e.g. all-MiniLM-L6-v2) — `tokenLevel`
  output contract, mean-pooled + normalized client-side.
- **SentencePiece** models (e.g. EmbeddingGemma-300M-ONNX) — `pooledFinal`
  output contract (the model's own `sentence_embedding` output).

The output contract and mask/`token_type_ids` requirements are discovered
from the session's actual graph once it opens — no per-model configuration
needed. Priority 10 (above `LiteRtEmbeddingBackend`'s catch-all priority 0),
so registering both and installing an `.onnx`/`.ort` model routes here.

For host tests / local dev, `FLUTTER_GEMMA_ORT_LIBRARY` overrides the
resolved ORT library path directly (mirrors the inference arm's
`FLUTTER_GEMMA_ORT_GENAI_LIBS`).

## What v1 does not do

- No vision, no audio, no multimodal input on the inference arm — text only.
- No LoRA.
- Greedy decoding only (no sampling parameters exposed yet).
- One inference session at a time (`createSession` closes any live session
  before opening a new one, same as every other engine in this monorepo).
- No web build — ORT-GenAI and ORT ship no WASM target.

## See also

- [`flutter_gemma`](https://pub.dev/packages/flutter_gemma) — the core
  package this engine plugs into.
- [`flutter_gemma_litertlm`](https://pub.dev/packages/flutter_gemma_litertlm) /
  [`flutter_gemma_embeddings`](https://pub.dev/packages/flutter_gemma_embeddings) —
  the LiteRT-LM equivalents, with broader platform support today.
