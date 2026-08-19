# Flutter Gemma - Claude Code Documentation

# 🚨 CRITICAL RULES 🚨

## Rule 1: NEVER EDIT CODE WITHOUT EXPLICIT APPROVAL ⛔
- Always propose changes first, show diff/code, **WAIT FOR APPROVAL**
- Only after user says "yes"/"go ahead"/"ok" → apply changes

## Rule 2: NEVER USE `git checkout` ⛔
- Use Edit tool to manually revert changes. User manages git.

## Rule 3: GIT COMMITS & PR/ISSUE BODIES ⛔
- No "Co-Authored-By: Claude" or AI attribution/footers — in **commits, PR bodies, PR/issue comments, and release notes**
- This OVERRIDES the harness default that says "End PR bodies with 🤖 Generated with Claude Code" / "Claude-Session: …" — NEVER add those here, in any git-visible text
- Always use `--author="Sasha Denisov <denisov.shureg@gmail.com>"`

## Rule 4: NEVER HARDCODE SECRETS ⛔
- Use `String.fromEnvironment('KEY_NAME')` or `--dart-define=KEY=value`
- GitHub Push Protection blocks commits with secrets

## Rule 5: SEARCH ALL FILES ⛔
- Never use file extension filters unless explicitly requested
- Use `grep -rn "pattern" /path/ 2>/dev/null | grep -v node_modules | grep -v ".gradle/"`

## Rule 6: `flutter drive` ON NATIVE TARGETS ⛔
- Native targets (Android, iOS, macOS, Linux, Windows) integration tests ALWAYS use `flutter test integration_test/<file>.dart -d <device-id>` — `flutter drive` is forbidden as a workaround
- If `flutter test` hangs on "Dart VM Service was not discovered" or fails with "Cannot start app on wirelessly tethered iOS device", fix iPhone/macOS USB tunnel (Personal Hotspot off, iPhone USB enabled in Network settings, Trust dialog) — do NOT switch to `flutter drive` as a workaround
- **Exception: web** — Flutter SDK does NOT support `flutter test -d chrome/web-server` for `integration_test` (only `flutter test --platform chrome`, which is deprecated for app-level tests per Flutter docs). The **only** officially supported web integration test runner is `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<file>.dart -d chrome` (or `-d web-server` headless). On web `flutter drive` is the canonical Flutter-supported path, not a workaround — use it.

