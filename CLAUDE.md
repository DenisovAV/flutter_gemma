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
- **Desktop**: Dart → gRPC → Kotlin/JVM server → LiteRT-LM native libs

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
| Qwen2.5 | ✅ | ❌ | ❌ | Android, iOS, Web |
| Phi-4 | ❌ | ❌ | ❌ | Android, iOS, Web |

> ¹ Thinking Mode for Gemma 4: Android, iOS, Desktop only. Web (MediaPipe) does not support `extraContext`.

### Platform Limitations

| Platform | Vision/Multimodal | Audio | Embeddings | Notes |
|----------|-------------------|-------|------------|-------|
| Android | ✅ | ✅ | ✅ | Full support |
| iOS Device | ✅ | ✅ | ✅ | Full support |
| iOS Simulator | ❌ | ❌ | ✅ | Vision calculator not in simulator build |
| Web | ✅ | ❌ | ✅ | MediaPipe only |
| macOS | ⚠️ Broken (#684) | ✅ LiteRT-LM only | ✅ | Vision: SDK bug, model hallucinates |
| Windows | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via gRPC |
| Linux | ✅ | ✅ LiteRT-LM only | ✅ | Desktop via gRPC |

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
- **LiteRT-LM Android**: `com.google.ai.edge.litertlm:litertlm-android:0.10.0`
- **Current Version**: 0.13.2

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
- Architecture: Dart → gRPC → Kotlin/JVM server → LiteRT-LM native libs
- Build script auto-downloads Azul Zulu JRE 24 + JAR + extracts natives
- ⚠️ **Use Azul Zulu, NOT Temurin!** Temurin causes Jinja template errors
- ⚠️ **macOS Vision broken** (#684): SDK bug, use text-only mode
- Desktop uses `.litertlm` format only (not `.task`)
- See `DESKTOP_DEBUG.md` for GPU cache clearing

Entitlements needed: `allow-jit`, `network.client`, `network.server`, `extended-virtual-addressing`, `increased-memory-limit`

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
| `lib/mobile/flutter_gemma_mobile.dart` | Mobile implementation |
| `lib/web/flutter_gemma_web.dart` | Web implementation |
| `lib/desktop/grpc_client.dart` | Desktop gRPC client |
| `lib/desktop/server_process_manager.dart` | JVM server lifecycle |
| `example/lib/models/model.dart` | Model configurations & URLs |
| `MIGRATION_SUMMARY.md` | ModelSource migration details |

## Project Structure

```
flutter_gemma/
├── android/              # Android native (Kotlin, MediaPipe + LiteRT-LM engines)
├── ios/                  # iOS native (Swift)
├── lib/                  # Dart implementation
│   ├── core/            # Domain, DI, handlers, model management
│   ├── mobile/          # Mobile platform code
│   ├── web/             # Web platform code
│   └── desktop/         # Desktop gRPC client + server manager
├── litertlm-server/     # Kotlin/JVM gRPC server for desktop
├── example/             # Example app + integration tests
└── test/                # Unit tests
```

## Repository

- **GitHub**: https://github.com/DenisovAV/flutter_gemma
- **Pub.dev**: https://pub.dev/packages/flutter_gemma
- **Issues**: `gh issue list --repo DenisovAV/flutter_gemma --state open`
- **Changelog**: See `CHANGELOG.md`
