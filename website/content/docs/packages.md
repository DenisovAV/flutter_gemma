---
title: Packages
description: The 1.0 modular architecture — a small core plus opt-in engine, embedding, and RAG packages.
image: https://fluttergemma.dev/images/og-image.png
---

As of **1.0**, the monolithic `flutter_gemma` plugin is split into a small
**core** package plus **opt-in** packages for each engine / backend. Your app
ships only the native weight it actually uses. All packages live in one monorepo
(a Dart pub workspace) and the opt-in packages depend on core one-directionally.

## The packages

| Package | What it does | Platforms |
|---|---|---|
| **`flutter_gemma`** | Core — registry, contracts, model management, sessions, chat. No engine on its own. **Always required.** | All |
| **`flutter_gemma_litertlm`** | `.litertlm` inference via `dart:ffi` (LiteRT-LM C API). Owns the shared native library. | Mobile + Desktop + Web |
| **`flutter_gemma_mediapipe`** | `.task` / `.bin` inference via MediaPipe. | Mobile + Web |
| **`flutter_gemma_builtin_ai`** | System OS models — Gemini Nano (Android / AICore), Apple Foundation Models (iOS 26+/macOS), and Gemini Nano via the Chrome Prompt API (Web). No model file to bundle or download. | Android + iOS + macOS + Web |
| **`flutter_gemma_onnx`** | Text generation (`OnnxEngine`) + embeddings (`OnnxEmbeddingBackend`) — ORT-GenAI/ORT via `dart:ffi` on native, Transformers.js/onnxruntime-web on Web. | macOS, Linux, Windows, Android, iOS (arm64) + Web |
| **`flutter_gemma_embeddings`** | Runtime-agnostic text-embedding pipeline (tokenizer, pooling, isolate worker). Needs a backend — `LiteRtEmbeddingBackend` (`flutter_gemma_litertlm`) or `OnnxEmbeddingBackend` (`flutter_gemma_onnx`). | All |
| **`flutter_gemma_rag_qdrant`** | On-device RAG vector store (qdrant-edge, native Rust FFI). Fastest on native. | Native (no Web) |
| **`flutter_gemma_rag_sqlite`** | On-device RAG vector store — in-SQLite KNN via the `sqlite-vec` (`vec0`) extension. Exact + portable. | All (incl. Web) |
| **`flutter_gemma_agent`** | On-device [agent skills](/docs/agent) — SKILL.md catalog + tool-calling loop (text / JS / native-intent / MCP). | Native, no Web (JS skills: no Linux) |
| **`flutter_gemma_speech`** | On-device [speech](/docs/speech) — speech-to-text + text-to-speech + a `VoiceSession` voice loop (moonshine/Whisper/Parakeet STT + Matcha/Qwen3/Inflect TTS) via the LiteRT C API + `dart:ffi`. | Native (no Web) |

## How it works

- **Core registers no engine by itself.** You wire the packages you added through
  `FlutterGemma.initialize(inferenceEngines:, embeddingBackends:, vectorStore:)`.
  See [Installation](/docs/installation).
- **Probe-chain registry.** Engines and backends are pure factories that declare
  `canHandle(spec)` + a priority. The registry selects a provider per model by
  file type — `.task` / `.bin` / `.tflite` → MediaPipe, `.litertlm` → LiteRT-LM,
  `.onnx` → Onnx, `builtIn` → BuiltInAi.
- **One app can run both formats.** Register both `LiteRtLmEngine()` and
  `MediaPipeEngine()`, and the registry routes each model to the engine that
  handles its extension.
- **Shared native library.** `flutter_gemma_litertlm` owns the native LiteRT
  library (fetched at build time via its Native-Assets hook); `flutter_gemma_embeddings`
  and `flutter_gemma_speech` have no hook of their own and consume that bundle
  transitively. `flutter_gemma_onnx` owns its own separate ORT / ORT-GenAI
  native archives.

## Choosing packages