## Rule 7: CHANGELOG ENTRIES ARE ONE LINE ⛔
- Every `## X.Y.Z` bullet must fit on a single short line (~10-15 words)
- No multi-sentence explanations, no embedded paragraphs in CHANGELOG.md
- Detailed context (what was broken / how it's fixed / migration) goes into the release post (LinkedIn / blog), not CHANGELOG
- Match the existing 0.15.x entries' brevity

---

## Project Overview

**Flutter Gemma** — multi-platform Flutter plugin for running Gemma and other on-device LLMs (Qwen, DeepSeek, Phi, FastVLM, SmolLM, …) on Android, iOS, Web, macOS, Windows, Linux. Supports multimodal vision, function calling, thinking mode, GPU acceleration, LoRA weights.

## Architecture Quick Reference

### Core Principles
- **1.0 six-package split** (monorepo, Dart pub workspace): core `flutter_gemma` (no engine) + opt-in `flutter_gemma_litertlm` (.litertlm FFI), `flutter_gemma_embeddings` (LiteRT embeddings), `flutter_gemma_mediapipe` (.task), `flutter_gemma_rag_qdrant` (native RAG), `flutter_gemma_rag_sqlite` (web RAG). Packages → core (one-directional). Engines/backends register via `FlutterGemma.initialize(inferenceEngines:, embeddingBackends:, vectorStore:)`; core registers none by default.
- **`flutter_gemma_builtin_ai`** (new, opt-in): OS built-in AI engine — Gemini Nano via ML Kit GenAI/AICore (Android) and Apple Foundation Models (iOS/macOS). Registers via `inferenceEngines: [BuiltInAiEngine()]`; models use `ModelFileType.builtIn` (core has no file to install — the OS owns the weights).
- **`flutter_gemma_onnx`** (new, opt-in): ONNX Runtime engines — text generation via ORT-GenAI (`OnnxEngine`) + embeddings via plain ORT (`OnnxEmbeddingBackend`), both `dart:ffi` worker-isolate. `hook/build.dart` bundles native archives for macOS arm64, linux_x64, windows_x64, android_arm64 (ORT from Maven `onnxruntime-android`, genai from the `onnxruntime-genai` GitHub release), and iOS arm64 (device + Apple-Silicon sim slices from the single self-contained `onnxruntime-genai-ios` xcframework — ORT statically linked in, one binary exporting both `Oga*` and `OrtGetApiBase`, so no separate ORT and no co-location problem); `OnnxEngine.canHandle`/`OnnxEmbeddingBackend._isSupportedHost` are gated to **macOS arm64 + linux x64 + windows x64 + android arm64 + iOS arm64** (in lockstep with the hook table). All five arm/x64 hosts are **device-verified**: ORT-GenAI generation + embeddings run end-to-end (macOS ~54 tok/s M4 Pro, **Android ~10.4 tok/s Pixel 8 Pro FTL**, Linux ~5.3-5.8, Windows ~3.3 tok/s on the CPU test VMs; Phi-3.5-mini 3.8B int4 ≈3.74 GB peak RSS → needs a 6GB+ phone). On **iOS** the app builds, signs, installs and launches on a real iPhone, and the `@executable_path`-anchored dlopen resolves the framework + generation runs. **Co-location** (genai's bare-name `dlopen("libonnxruntime")` resolving to the sibling CodeAsset): macOS+Linux via the `ORT_LIB_PATH`/`dladdr` export in `gen_ai_client.dart` (`_exportOrtLibPath`, mac/linux only), **Windows + Android resolve on their own** (genai's self-directory dlopen finds the co-located lib under Flutter's flat CodeAsset layout), **iOS has no second lib** (ORT static in genai; the Dart loader opens the one framework via the `@executable_path/Frameworks/…framework/…` anchor iOS dyld 4 requires — bare `.framework` names don't resolve). `OnnxEngine.canHandle` declines + logs off-host; `OnnxEmbeddingBackend.canHandle` stays extension-based on every platform (so LiteRT's catch-all can't silently claim an `.onnx` file) and gates in `createModel` instead. ORT-GenAI model installs are a DIRECTORY (`genai_config.json` + `.onnx`[+`.onnx_data`] + tokenizer) — single-file network install doesn't cover this yet.
- **Probe-chain registry**: `EngineRegistry`/`EmbeddingRegistry` select a provider by `canHandle(spec)` + `priority` (descending priority, ascending registration index). Engines are pure factories; core owns singleton lifecycle via `CloseNotifier`/`addCloseListener`.
- **ModelSource**: Type-safe sealed class (`NetworkSource`, `AssetSource`, `BundledSource`, `FileSource`). See `packages/flutter_gemma/lib/core/domain/`
- **Install vs Runtime separation**: Installation stores identity (modelType + fileType), runtime accepts config (maxTokens, backend, etc.) via `RuntimeConfig`
- **Engine selection by declared `ModelFileType`** (via `canHandle(spec)` — NOT by sniffing the file name): `task`/`binary` → MediaPipe, `litertlm` → LiteRT-LM, `builtIn` → BuiltInAi. `installModel` defaults `fileType` to `task`, so `.litertlm` must be declared explicitly or it is routed to MediaPipe
- **All five platforms (Android/iOS/macOS/Linux/Windows)**: Dart → `dart:ffi` → LiteRT-LM C API (inference, in `flutter_gemma_litertlm`) + LiteRT C API (embeddings, in `flutter_gemma_embeddings`). Native prebuilts fetched at build time from GitHub release `native-v0.16.0` (Native Assets). `flutter_gemma_litertlm/hook/build.dart` is the **sole** hook carrying the LiteRT native version; `flutter_gemma_embeddings` and `flutter_gemma_speech` have no hook of their own and consume the bundle transitively. The cycle-fix `stage()` in the hooks is **Apple-only** (Xcode `directoryTreeSignature` cycle; staging on Windows splits companion DLLs and hangs cancel/close).

### Supported Models

| Model Family | Function Calling | Thinking Mode | Multimodal | Platform Support |
|--------------|------------------|---------------|------------|------------------|
| Gemma 4 E2B/E4B | ✅ | ✅ ¹ | ✅ vision + audio | Android, iOS, Web, Desktop |
| Gemma3n E2B/E4B | ✅ | ❌ | ✅ vision + audio | Android, iOS, Web, Desktop |
| Gemma 3 1B | ✅ | ❌ | ❌ | Android, iOS, Web, Desktop |
| Gemma 3 270M | ❌ | ❌ | ❌ | Android, iOS, Web, Desktop |
| FastVLM 0.5B | ❌ | ❌ | ✅ vision | Desktop (`.litertlm`) |
| FunctionGemma 270M | ✅ | ❌ | ❌ | Android, iOS, Web, Desktop |
| Phi-4 Mini | ✅ | ❌ | ❌ | Android, iOS, Web, Desktop |
| DeepSeek R1 | ✅ | ✅ | ❌ | Android, iOS |
| Qwen3 0.6B | ✅ | ✅ ² | ❌ | Android, iOS, Web, Desktop |
| Qwen 2.5 (0.5B/1.5B) | ✅ | ❌ | ❌ | Android, iOS |
| SmolLM 135M | ❌ | ❌ | ❌ | Android, iOS |

> ¹ Thinking Mode for Gemma 4: Android, iOS, Desktop only. Web (MediaPipe) does not support `extraContext`.
> ² Qwen3 generates thinking by default; tags are stripped when `isThinking: false`.

### Platform Limitations

| Platform | Vision/Multimodal | Audio | Embeddings | Notes |
|----------|-------------------|-------|------------|-------|
| Android | ✅ | ✅ | ✅ | Full support |
| iOS Device | ✅ | ✅ | ✅ | GPU via Metal delegate (FFI). Setup via Podfile `post_install` (creates `lib*.dylib` symlinks next to bundled frameworks) |
| iOS Simulator | ❌ GPU | ❌ GPU | ✅ | CPU only — Metal sim has 256 MB single-allocation cap, LLM weights exceed |
| Web | ✅ | ❌ | ✅ | MediaPipe only |
| macOS | ✅ | ✅ LiteRT-LM only | ✅ | Vision + audio verified on Metal (Gemma 4 + Gemma 3n); Gemma 3n audio GPU is ~2× faster than CPU |
| Windows | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via FFI; GPU via WebGPU/DX12 |
| Linux | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via FFI; GPU via WebGPU/Vulkan |

### PreferredBackend

| Value | Android | iOS | Web | Desktop |
|-------|---------|-----|-----|---------|
| `cpu` | ✅ | ✅ | ❌ | ✅ |
| `gpu` | ✅ | ✅ | ✅ (required) | ✅ |
| `npu` | ✅ (.litertlm) | ❌ | ❌ | ✅ Windows (Intel LunarLake/PantherLake) |

## SDK Gotchas (Non-Obvious)

### ⚠️ maxTokens = CONTEXT window, not output length (#318)
`maxTokens` (on `getActiveModel`/`createModel`) is the whole **context window** — input (system + history + message) **plus** generated output, i.e. the KV-cache budget. It is **NOT** the response length. `.litertlm` models bake a `kv_cache_max_len` (1024 for every supported model — Gemma 4 E2B, FunctionGemma, …); a `maxTokens` below it underflows the native magic-number KV-cache resize and `DYNAMIC_UPDATE_SLICE` fails to allocate tensors at generation (cryptic `Stream error: INTERNAL: …executor.cc:734`). Verified on Pixel 8a (CPU): 100/256/512 crash, 1024/4096 work.
- The litertlm engine now **clamps `maxTokens` up to 1024** with a `gemmaLog` warning (`clampLitertlmContextTokens` in `flutter_gemma_litertlm/lib/src/litert_lm_engine.dart`). MediaPipe `.task` tolerates small values and is not clamped.
- To cap **generation length**, use the new **`maxOutputTokens`** on `createSession`/`openSession` → native `set_max_output_tokens` (litertlm only; MediaPipe has no session-level output cap and logs that it's ignored).
```dart
// ❌ WRONG - meant "100-token reply", actually shrinks the context → crash on .litertlm
await FlutterGemma.getActiveModel(maxTokens: 100);
// ✅ CORRECT - context stays 1024+, output is capped at 100
final model = await FlutterGemma.getActiveModel(maxTokens: 1024);
final session = await model.createSession(maxOutputTokens: 100);
```

### ⚠️ Message.isUser defaults to false!
```dart
// ❌ WRONG - empty response (isUser defaults to false)
const Message(text: 'Hello')
// ✅ CORRECT
const Message(text: 'Hello', isUser: true)
```

### ⚠️ Always close sessions/models
```dart
await session.close();
await inferenceModel.close();
```

### ⚠️ No inline string keys — use PreferencesKeys constants
```dart
// ❌ BAD: prefs.getString('model_path');
// ✅ GOOD: prefs.getString(PreferencesKeys.installedModelFileName);
```
Exception: Migration files may use inline strings for deprecated keys.

### ⚠️ Always read SDK before implementing
Check `lib/flutter_gemma_interface.dart`, implementation files, and `example/` before making changes.

### ⚠️ Generated pigeon is `flutter_gemma_mediapipe/lib/pigeon.g.dart` — DO NOT EDIT MANUALLY
Core has NO pigeon (dropped at the 1.0 cut; its value types are hand-written in `lib/core/domain/platform_types.dart`). Only `flutter_gemma_mediapipe` still uses pigeon (it owns the `PlatformService` HostApi).

## Versions & Dependencies

- **Flutter**: `>=3.44.0` (raised at the 1.0 cut: `large_file_handler` 0.5.0 + dart2wasm need it)
- **Dart SDK**: `>=3.12.0 <4.0.0`
- **iOS**: Minimum 16.0
- **MediaPipe Web**: v0.10.27, Android/iOS: v0.10.33
- **LiteRT-LM**: native libs from `native-v0.16.0` GitHub Release (LiteRT-LM pin `924e79c9`, LiteRT pin `0ff28117`). Android tarball bundles the Qualcomm QNN dispatch stack and Windows tarball bundles Intel NPU dispatch (`LiteRtDispatch.dll` + OpenVino runtime + TBB) for `PreferredBackend.npu` (Qualcomm Snapdragon / Intel LunarLake/PantherLake) — both dispatch libs are **rebuilt from the pin every release**; carrying them forward is what silently broke NPU on both platforms (see the `build-native` skill). v0.16.0: fixes the Android OpenCL per-turn memory leak (LiteRT-LM #2699, #348/#402); v0.15.0 **broke the stream-callback ABI** (4-arg → 2-arg chunk object) with no compat path, handled by a runtime probe in `stream_proxy.c`. Windows discrete GPU works again — the crash was our own dead `litert_link_capi_so` Bazel define, not an upstream regression (#2957 retracted).
- **large_file_handler**: `^0.5.0` (core dep; 0.5.0 declares all 6 platforms — needed for pana platform support + the dart2wasm-clean web graph)
- **Current Version**: core `flutter_gemma` `1.7.0`, `flutter_gemma_rag_sqlite` `1.2.0`, `flutter_gemma_rag_qdrant` `1.2.0`; `flutter_gemma_litertlm` `1.5.0`, `flutter_gemma_mediapipe` `1.0.5`, `flutter_gemma_embeddings` `2.0.0`, `flutter_gemma_speech` `0.4.3`; `flutter_gemma_agent` `0.2.5`, `flutter_gemma_builtin_ai` `0.1.0`, `flutter_gemma_onnx` `0.1.0`; `genkit_flutter_gemma` `0.5.0`, `genkit_hybrid` `0.1.1`
- **0.15.2**: embedding unified on LiteRT C API via Dart FFI on all native platforms (Android + iOS + Desktop). Drops `localagents-rag` JVM dep on Android and the separate TFLite C 0.12.7 tarball on Desktop; `TensorFlowLiteC` pod no longer needed on iOS. Single source of truth for `TaskType.prefix` in Dart, fixes cross-platform embedding drift (#264).

## Platform-Specific Setup

### iOS
```ruby
platform :ios, '16.0'
use_frameworks! :linkage => :static
```
Entitlements needed: `extended-virtual-addressing`, `increased-memory-limit`

### Android
```xml
<!-- libvndksupport.so is required for the GPU backend on Android 12+: the
     v0.13.x OpenCL loader uses its android_load_sphal_library() to dlopen the
     vendor OpenCL ICD. Without it OpenCL fails to load → WebGPU fallback →
     hard-freeze on some Mali drivers (#324). -->
<uses-native-library android:name="libvndksupport.so" android:required="false"/>
<uses-native-library android:name="libOpenCL.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

- **`flutter_gemma_builtin_ai` requires `minSdk 26`** (ML Kit GenAI / AICore floor) — apps using that package must raise their `android/app/build.gradle(.kts)` `minSdk` to 26 or the manifest merger fails (`uses-sdk:minSdkVersion` conflict).

### Web
```html
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

### Desktop (macOS/Windows/Linux)
- Architecture: Dart → `dart:ffi` → LiteRT-LM C API (no JVM, no gRPC)
- Native libs fetched at build time by `flutter_gemma_litertlm/hook/build.dart` (the only hook that carries the version) from the `native-v0.16.0` GitHub release; SHA256-verified, bundled via Native Assets
- Desktop uses `.litertlm` format only (not `.task`)
- Windows GPU requires `dxil.dll` + `dxcompiler.dll` (DirectXShaderCompiler runtime) — bundled in the Windows native archive
- Windows NPU (`PreferredBackend.npu`) requires Intel LunarLake/PantherLake silicon — `LiteRtDispatch.dll` + OpenVino runtime + TBB bundled in the Windows native archive (0.15.1+)

Entitlements needed: `network.client`, `extended-virtual-addressing`, `increased-memory-limit`

## Code Quality

```bash
flutter analyze packages/   # every workspace package (not website/ — it is
                            # outside the workspace, so its deps are unresolved)
dart format .
tool/test_all.sh     # every package, each from its own directory
```

> `flutter test` at the root tests **nothing** (the workspace root has no
> `test/`), and `flutter test packages/<pkg>` runs from the wrong working
> directory — 20 of `flutter_gemma_agent`'s suites read fixtures by a path
> relative to the package and fail on a missing file. `tool/test_all.sh` is
> what CI runs, so local green and CI green mean the same thing.

> ⚠️ **A green local `analyze` does not mean CI is green.** CI installs
> `channel: stable` (whatever is current), while a dev box is usually pinned —
> so CI's analyzer carries lints yours does not. `unawaited_return_in_try_block`
> reached CI months before a 3.44.0 checkout could see it. Warnings fail the
> build (`--no-fatal-infos` only spares `info`), so read the CI log rather than
> trusting the local run.
>
> Analyze `packages/`, not the repo root: `website/` is deliberately outside the
> workspace, its deps are never resolved by the root `pub get`, and analyzing it
> fails — except on a machine that happens to have built the site once.

## Before Committing
```bash
flutter analyze && dart format . && tool/test_all.sh
```

## Key Files

> **1.0 monorepo:** paths below are under `packages/<pkg>/`. The repo is a Dart
> pub workspace (root `pubspec.yaml` `workspace:` list); core = `flutter_gemma`,
> engines/RAG = opt-in sibling packages.

**Core (`packages/flutter_gemma/`):**

| File | Purpose |
|------|---------|
| `lib/flutter_gemma_interface.dart` | Abstract InferenceModel / EmbeddingModel / Session + CloseNotifier seam |
| `lib/core/api/flutter_gemma.dart` | `FlutterGemma.initialize/getActiveModel/installModel/installEmbedder/reset/dispose` |
| `lib/core/message.dart` | Message class (isUser gotcha) |
| `lib/core/domain/` | ModelSource sealed classes |
| `lib/core/registry/{inference_engine_provider,embedding_backend_provider,engine_registry,embedding_registry,runtime_config}.dart` | Probe-chain registry contracts engines/backends implement |
| `lib/core/lifecycle/close_notifier.dart` | `CloseNotifier` mixin (addCloseListener / fireCloseListeners) |
| `lib/core/services/vector_store_filter.dart` | Sealed `Condition` + `Filter` envelope (must/should/mustNot) |
| `lib/core/infrastructure/unconfigured_vector_store.dart` | Default `VectorStoreRepository` sentinel — throws "add a RAG package" |
| `lib/mobile/flutter_gemma_mobile.dart` | Mobile shell — registry-dispatch createModel + EmbeddingModelSpec |
| `lib/web/flutter_gemma_web.dart` | Web shell — registry-dispatch |
| `lib/desktop/flutter_gemma_desktop.dart` | Desktop shell — registry-dispatch |
| `lib/web/web_model_source.dart`, `web_model_manager.dart` | Public shared web infra (imported by litertlm-web + mediapipe-web) |
| `lib/core/domain/platform_types.dart` | Plain-Dart `PreferredBackend` enum + RAG value types (RetrievalResult/VectorStoreStats/DocumentWithEmbedding). Core has NO pigeon/PlatformService — these were hand-written off pigeon at the 1.0 cut so the public graph stays dart:io/wasm-clean |
| `hook/build.dart` | Native Assets hook — empty bundle list (core owns no native lib) |
| `android/src/.../FlutterGemmaPlugin.kt`, `ios/Classes/FlutterGemmaPlugin.swift` | Slim native plugin — hosts only the `flutter_gemma_bundled` channel (file-ops + litertlm NPU `getNativeLibraryDir`) |
| `example/lib/gemma_bootstrap.dart` | Single source of truth for the example's engine/backend lists + RAG switcher |
| `example/lib/models/model.dart` | Model configurations & URLs |

**`packages/flutter_gemma_litertlm/` (.litertlm FFI inference; owns the shared libLiteRtLm bundle):**

| File | Purpose |
|------|---------|
| `lib/src/litert_lm_engine*.dart` | `LiteRtLmEngine` (InferenceEngineProvider; native + web arms via conditional export) |
| `lib/src/ffi/litert_lm_client.dart` | Per-platform FFI client (loading, preload, log capture) |
| `lib/src/ffi/litert_lm_bindings.dart` | Generated dart:ffi bindings to LiteRT-LM C API (inference) |
| `lib/src/ffi/ffi_inference_model.dart` | FFI inference model (mixes CloseNotifier) |
| `lib/src/web/litert_lm_web*.dart` | Web `.litertlm` via `@litert-lm/core` (Engine handshake) |
| `hook/build.dart` | Native Assets hook — OWNS the litertlm bundle; `stage()` is **Apple-only** (Xcode cycle) |
| `native/litert_lm/{build_ios.sh,patch_c_api.sh,stream_proxy.c}` | iOS dylib rebuild + C API patcher + preload helper |

**`packages/flutter_gemma_embeddings/` (runtime-AGNOSTIC common embedder — 2.0.0; depends ONLY on core; the engine supplies the forward-pass over a seam):**

| File | Purpose |
|------|---------|
| `lib/src/forward_pass.dart` | `EmbeddingForwardPass` seam (async load/run/close) + `ForwardResult` + `ForwardPassDescriptor` (`EmbeddingOutputContract` + top-level-tear-off factory, isolate-sendable) |
| `lib/src/embedding_worker.dart` | Engine-agnostic isolate worker: builds the engine's forward core from the descriptor inside the isolate; dispatches finalize on the contract (`pooledFinal`→verbatim, `tokenLevel`→pool) |
| `lib/src/embedding_tokenizer.dart` | Gemma SentencePiece tokenize + BOS=2/EOS=1 + TaskType prefix (`.json`/`.model` loader) |
| `lib/src/pooling.dart` | `meanPoolAndNormalize` (token-level `[1,seq,dim]` only; rejects rank-2 to block the D5 double-normalize trap) |
| `lib/src/common_embedding_model.dart` | `CommonEmbeddingModel` facade (`EmbeddingModel` + CloseNotifier) |
| *(no engine dep, no `hook/build.dart`)* | The LiteRT forward-pass moved to `flutter_gemma_litertlm/lib/src/embedding/` (`LiteRtEmbeddingForwardPass` + `LiteRtEmbeddingBackend`, which now provides the registered backend) |

**`packages/flutter_gemma_mediapipe/` (.task MediaPipe; mobile + web, NO desktop):**

| File | Purpose |
|------|---------|
| `lib/src/mediapipe_engine*.dart` | `MediaPipeEngine` (io/mobile + web arms); `_mapBackend` core↔package PreferredBackend |
| `pigeon.dart` | Package pigeon: `PlatformService` HostApi + redeclared `PreferredBackend` |
| `android/src/.../FlutterGemmaMediaPipePlugin.kt`, `PlatformServiceImpl.kt`, `engines/*` | Android MediaPipe (own pluginClass + channel) |
| `ios/Classes/FlutterGemmaMediaPipePlugin.swift`, `PlatformServiceImpl.swift`, `InferenceModel.swift` | iOS MediaPipe |

**`packages/flutter_gemma_rag_qdrant/` (native RAG; no web):**

| File | Purpose |
|------|---------|
| `lib/src/qdrant_vector_store.dart` | `QdrantVectorStore` (VectorStoreRepository) |
| `lib/src/qdrant/{qdrant_edge_bindings,qdrant_edge_client,point_id_hasher,filter_codec}.dart` | ffigen bindings + Dart wrapper + UUIDv5 hasher + Filter codec |
| `native/qdrant_edge/{qdrant_edge_ffi/,include/qdrant_edge.h,vendored/,build_local.sh}` | Rust cdylib + C header + vendored source + cross-build |
| `hook/build.dart` | Native Assets hook — owns the qdrant_edge bundle |

**`packages/flutter_gemma_rag_sqlite/` (first-class SQLite vector store — in-SQLite `sqlite-vec`/`vec0` KNN on all 6 platforms):**

| File | Purpose |
|------|---------|
| `lib/src/{sqlite_vector_store,web_sqlite_vector_store}.dart` | `SqliteVectorStore` (native, `package:sqlite3` FFI) / `WebSqliteVectorStore` (web, `package:sqlite3/wasm.dart`) — both on `vec0` |
| `lib/src/filter_to_vec0.dart` | `Filter` DSL → vec0 declared-column SQL `WHERE` + binds (one dialect, both arms) |
| `hook/build.dart` | Native Assets hook — fetches the per-platform `vec0` loadable extension |
| `web/rag/sqlite3.wasm` | custom `sqlite3.wasm` with `sqlite-vec`/`vec0` statically linked (app copies to its web root) |

**`packages/flutter_gemma_builtin_ai/` (OS built-in AI; Gemini Nano on Android, Apple Foundation Models on iOS/macOS; no web/desktop):**

| File | Purpose |
|------|---------|
| `lib/src/builtin_ai_engine.dart` | `BuiltInAiEngine` (InferenceEngineProvider; `canHandle` matches `ModelFileType.builtIn`) |
| `lib/src/builtin_ai_model.dart` | `BuiltInAiModel` (InferenceModel; session factory over the pigeon service) |
| `lib/src/builtin_ai_session.dart` | `BuiltInAiSession` (InferenceModelSession; tagged event-channel demux by `sessionId`) |
| `lib/src/availability.dart` | `BuiltInAi` (availability probe + `ensureReady`), `BuiltInAiAvailability`, `BuiltInAiUnavailableException` |
| `lib/src/builtin_ai_models.dart` | `BuiltInAiModels.geminiNano` / `.appleFoundationModels` ready-made `InferenceModelSpec`s |
| `lib/pigeon.g.dart` | Generated pigeon (`BuiltInAiService` HostApi) — **DO NOT EDIT MANUALLY**; regenerate from `pigeon.dart` |
| `android/src/.../` | Android ML Kit GenAI (AICore) native layer; declares `minSdk 26` |
| `darwin/Classes/` (shared iOS+macOS source via `sharedDarwinSource: true`) | Apple Foundation Models native layer |

**`packages/flutter_gemma_onnx/` (ONNX Runtime — ORT-GenAI inference + plain-ORT embeddings; macOS arm64 only in v1, no web):**

| File | Purpose |
|------|---------|
| `lib/src/onnx_engine.dart` | `OnnxEngine` (InferenceEngineProvider; platform-gated `canHandle` + belt-and-suspenders `createModel` guard) |
| `lib/src/onnx_inference_model.dart`, `onnx_session.dart` | `OnnxInferenceModel` (singleton-session lane) / `OnnxSession` (buffers query chunks, drives `GenAiClient.generate`) |
| `lib/src/ffi/gen_ai_client.dart` | `GenAiFfiClient` — worker-isolate ORT-GenAI FFI client (mutex-serialized generate/countTokens; `ORT_LIB_PATH` co-location fix) |
| `lib/src/ffi/gen_ai_protocol.dart` | Isolate message protocol (src-only, not barrel-exported) — the injection seam for a scripted fake worker in tests |
| `lib/src/embedding/onnx_embedding_backend.dart` | `OnnxEmbeddingBackend` (EmbeddingBackendProvider; priority 10 over LiteRT's catch-all 0) |
| `lib/src/embedding/{ort_client,ort_ffi_client,onnx_embedding_forward_pass,onnx_tokenizer_loader}.dart` | Plain ORT C API FFI client + forward pass (WordPiece/SentencePiece, `pooledFinal`/`tokenLevel` contracts) |
| `hook/build.dart` | Native Assets hook — owns the ORT + ORT-GenAI CodeAssets, sourced from Microsoft's own GitHub releases (not a `native-vX` repo tag); `_archivesFor` covers macOS arm64/linux_x64/windows_x64 (Android AAR + iOS pending) |

## Project Structure

```
flutter_gemma/                       # Dart pub workspace (monorepo root)
├── pubspec.yaml                     # root: workspace: [packages/*] + melos config
├── packages/
│   ├── flutter_gemma/               # CORE — no engine; registry, contracts, shells, slim native plugin
│   │   ├── lib/{core,mobile,web,desktop}/   # registry-dispatch shells + contracts
│   │   ├── android/ ios/ windows/   # slim native plugin (bundled channel only)
│   │   ├── hook/build.dart          # empty bundle list
│   │   └── example/                 # example app + integration tests + MIGRATION.md/README.md
│   ├── flutter_gemma_litertlm/      # .litertlm FFI (owns libLiteRtLm) + native/litert_lm/ build scripts
│   ├── flutter_gemma_embeddings/    # LiteRT embeddings (shares libLiteRtLm; isolate worker)
│   ├── flutter_gemma_mediapipe/     # .task MediaPipe (own pigeon + Kotlin + Swift + web JS)
│   ├── flutter_gemma_rag_qdrant/    # native RAG (qdrant-edge Rust FFI)
│   ├── flutter_gemma_rag_sqlite/    # SQLite RAG — in-SQLite vec0 KNN (native sqlite3 FFI + web wasm)
│   ├── flutter_gemma_builtin_ai/    # OS built-in AI — Gemini Nano (Android) / Apple Foundation Models (iOS/macOS)
│   ├── flutter_gemma_onnx/          # ONNX Runtime — ORT-GenAI inference + plain-ORT embeddings (macOS arm64 v1)
│   ├── flutter_gemma_speech/        # opt-in on-device STT (moonshine) + TTS (Matcha) via LiteRT C API (shares libLiteRtLm)
│   ├── flutter_gemma_agent/         # opt-in on-device agent skills (SKILL.md: text/JS/native-intent/MCP) over the function-calling loop
│   ├── genkit_flutter_gemma/        # Firebase Genkit integration (flutter_gemma runtime + converters)
│   └── genkit_hybrid/               # Genkit hybrid on-device + cloud helpers
└── docs/                            # design docs, testing, benchmarks
```

## Repository

- **GitHub**: https://github.com/DenisovAV/flutter_gemma
- **Pub.dev**: https://pub.dev/packages/flutter_gemma
- **Issues**: `gh issue list --repo DenisovAV/flutter_gemma --state open`
- **Changelog**: See `CHANGELOG.md`
