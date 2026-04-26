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

---

## Project Overview

**Flutter Gemma** — multi-platform Flutter plugin for running Google's Gemma AI models locally on devices (Android, iOS, Web, macOS, Windows, Linux). Supports multimodal vision, function calling, thinking mode, GPU acceleration, LoRA weights.

## Architecture Quick Reference

### Core Principles
- **ModelSource**: Type-safe sealed class (`NetworkSource`, `AssetSource`, `BundledSource`, `FileSource`). See `lib/core/domain/`
- **Install vs Runtime separation**: Installation stores identity (modelType + fileType), runtime accepts config (maxTokens, backend, etc.)
- **Engine selection by file extension**: `.task`/`.bin`/`.tflite` → MediaPipe, `.litertlm` → LiteRT-LM
- **All five platforms (Android/iOS/macOS/Linux/Windows)**: Dart → `dart:ffi` → LiteRT-LM C API. Native prebuilts fetched at build time via `hook/build.dart` (Native Assets) from GitHub release `native-v0.10.2`.

### Supported Models

| Model Family | Function Calling | Thinking Mode | Multimodal | Platform Support |
|--------------|------------------|---------------|------------|------------------|
| Gemma 4 E2B | ✅ | ✅ ¹ | ✅ | Android, iOS, Web, Desktop |
| Gemma 4 E4B | ✅ | ✅ ¹ | ✅ | Android, iOS, Web, Desktop |
| Gemma 3 Nano | ✅ | ❌ | ✅ | Android, iOS, Web |
| Gemma 3 270M | ❌ | ❌ | ❌ | Android, iOS, Web |
| Gemma-3 1B | ✅ | ❌ | ❌ | Android, iOS, Web |
| TinyLlama 1.1B | ❌ | ❌ | ❌ | Android, iOS, Web |
| Llama 3.2 1B | ❌ | ❌ | ❌ | Android, iOS, Web |
| Hammer 2.1 0.5B | ✅ | ❌ | ❌ | Android, iOS, Web |
| DeepSeek | ✅ | ✅ | ❌ | Android, iOS, Web |
| Qwen3 | ✅ | ✅ ² | ❌ | Android, iOS, Web, Desktop |
| Qwen2.5 | ✅ | ❌ | ❌ | Android, iOS, Web |
| Phi-4 | ❌ | ❌ | ❌ | Android, iOS, Web |

> ¹ Thinking Mode for Gemma 4: Android, iOS, Desktop only. Web (MediaPipe) does not support `extraContext`.
> ² Qwen3 generates thinking by default; tags are stripped when `isThinking: false`.

### Platform Limitations

| Platform | Vision/Multimodal | Audio | Embeddings | Notes |
|----------|-------------------|-------|------------|-------|
| Android | ✅ | ✅ | ✅ | Full support |
| iOS Device | ✅ | ✅ | ✅ | GPU via Metal delegate (FFI). Auto-setup via podspec script_phase |
| iOS Simulator | ❌ GPU | ❌ GPU | ✅ | CPU only — Metal sim has 256 MB single-allocation cap, LLM weights exceed |
| Web | ✅ | ❌ | ✅ | MediaPipe only |
| macOS | ⚠️ Broken (#684) | ✅ LiteRT-LM only | ✅ | Vision: SDK bug, model hallucinates |
| Windows | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via FFI; GPU via WebGPU/DX12 |
| Linux | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via FFI; GPU via WebGPU/Vulkan |

### PreferredBackend

| Value | Android | iOS | Web | Desktop |
|-------|---------|-----|-----|---------|
| `cpu` | ✅ | ✅ | ❌ | ✅ |
| `gpu` | ✅ | ✅ | ✅ (required) | ✅ |
| `npu` | ✅ (.litertlm) | ❌ | ❌ | ❌ |

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
- **LiteRT-LM**: native libs from `native-v0.10.2` GitHub Release (built from upstream `google-ai-edge/LiteRT-LM` v0.10.2 + commit 5e0d86b for iOS), bundled via Native Assets — same `.so`/`.dylib`/`.dll` set on all platforms
- **Current Version**: 0.14.0

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
- Native libs fetched at build time by `hook/build.dart` from `native-v0.10.2` GitHub release; SHA256-verified, bundled via Native Assets
- ⚠️ **macOS Vision broken** (#684): SDK bug, use text-only mode
- Desktop uses `.litertlm` format only (not `.task`)
- Windows GPU requires `dxil.dll` + `dxcompiler.dll` (DirectXShaderCompiler runtime) — bundled in the Windows native archive

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
| `lib/core/ffi/litert_lm_bindings.dart` | Generated dart:ffi bindings to LiteRT-LM C API |
| `lib/core/ffi/ffi_inference_model.dart` | Shared FFI inference model (used by mobile + desktop) |
| `lib/mobile/flutter_gemma_mobile.dart` | Mobile implementation (FFI for .litertlm, MediaPipe for .task) |
| `lib/web/flutter_gemma_web.dart` | Web implementation (MediaPipe JS) |
| `lib/desktop/flutter_gemma_desktop.dart` | Desktop entrypoint, delegates to FFI client |
| `hook/build.dart` | Native Assets hook: fetches+verifies native prebuilts |
| `native/litert_lm/build_ios.sh` | Local iOS dylib rebuild script (calls patch_c_api.sh) |
| `native/litert_lm/patch_c_api.sh` | C API source patcher (linkshared, set_max_num_images, dispatch_lib_dir) |
| `native/litert_lm/stream_proxy.c` | RTLD_GLOBAL/LoadLibraryEx preload + stderr redirect |
| `ios/flutter_gemma.podspec` | iOS pod with script_phase for dylib symlinks |
| `example/lib/models/model.dart` | Model configurations & URLs |

## Project Structure

```
flutter_gemma/
├── android/              # Android native (Kotlin, MediaPipe + LiteRT-LM JNI)
├── ios/                  # iOS native (Swift) + podspec script_phase
├── lib/                  # Dart implementation
│   ├── core/            # Domain, DI, handlers, model management
│   │   └── ffi/         # dart:ffi client + bindings (used by all 5 platforms)
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