| You want to… | Add |
|---|---|
| Run `.litertlm` models (Gemma 4, Qwen3, FastVLM, + all desktop) | `flutter_gemma_litertlm` |
| Run `.task` / `.bin` models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) | `flutter_gemma_mediapipe` |
| Run the OS system model with no download (Gemini Nano / Apple Foundation Models) | `flutter_gemma_builtin_ai` |
| Run ONNX models — ORT-GenAI (native) or Transformers.js (Web) | `flutter_gemma_onnx` |
| Generate text embeddings | `flutter_gemma_embeddings` + `flutter_gemma_litertlm` (`LiteRtEmbeddingBackend`) |
| Generate text embeddings from ONNX/ORT models | `flutter_gemma_embeddings` + `flutter_gemma_onnx` (`OnnxEmbeddingBackend`) |
| On-device RAG on native, fastest (Android/iOS/desktop) | `flutter_gemma_rag_qdrant` |
| On-device RAG on web, or a portable/exact store on any platform | `flutter_gemma_rag_sqlite` |
| On-device agent skills the model runs itself (text / JS / native-intent / MCP) | `flutter_gemma_agent` |
| Transcribe audio, synthesize speech, or run a voice loop on-device (STT + TTS + voice) | `flutter_gemma_speech` |

<Info>
Desktop is served **primarily** by [`flutter_gemma_litertlm`](/docs/litertlm)
(`.litertlm`) — the default engine. [`flutter_gemma_onnx`](/docs/onnx) also runs
on all three desktop OSes (macOS/Windows/Linux), and on **macOS** the OS built-in
model is available via [`flutter_gemma_builtin_ai`](/docs/builtin-ai) (Apple
Foundation Models, macOS only). There is no MediaPipe engine on desktop. See
[Desktop Support](/docs/desktop).
</Info>

Migrating from the 0.16.x monolith is just adding these packages plus one
`initialize(...)` call — every model / session / chat / embedding / RAG API is
unchanged. See [Migration (0.x → 1.0)](/docs/migration).

## ONNX Runtime engine

`flutter_gemma_onnx` adds a second inference/embedding stack alongside
LiteRT-LM and MediaPipe: **ONNX Runtime** — `dart:ffi` on native (no JVM, no
gRPC), Transformers.js / onnxruntime-web on Web. Two independent arms, either
can be registered on its own:

- **`OnnxEngine`** — text generation via [ORT-GenAI](https://github.com/microsoft/onnxruntime-genai)
  on native, [Transformers.js](https://huggingface.co/docs/transformers.js) on
  Web. Text-only, greedy decoding, one session at a time in v1 — no vision, no
  audio, no LoRA yet.
- **`OnnxEmbeddingBackend`** — embeddings via plain ONNX Runtime
  (WordPiece/BERT-style and SentencePiece models) on native, onnxruntime-web
  on Web, priority 10 over `LiteRtEmbeddingBackend`'s catch-all priority 0.

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_onnx/flutter_gemma_onnx.dart';

await FlutterGemma.initialize(
  inferenceEngines: [OnnxEngine()],
  embeddingBackends: [OnnxEmbeddingBackend()],
);
```

**Platform support:** device-verified via `dart:ffi` on macOS (Apple Silicon),
Linux x64, Windows x64, Android (arm64), and iOS (arm64). On **Web**,
`OnnxEngine` runs generation through Transformers.js v4 and
`OnnxEmbeddingBackend` runs through onnxruntime-web (WebGPU/WASM) — same
public API as native, no `if (kIsWeb)` needed in app code.

<Info>
On native, an ORT-GenAI model installs as a **directory**, not a single file:
`genai_config.json` + `model.onnx` (+ `model.onnx_data` for external weights)
+ tokenizer files. `ModelFileType.onnx` models need the whole bundle on disk
alongside the tracked file (e.g. shipped as an asset) — a real multi-file
network install is a follow-on. On **Web** this doesn't apply — the model is a
Hugging Face repo id (e.g. `onnx-community/Qwen2.5-0.5B-Instruct`), not a
directory, and install is fileless: `ModelFileType.onnx` just marks it active,
and Transformers.js downloads and caches the repo itself.
</Info>

See the [`flutter_gemma_onnx` README](https://pub.dev/packages/flutter_gemma_onnx) for the full platform matrix and FFI details.

## Genkit integration

Two companion packages integrate flutter_gemma with [Genkit](https://pub.dev/packages/genkit), Google's framework for building AI features:

| Package | What it does | Depends on |
|---|---|---|
| **`genkit_flutter_gemma`** | Exposes flutter_gemma as a Genkit model/embedder provider — call `ai.generate(model: flutterGemma.model(...))` and `ai.embed(...)` through the standard Genkit API. | `flutter_gemma` + `genkit` |
| **`genkit_hybrid`** | Provider-agnostic hybrid routing: combine an on-device and a cloud model behind one routing policy, with correct streaming + before-first-token fallback. | `genkit` only (no flutter_gemma) |

See [Genkit](/docs/genkit) for setup and examples.
