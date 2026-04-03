## 0.13.0
- **Gemma 4 E2B/E4B**: Added support for next-gen multimodal models (text + image + audio)
- **systemInstruction**: New parameter in `createChat()` and `createSession()` for setting system-level context
- **ModelFileType.litertlm**: New file type to properly handle `.litertlm` models across platforms
- **iOS LiteRT-LM support**: `.litertlm` models now work on iOS
- **stopGeneration on iOS**: Supported for `.litertlm` models
- **MediaPipe GenAI 0.10.33**: Updated iOS (from 0.10.24) and Android (from 0.10.29)
  - iOS: GPU backend selection via `preferredBackend` (Metal delegate now activated)
  - iOS: Audio modality support (`addAudio` + `enableAudioModality`)
  - Android: Unified inference engine (CPU-only path removed), improved error handling
  - Web: Updated to 0.10.27
- **Example WASM compatibility**: Replaced direct `dart:io` imports with conditional imports for WASM compilation support
- **Benchmark integration test**: `example/integration_test/benchmark_comparison_test.dart` for comparing model performance on device

## 0.12.8
- **ToolChoice enum**: `auto` / `required` / `none` parameter in `createChat()` to control tool calling behavior
- **Parallel Tool Calls**: `ParallelFunctionCallResponse` for multiple function calls in one response
- **Strategy Pattern Parser**: Per-model `FunctionCallFormat` implementations (Gemma, Qwen, DeepSeek, Llama, Phi, FunctionGemma)
- **`<tool_call>` Format**: Qwen/Mistral-style function call parsing
- **ModelType.phi**: Dedicated model type for Phi-4 with `<|tool_calls|>` format support
- **NPU Fix**: Pass `nativeLibraryDir` to LiteRT-LM `Backend.NPU()`
- **Embeddings**: Models return L2-normalized vectors (dot product = cosine similarity)
- **Windows/Linux Embeddings Fix**: TFLite C library now correctly copied to build output (#200)

## 0.12.7
- **Dual-Prefix Embeddings (TaskType)**: Improved RAG retrieval quality with query/document prefixes
  - `TaskType.retrievalQuery` (default) — for search queries
  - `TaskType.retrievalDocument` — for document indexing
  - Follows Google RAG SDK convention (`EmbedData.TaskType`)
  - All platforms: Android, iOS, Web, Desktop
  - `addDocument()` automatically uses document prefix
- **Desktop Embeddings**: Run `.tflite` embedding models (EmbeddingGemma, Gecko) on macOS, Windows, Linux
  - LiteRT C API via `dart:ffi` — no gRPC, no JVM overhead
  - Pure Dart tokenizer via `dart_sentencepiece_tokenizer` (BPE + Unigram, auto-detect format)
  - LiteRT C library built from google-ai-edge/LiteRT v2.1.3
  - XNNPACK delegate with default options (QS8/QU8 quantization support)
  - Desktop scores match Android/Python exactly (cosine similarity 0.708)
  - CI workflow for building LiteRT C library on all 4 platform/arch combinations
- **Unified VectorStore**: Single Dart implementation using `sqlite3` dart:ffi replacing platform-specific code
- **Test Migration**: Removed `patrol` dependency, migrated all integration tests to standard `integration_test`

## 0.12.6
- **LiteRT-LM 0.9.0-beta**: Updated from 0.9.0-alpha02 on Android and Desktop (JVM)
  - Breaking API change: Backend enum to Backend factory constructors
- **Cancel Generation**: Implemented on Android, Desktop, and Web
  - Android LiteRT-LM: `Conversation.cancelProcess()`
  - Desktop: gRPC `CancelGeneration` RPC
  - Web: `LlmInference.cancelProcessing()` (MediaPipe 0.10.26)
- **MediaPipe Web 0.10.26**: Pinned CDN version (was @latest)
- **E2E Integration Tests**: Full inference test suite
  - Parameterized tests for both MediaPipe and LiteRT-LM engines
  - Multimodal tests: vision (Android, iOS, Web, Desktop) + audio (Android, Desktop)
  - Cancel, lifecycle, dual-engine tests

## 0.12.5
- **iOS Tokenizer Rewrite**: Replaced SentencePiece C++ with pure Swift tokenizers (BPE + Unigram)
  - Eliminates protobuf symbol conflict between SentencePiece and TensorFlow Lite (#184)
  - Auto-detects tokenizer type from `model.type` field in tokenizer.json
  - Supports both EmbeddingGemma (BPE) and Gecko (Unigram) models
- **HNSW Vector Search**: O(log n) approximate nearest neighbor search for VectorStore
  - Cross-platform: Android (Kotlin), iOS (Swift), Web (JavaScript)
  - Configurable M and efConstruction parameters
  - Falls back to brute-force for small datasets
- **iOS Embeddings**: `iosPath` parameter for platform-aware tokenizer downloads
  - Pre-converted tokenizer.json files on CDN (no SentencePiece dependency on iOS)
- **Desktop JAR Fix**: Updated `litertlm-server.jar` URL to v0.12.5 (#189)
- **Bug Fixes**:
  - Fixed iOS embedder crash due to protobuf symbol conflict (#184)
  - Removed deprecated `package` attribute from AndroidManifest.xml

## 0.12.4
- **Android ProGuard Fix**: Added ProGuard rules for LiteRT-LM classes (#185)

## 0.12.3
- **Android LiteRT-LM Engine**: Added LiteRT-LM inference engine for Android
  - Automatic engine selection based on file extension (`.litertlm` → LiteRT-LM, `.task/.bin` → MediaPipe)
  - NPU acceleration support (Qualcomm, MediaTek, Google Tensor)
- **Audio Input Support**: Audio input for Gemma 3n models via LiteRT-LM
  - Platforms: Android + Desktop (macOS, Windows, Linux)
  - WAV format (16kHz, mono, 16-bit PCM)
  - `supportAudio` parameter in session configuration
- **Desktop LiteRT-LM Fixes**: Fixed text chat and audio on desktop platforms
  - Switched from Flow-based to Callback-based async API (matches Android)
  - Audio transcription now works correctly
- **Bug Fixes**:
  - Fixed model deletion not removing metadata
  - Fixed model creation failure blocking switching to another model
  - Fixed download issues for large models

## 0.12.2
- **Model Deletion Fix**: Fixed model deletion not removing metadata (#169)
- **Model Switch Fix**: Fixed model creation failure blocking switching to another model (#170)
- **Android SDK**: Updated to API 36

## 0.12.1
- **Web Large Model Support**: `WebStorageMode` for models >2GB via OPFS streaming (#162)
- **Desktop JAR Checksum Fix**: Fixed JAR checksum mismatch in setup scripts (#167)

## 0.12.0
- 🖥️ **Desktop Support**: Full support for macOS, Windows, and Linux platforms
  - **macOS**: Apple Silicon (M1/M2/M3/M4) with Metal GPU acceleration
  - **Windows**: x86_64 with DirectX 12 GPU acceleration
  - **Linux**: x86_64 and ARM64 with Vulkan GPU acceleration
- 🏗️ **LiteRT-LM Architecture**: Desktop uses gRPC server with bundled JRE for inference
  - Automatic JRE 21 download and native library extraction
  - Dynamic port allocation prevents conflicts
  - Supports `.litertlm` model format only (MediaPipe `.task`/`.bin` not supported on desktop)
- 📚 **Desktop Documentation**: Comprehensive setup guide in DESKTOP_SUPPORT.md

## 0.11.16
- 🐛 **iOS Embeddings Fix**: Fix crash on repeated embedding inference (#155)

## 0.11.15
- 🤖 **FunctionGemma Single-Turn Mode**: FunctionGemma now operates in single-turn mode by design (clears history after each response)
- 🐛 **Download Resume Fix**: Fixed model download resume after interruption

## 0.11.14
- 🤖 **FunctionGemma Support**: Added `ModelType.functionGemma` for Google's specialized function calling model
  - Pre-converted models available on HuggingFace
  - Fine-tuning Colab notebooks (3-step pipeline)
- 🐛 **Batch Embeddings Fix**: Fixed type cast issue in platform channel for batch embeddings (#142)

## 0.11.13
 - ✅ **iOS Embeddings Fix**: XNNPACK + SentencePiece integration for better results on iOS
 - 🌐 **Web CDN**: Modules available via jsDelivr (`@0.11.13/web/*.js`)

## 0.11.12
 - 🌐 **Web VectorStore**: Full RAG support on web with SQLite WASM
   - Uses wa-sqlite with OPFS storage (10x faster than IndexedDB)
   - Cross-platform parity: Android, iOS, and Web now all support VectorStore
 - 🐛 **Android 16KB Page Size Fix**: Updated `tasks-vision-image-generator` to 0.10.26.1 for Android 15+ compatibility
 - ⬆️ **Kotlin Update**: Upgraded to Kotlin 2.1.0 in example app

## 0.11.11
 - 🐛 **Mobile Build Fix**: Fixed compilation errors on iOS/Android platforms

## 0.11.10
 - 💾 **Web Persistent Caching**: Models now persist across browser restarts using Cache API
 - ⚠️ **BREAKING CHANGE**: Explicit initialization now required
   - **ACTION REQUIRED**: Add `await FlutterGemma.initialize()` in `main()` before using the plugin

## 0.11.9
 - 🌐 **Web Embedding Support**: Added support for embedding generation on web platform
 - 🐛 **Web Example App**: Fixed bugs in example app on web platform

## 0.11.8
 - 🤖 **CI/CD Automation**: Added GitHub Actions workflows for automated testing and release builds
 - ☕ **Support the Project**: Added Ko-fi donation button for community support

## 0.11.7
 - 🚀 **VectorStore Optimization** ⚠️ **BREAKING (RAG only)**:
   - **71% smaller storage**: Binary BLOB format instead of JSON (3 KB vs 10.5 KB per 768D embedding)
   - **6.7x faster reads**: ~75 μs vs ~500 μs per document search
   - **3.3x faster writes**: ~45 μs vs ~150 μs per document insertion
   - **Dynamic dimensions**: Auto-detect any embedding size (256D, 384D, 512D, 768D, 1024D, 1536D, 3072D, 4096D+)
   - **iOS implementation**: Full VectorStore support on iOS (was stubs only)
   - **Cross-platform parity**: Identical behavior on Android and iOS
   - ⚠️ **ACTION REQUIRED**: Existing vector databases will be recreated on upgrade (re-index required)

## 0.11.6
 - 🐛 **iOS Simulator Fix**: Fixed "Filename cannot contain path separators" crash on iOS Simulator (#127)
 - 🔧 **Download Service Refactoring**: Unified download implementation, removed legacy code (~100 lines)
 - 🚫 **Download Cancellation**: Added CancelToken pattern (Dio-style) for cancelling downloads (NON-BREAKING)
 - 🧹 **API Cleanup** ⚠️ **BREAKING**: Removed unused `canResume()`, `resume()`, `cancel()` methods from DownloadService interface

## 0.11.5
 - 🐛 Fixes: Some fixes for new Modern API
 - ⚠️ Deprecated: Marked legacy asset/file management methods as deprecated with migration hints
 - 📚 Documentation: Updated README with Modern API examples and complete parameter documentation

## 0.11.4
- **New**: Fluent builder API with `FlutterGemma.installModel().fromNetwork/fromAsset/fromBundled/fromFile()`
- **Architecture**: Sealed classes for type-safe sources, dependency injection via ServiceRegistry, platform-specific handlers
- **Bundled Models**: Support for including small models in production builds via native bundles (iOS: Bundle.main, Android: assets)
- **Backward Compatible**: Legacy API (`modelManager.downloadModelWithProgress()`) still works as facade

## 0.11.3
- 🌐 **Web Multimodal Support**: Added full multimodal image processing support for web platform
- 📚 **MediaPipe 0.10.25**: Updated to MediaPipe GenAI v0.10.25 for web compatibility
- 📦 **LiterTLM Format Support**: Added support for `.litertlm` model files optimized for web platform

## 0.11.2
- 🛡️ **Fixed**: Updated ProGuard rules for Android release build compatibility

## 0.11.1
- 🐛 **Fixed**: Export missing ModelType and other public API types to resolve import issues

## 0.11.0
- 🚀 **Embedding Models Support**: Added full support for text embedding models
- 🔧 **Unified Model System**: All models (inference and embedding) now use the same download and management pipeline
- 📝 **ModelSpec Architecture**: Introduced `InferenceModelSpec` and `EmbeddingModelSpec` for better model organization
- 🛡️ **Smart Cleanup System**: Added automatic cleanup of orphaned files with resume detection capabilities
- 🔄 **Model Replace Policies**: Separate policies for model downloading `replace` and `keep`
- 📱 **Example App Integration**: Added embedding models download screen and embeddings generation demo screen

## 0.10.6
- 🔧 **Model Replace Policy**: Added configurable model replacement system with keep/replace options and `ensureModelReady()` method
- 📥 **Enhanced Downloads**: Added HuggingFace CDN ETag issue handler with smart retry logic and exponential backoff
- 🔄 **Download Reliability**: New `HuggingFaceDownloader` wrapper to handle CDN server inconsistencies and resume failures
- 📁 **ModelFileType System**: Introduced distinction between `.task` files (MediaPipe-handled) and `.bin/.tflite` files (manual formatting)
- 🔐 **Android Security**: Added network security configuration for HuggingFace CDN access with proper permissions
- 🐛 **Download Fixes**: Fixed Android download timeouts, stream management, and ETag mismatch issues
- 🖼️ **Image Corruption Fix**: Added comprehensive image processing system to prevent AI model corruption on Android
- 🔄 **Example App**: Added sync/async response method selection in chat interface

## 0.10.5
- 🛑 **Stop Generation**: Added Android support for stopping text generation mid-process with `session.cancelRequestGenerationAsync()` (#89, #19, #34)
- 🐛 **Screen Close Fix**: Fixed crash when closing screen during active generation by implementing proper StreamSubscription cleanup (#89)  
- 🐛 **Model Loading Fix**: Fixed model install check with partial downloads by adding orphaned files cleanup (#84)
- 🗑️ **File Management**: Added automatic cleanup of corrupted/incomplete model files with atomic SharedPrefs updates
- 📱 **iOS Requirements**: Updated deployment target to 16.0 for MediaPipe GenAI compatibility
- 🔧 **Error Handling**: Improved error recovery with automatic file cleanup on failed downloads
- 📚 **Documentation**: Updated model capabilities table and comprehensive usage examples

## 0.10.4
- 📚 **Documentation**: Updated README with comprehensive model information and usage examples

## 0.10.3
- 📥 **Background Downloads**: Added background download support for model files

## 0.10.2
- 🚀 **New Models**: Added support for 4 new compact models:
  - [Gemma 3 270M](https://huggingface.co/litert-community/gemma-3-270m-it) - Ultra-compact text-only model (0.3GB)
  - [TinyLlama 1.1B](https://huggingface.co/litert-community/TinyLlama-1.1B-Chat-v1.0) - Lightweight chat model (1.2GB)
  - [Hammer 2.1 0.5B](https://huggingface.co/litert-community/Hammer2.1-0.5b) - Action model with strong function calling (0.5GB)
  - [Llama 3.2 1B](https://huggingface.co/litert-community/Llama-3.2-1B-Instruct) - Instruction-tuned model (1.1GB)
- ⚙️ **Backend Switching**: Added individual CPU/GPU backend switcher for each model in the example app
- 🔍 **Advanced Model Filtering**: Added expandable filter section with feature-based filtering:
  - Filter by Multimodal support (vision capabilities)
  - Filter by Function Calling support 
  - Filter by Thinking Mode support
  - Animated expandable UI with clear visual indicators
- 📊 **Model Sorting**: Added comprehensive sorting options:
  - Sort alphabetically (A-Z)
  - Sort by model size (smallest to largest)
  - Default order (Gemma models prioritized)
- 📏 **Improved Model Display**: Separated size information from model names for cleaner presentation
- 🌐 **Full English Localization**: Converted all UI text from Russian to English
- 📊 **Results Counter**: Added dynamic counter showing filtered results ("Showing X models")
- 🎨 **Enhanced Filter UI**: FilterChip components with color-coded selections matching feature badges
- 🎯 **Model Organization**: Reorganized model list with Gemma models prioritized at the top
- 🛠️ **Function Calling**: Enhanced function calling support with Hammer 2.1 action model
- 📱 **UI Improvements**: New card-based design with individual backend controls per model
- ✅ **Model Capabilities**: Fixed and verified multimodal support flags for all models
- 📚 **Documentation**: Updated README and model feature support table with new models

## 0.10.1
- 🧠 **Thinking Mode**: Added thinking mode support for DeepSeek models with persistent thinking bubbles
- 🔧 **Function Call Fixes**: Fixed function calls detection in the middle of responses
- 💬 **UI Improvements**: Fixed loading indicator display after function calls
- 🔄 **JSON Response Handling**: Enhanced handling of JSON responses after function execution
- 📚 **Documentation**: Updated README with latest API changes and improved examples
- 🎨 **Code Quality**: Removed Russian comments and improved code consistency

## 0.10.0
- ✨ **Function Calling**: Added support for function calling, allowing models to interact with external tools.
- 🔧 **Improved Chat API**: Enhanced the chat API to support function calls and tool responses.

## 0.9.0
- 🖼️ **MULTIMODAL SUPPORT**: Added full support for text + image input with Gemma 3 Nano vision models
- 🎯 **Enhanced Message API**: New `Message` class with support for text, image, and multimodal content
    - `Message.text()` - for text-only messages
    - `Message.withImage()` - for text + image messages
    - `Message.imageOnly()` - for image-only messages
    - `message.hasImage` - to check if message contains image
- 📱 **Vision Models**: Full support for Gemma 3n E2B and E4B models with image understanding
- 🌐 **Web Platform**: Added graceful degradation with debug warnings for unsupported features

## 0.8.6
- 🚀 **GEMMA 3 NANO SUPPORT**: Added full support for Gemma 3 Nano models
- ⚡ Optimized session parameters for Gemma 3n models (temperature: 0.6, topK: 40, topP: 0.9)
- 🛡️ Added automatic fallback session creation for `input_pos != nullptr` errors
- 🎯 Added Gemma 3n model detection and compatibility handling
- 💪 Enhanced error handling for TensorFlow Lite model initialization
- 🔧 Fixed iOS session initialization with proper input position handling
- 📱 Improved mobile inference model with optimized parameters
## 0.8.5
- Upgraded Mediapipe to 0.10.24 for iOS and Android
- Added support of **Gemma3**, **Phi-4** and **DeepSeek** models for iOS
## 0.8.4
- iOS LoRA support added
- iOS topP support added
## 0.8.3
- Readme updated
## 0.8.2
- Readme updated
## 0.8.1
- Migrate to js-interop
- Add web platform support in pubspec.yaml
## 0.8.0
- Upgraded Mediapipe to 0.10.22 for Android and Web
- Upgraded Mediapipe to 0.10.21 for iOS
- Added opportunity to set *topP* and *preferredBackend* for inference
- Added support of **Gemma3**, **Phi-4** and **DeepSeek** models for Android and Web
## 0.7.0
- Added Chat functionality for instruction tuned model
- Added sizeInTokens method for analysis of the size of the input prompt
## 0.6.0
- Added opportunity to manage inference session
## 0.5.1
- Fixed crash on generation for Android
## 0.5.0
- IMPORTANT: Breaking changes in the API
- FlutterGemma instance was replaced with ModelManager and InferenceModel
- ModelManager to manage models and LoRA weights
- InferenceModel to manage inference
- Added opportunity to set model and LoRA weights paths manually
- Added opportunity to delete model and LoRA weights
- Added opportunity to load LoRA weights from assets and network
## 0.4.6
- Added close method
## 0.4.5
- Small fixes for Android
## 0.4.4
- Small fixes for iOS
## 0.4.3
- Upgraded Mediapipe to 0.10.20
- Updated LoRA support
## 0.4.2
- Added error handling
- Updated example for error handling
- Upgraded Mediapipe to 0.10.18 for iOS
- Fixed ios issue with model freezing
## 0.4.1
- Fixed ios issue
## 0.4.0
- Upgraded Mediapipe to 0.10.16
- Added LoRA support
- Fixed some issues
## 0.3.1
- Updated example and readme
## 0.3.0
- Added support for loading models from assets and network.
- Added progress updates for model loading.
## 0.2.4
- Fixed Mediapipe ios version
## 0.2.3
- Updated Mediapipe ios version
## 0.2.2
- Added opportunity to configure folder (Android only)
- Fixed android release issue
- Updated Mediapipe for Android
- Updated readme
## 0.2.1
- Updated chat functionality for instruction tuned model
- Updated readme
## 0.2.0
- Added chat functionality for instruction tuned model
- Updated example
## 0.1.4
- Updated readme for GPU models on Android devices
- Updated example
## 0.1.3
- Updated readme
## 0.1.2
- Updated example
## 0.1.1
- Updated example
## 0.1.0
- Added web support
- Added opportunity to set *randomSeed*, *topK* and temperature
## 0.0.4
- Updated example
- Updated readme
## 0.0.3
- Added getResponseAsync method
## 0.0.2
- Added description in Readme.md
- Added opportunity to setup a model before initiation
## 0.0.1
- Initial release
































