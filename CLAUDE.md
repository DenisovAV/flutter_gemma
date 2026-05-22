# Flutter Gemma - Claude Code Documentation

# 🚨 CRITICAL RULES 🚨

## Rule 1: NEVER EDIT CODE WITHOUT EXPLICIT APPROVAL ⛔
- Always propose changes first, show diff/code, **WAIT FOR APPROVAL**
- Only after user says "yes"/"go ahead"/"ok" → apply changes

## Rule 2: NEVER USE `git checkout` ⛔
- Use Edit tool to manually revert changes. User manages git.

## Rule 3: GIT COMMITS ⛔
- No "Co-Authored-By: Claude" or AI attribution/footers
- Always use `--author="Sasha Denisov <denisov.shureg@gmail.com>"`

## Rule 4: NEVER HARDCODE SECRETS ⛔
- Use `String.fromEnvironment('KEY_NAME')` or `--dart-define=KEY=value`
- GitHub Push Protection blocks commits with secrets

## Rule 5: SEARCH ALL FILES ⛔
- Never use file extension filters unless explicitly requested
- Use `grep -rn "pattern" /path/ 2>/dev/null | grep -v node_modules | grep -v ".gradle/"`

## Rule 6: NEVER USE `flutter drive` ⛔
- iPhone/iOS integration tests ALWAYS use `flutter test integration_test/<file>.dart -d <device-id>`
- If `flutter test` hangs on "Dart VM Service was not discovered" or fails with "Cannot start app on wirelessly tethered iOS device", fix iPhone/macOS USB tunnel (Personal Hotspot off, iPhone USB enabled in Network settings, Trust dialog) — do NOT switch to `flutter drive` as a workaround
- `flutter drive` is forbidden in this project, full stop

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
- **ModelSource**: Type-safe sealed class (`NetworkSource`, `AssetSource`, `BundledSource`, `FileSource`). See `lib/core/domain/`
- **Install vs Runtime separation**: Installation stores identity (modelType + fileType), runtime accepts config (maxTokens, backend, etc.)
- **Engine selection by file extension**: `.task`/`.bin`/`.tflite` → MediaPipe, `.litertlm` → LiteRT-LM
- **All five platforms (Android/iOS/macOS/Linux/Windows)**: Dart → `dart:ffi` → LiteRT-LM C API (inference) + LiteRT C API (embeddings). Native prebuilts fetched at build time via `hook/build.dart` (Native Assets) from GitHub release `native-v0.12.0`.

### Supported Models

| Model Family | Function Calling | Thinking Mode | Multimodal | Platform Support |
|--------------|------------------|---------------|------------|------------------|
| Gemma 4 E2B/E4B | ✅ | ✅ ¹ | ✅ vision + audio | Android, iOS, Web, Desktop |
| Gemma3n E2B/E4B | ✅ | ❌ | ✅ vision + audio | Android, iOS, Web, Desktop |
| Gemma 3 1B | ✅ | ❌ | ❌ | Android, iOS, Web, Desktop |
| Gemma 3 270M | ❌ | ❌ | ❌ | Android, iOS, Web, Desktop |
| FastVLM 0.5B | ❌ | ❌ | ✅ vision | Desktop (`.litertlm`) |
| FunctionGemma 270M | ✅ | ❌ | ❌ | Android, iOS, Desktop |
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

### ⚠️ `lib/pigeon.g.dart` is generated — DO NOT EDIT MANUALLY

## Versions & Dependencies

- **Flutter**: `>=3.24.0`
- **Dart SDK**: `>=3.6.0 <4.0.0`
- **iOS**: Minimum 16.0
- **MediaPipe Web**: v0.10.27, Android/iOS: v0.10.33
- **LiteRT-LM**: native libs from `native-v0.12.0` GitHub Release. Windows tarball bundles Intel NPU dispatch (`LiteRtDispatch.dll` + OpenVino runtime + TBB) for `PreferredBackend.npu` on Intel LunarLake/PantherLake silicon. MTP (speculative decoding) support for Gemma 4.
- **Current Version**: 0.16.1
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
<uses-native-library android:name="libOpenCL.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

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
- Native libs fetched at build time by `hook/build.dart` from `native-v0.12.0` GitHub release; SHA256-verified, bundled via Native Assets
- Desktop uses `.litertlm` format only (not `.task`)
- Windows GPU requires `dxil.dll` + `dxcompiler.dll` (DirectXShaderCompiler runtime) — bundled in the Windows native archive
- Windows NPU (`PreferredBackend.npu`) requires Intel LunarLake/PantherLake silicon — `LiteRtDispatch.dll` + OpenVino runtime + TBB bundled in the Windows native archive (0.15.1+)

Entitlements needed: `network.client`, `extended-virtual-addressing`, `increased-memory-limit`

## Code Quality

```bash
flutter analyze
dart format .
flutter test
```

## Before Committing
```bash
flutter analyze && dart format . && flutter test
```

## Key Files

