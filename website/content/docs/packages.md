---
title: Packages
description: The 1.0 modular architecture — a small core plus opt-in engine, embedding, and RAG packages.
image: https://fluttergemma.dev/images/og-image.png
---

As of **1.0**, the monolithic `flutter_gemma` plugin is split into a small
**core** package plus **opt-in** packages for each engine / backend. Your app
ships only the native weight it actually uses. All packages live in one monorepo
(a Dart pub workspace) and the opt-in packages depend on core one-directionally.

## The six packages

| Package | What it does | Platforms |
|---|---|---|
| **`flutter_gemma`** | Core — registry, contracts, model management, sessions, chat. No engine on its own. **Always required.** | All |
| **`flutter_gemma_litertlm`** | `.litertlm` inference via `dart:ffi` (LiteRT-LM C API). Owns the shared native library. | Mobile + Desktop + Web |
| **`flutter_gemma_mediapipe`** | `.task` / `.bin` inference via MediaPipe. | Mobile + Web |
| **`flutter_gemma_embeddings`** | Text embeddings (EmbeddingGemma / Gecko) via LiteRT C API. | All |
| **`flutter_gemma_rag_qdrant`** | On-device RAG vector store (qdrant-edge, native Rust FFI). | Native (no Web) |
| **`flutter_gemma_rag_sqlite`** | On-device RAG vector store (wa-sqlite on Web; sqlite3 on native). | Web + native |

## How it works

- **Core registers no engine by itself.** You wire the packages you added through
  `FlutterGemma.initialize(inferenceEngines:, embeddingBackends:, vectorStore:)`.
  See [Installation](/docs/installation).
- **Probe-chain registry.** Engines and backends are pure factories that declare
  `canHandle(spec)` + a priority. The registry selects a provider per model by
  file type — `.task` / `.bin` / `.tflite` → MediaPipe, `.litertlm` → LiteRT-LM.
- **One app can run both formats.** Register both `LiteRtLmEngine()` and
  `MediaPipeEngine()`, and the registry routes each model to the engine that
  handles its extension.
- **Shared native library.** `flutter_gemma_litertlm` and
  `flutter_gemma_embeddings` share one native LiteRT library, fetched at build
  time via each package's Native-Assets hook (no manual download/bundling).

## Choosing packages

| You want to… | Add |
|---|---|
| Run `.litertlm` models (Gemma 4, Qwen3, FastVLM, + all desktop) | `flutter_gemma_litertlm` |
| Run `.task` / `.bin` models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) | `flutter_gemma_mediapipe` |
| Generate text embeddings | `flutter_gemma_embeddings` |
| On-device RAG on native (Android/iOS/desktop) | `flutter_gemma_rag_qdrant` |
| On-device RAG on web | `flutter_gemma_rag_sqlite` |

<Info>
Desktop is served exclusively by `flutter_gemma_litertlm` and uses LiteRT-LM
format only. There is no MediaPipe engine on desktop. See
[Desktop Support](/docs/desktop).
</Info>

Migrating from the 0.16.x monolith is just adding these packages plus one
`initialize(...)` call — every model / session / chat / embedding / RAG API is
unchanged. See [Migration (0.x → 1.0)](/docs/migration).