| File | Purpose |
|------|---------|
| `lib/flutter_gemma_interface.dart` | Main plugin interface |
| `lib/core/message.dart` | Message class (isUser gotcha) |
| `lib/core/domain/` | ModelSource sealed classes |
| `lib/core/ffi/litert_lm_client.dart` | Per-platform FFI client (loading, preload, log capture) |
| `lib/core/ffi/litert_lm_bindings.dart` | Generated dart:ffi bindings to LiteRT-LM C API (inference) |
| `lib/core/ffi/ffi_inference_model.dart` | Shared FFI inference model (used by mobile + desktop) |
| `lib/core/litert/litert_bindings.dart` | Hand-written dart:ffi bindings to LiteRT C API (embeddings); dual MSVC/POSIX `LiteRtLayout` structs |
| `lib/core/litert/litert_embedding_model.dart` | Shared embedding model — Gecko / EmbeddingGemma `.tflite` on all 5 native platforms |
| `lib/core/qdrant/qdrant_edge_bindings.dart` | ffigen-generated dart:ffi bindings to the qdrant_edge_ffi shim (0.16.0+) |
| `lib/core/qdrant/qdrant_edge_client.dart` | High-level Dart wrapper around `QdrantEdgeBindings` (shard lifecycle, Finalizer, JSON marshalling) |
| `lib/core/qdrant/point_id_hasher.dart` | UUIDv5 hash mapping arbitrary `String id` → qdrant `PointId::Uuid` |
| `lib/core/qdrant/filter_codec.dart` | Encodes `Filter` DSL → qdrant `Filter` JSON envelope |
| `lib/core/services/vector_store_filter.dart` | Sealed `Condition` + `Filter` envelope (must/should/mustNot) |
| `lib/core/infrastructure/qdrant_vector_store_repository.dart` | Native default `VectorStoreRepository` impl (0.16.0+) |
| `lib/core/infrastructure/dart_vector_store_repository.dart` | `@Deprecated` legacy impl (sqlite3 + `local_hnsw`); removal in 1.0 |
| `native/qdrant_edge/qdrant_edge_ffi/` | Rust cdylib over qdrant-edge — 10 `qe_*` C functions exposed via `extern "C"` |
| `native/qdrant_edge/include/qdrant_edge.h` | C header consumed by ffigen + Dart FFI |
| `native/qdrant_edge/vendored/qdrant-edge/` | Vendored amalgamated qdrant-edge source with `EdgeShardOptions` + Android flock skip patch; removed once upstream qdrant/qdrant#9067 merges |
| `native/qdrant_edge/build_local.sh` | Local cross-build script for macOS arm64 + iOS arm64 device/sim + Android arm64 |
| `lib/mobile/flutter_gemma_mobile.dart` | Mobile implementation (FFI for .litertlm, MediaPipe for .task) |
| `lib/web/flutter_gemma_web.dart` | Web implementation (MediaPipe JS) |
| `lib/desktop/flutter_gemma_desktop.dart` | Desktop entrypoint, delegates to FFI client |
| `hook/build.dart` | Native Assets hook: fetches+verifies native prebuilts |
| `native/litert_lm/build_ios.sh` | Local iOS dylib rebuild script (calls patch_c_api.sh) |
| `native/litert_lm/patch_c_api.sh` | C API source patcher (linkshared, set_max_num_images, dispatch_lib_dir) |
| `native/litert_lm/stream_proxy.c` | RTLD_GLOBAL/LoadLibraryEx preload helper + stderr redirect for debug logs |
| `ios/flutter_gemma.podspec` | iOS pod (companion `lib*.dylib` symlinks come from `example/ios/Podfile` `post_install` — pod-level `script_phase` doesn't reach the host app target) |
| `example/ios/Podfile` | iOS host app `post_install` block — creates `lib*.dylib` symlinks next to `.framework`s for `gpu_registry` basename `dlopen` |
| `example/macos/Podfile` | Same `post_install` pattern for macOS (added in 0.14.0; 3-tier dylib source fallback added in 0.14.4 for #255 — Native Assets cache → plugin symlink → repo path) |
| `example/lib/models/model.dart` | Model configurations & URLs |

## Project Structure

```
flutter_gemma/
├── android/              # Android native (Kotlin, MediaPipe + LiteRT-LM JNI)
├── ios/                  # iOS native (Swift) + podspec script_phase
├── lib/                  # Dart implementation
│   ├── core/            # Domain, DI, handlers, model management
│   │   ├── ffi/         # dart:ffi client + bindings for LiteRT-LM inference (all 5 platforms)
│   │   └── litert/      # dart:ffi bindings + shared model for LiteRT C API embeddings (all 5 platforms)
│   ├── mobile/          # Mobile entrypoint (selects FFI vs MediaPipe)
│   ├── web/             # Web platform code
│   └── desktop/         # Desktop entrypoint (delegates to lib/core/ffi/)
├── native/litert_lm/    # Native build scripts + C API patcher + stream_proxy.c
├── hook/build.dart       # Native Assets hook (fetches CI prebuilts at build time)
├── example/             # Example app + integration tests
└── test/                # Unit tests
```

## Repository

- **GitHub**: https://github.com/DenisovAV/flutter_gemma
- **Pub.dev**: https://pub.dev/packages/flutter_gemma
- **Issues**: `gh issue list --repo DenisovAV/flutter_gemma --state open`
- **Changelog**: See `CHANGELOG.md`
