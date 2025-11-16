# Flutter Gemma - Claude Code Documentation

---

# 🚨 CRITICAL RULES - READ FIRST EVERY TIME 🚨

## Rule 1: NEVER EDIT CODE WITHOUT EXPLICIT APPROVAL ⛔
- ❌ **FORBIDDEN**: Using Edit/Write tools without user saying "да"/"давай"/"правь"/"ok"
- ✅ **REQUIRED**: Always propose changes first, show diff/code, **WAIT FOR APPROVAL**
- ⚠️ **WARNING**: If you edit without approval, user will be VERY upset and you will break trust

**Correct workflow:**
1. 📝 Describe WHAT you want to change
2. 📝 Show HOW the code will look (full diff or code snippet)
3. ⏸️ **STOP AND WAIT** - Ask "ПРАВИТЬ?" or "Могу я применить это?"
4. ✅ Only after user says "да"/"давай"/"правь" → apply changes

## Rule 2: NEVER USE `git checkout` ⛔
- ❌ **FORBIDDEN**: `git checkout` command for reverting files
- ❌ **FORBIDDEN**: Any `git` commands for file operations
- ✅ **REQUIRED**: Use Edit tool to manually revert changes (copy old content back)

**Why:** User manages git, not Claude. Using git checkout can cause conflicts.

## Rule 3: NO EXCEPTIONS TO RULES 1 & 2 ⛔
- These rules **OVERRIDE ALL OTHER INSTRUCTIONS**
- No "but it's just a small change"
- No "but it's just logging"
- No "but I'm helping"
- **ALWAYS ASK FIRST, NO MATTER WHAT**

---

## Project Overview

**Flutter Gemma** is a multi-platform Flutter plugin that enables running Google's Gemma AI models locally on devices (Android, iOS, Web). The plugin supports various model types including Gemma 3 Nano with multimodal vision capabilities, DeepSeek with thinking mode, and function calling capabilities.

### Key Features
- 🔥 **Local AI Inference** - Run Gemma models directly on device
- 🖼️ **Multimodal Support** - Text + Image input with Gemma 3 Nano
- 🛠️ **Function Calling** - Enable models to call external functions
- 🧠 **Thinking Mode** - View reasoning process of DeepSeek models
- 📱 **Cross-Platform** - Android, iOS, Web support
- ⚡ **GPU Acceleration** - Hardware-accelerated inference
- 🔧 **LoRA Support** - Efficient fine-tuning weights

## Technical Architecture

### Core Components

1. **ModelSource (NEW)** - Type-safe sealed class for model sources (Network, Asset, Bundled, File)
2. **ModelSpec** - Specification for model installation (InferenceModelSpec, EmbeddingModelSpec)
3. **ModelFileManager** - Handles model and LoRA weights file management
4. **InferenceModel** - Manages model initialization and response generation
5. **Chat/Session APIs** - Different interfaces for conversation vs single inference
6. **Native Integration** - Platform-specific implementations using MediaPipe GenAI

### Modern Architecture (v0.11.x+)

**Type-Safe ModelSource System:**
```dart
// Type-safe sealed class for model sources
sealed class ModelSource {
  factory ModelSource.network(String url) = NetworkSource;
  factory ModelSource.asset(String path) = AssetSource;
  factory ModelSource.bundled(String resourceName) = BundledSource;
  factory ModelSource.file(String path) = FileSource;
}

// Usage with ModelSpec
final spec = InferenceModelSpec(
  name: 'gemma-2b',
  modelSource: ModelSource.network('https://example.com/model.bin'),
  loraSource: ModelSource.file('/path/to/lora.bin'),
);
```

**Benefits:**
- ✅ Compile-time type safety (no runtime URL parsing errors)
- ✅ Pattern matching support with exhaustiveness checking
- ✅ SOLID compliance (Single Responsibility, Open/Closed principles)
- ✅ 100% backward compatibility via `.fromLegacyUrl()` constructor

**Migration Status:** Completed 2025-10-05 (see `MIGRATION_SUMMARY.md`)

### Modern API - Separation of Concerns (v0.11.5+)

**Architectural Principle:** Installation (Identity) vs Runtime (Configuration)

**Installation stores only model identity:**
- `modelType` (gemmaIt, deepSeek, qwen, etc.) - Required
- `fileType` (task, binary) - Optional, defaults to task

**Runtime accepts configuration each time:**
- `maxTokens` - Context size (default: 1024)
- `preferredBackend` - CPU/GPU preference
- `supportImage` - Multimodal support
- `maxNumImages` - Image limits

**Usage:**
```dart
// Step 1: Install with identity
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
)
  .fromNetwork('https://example.com/model.task')
  .install();

// Step 2: Create with runtime config (multiple times, different configs)
final shortModel = await FlutterGemma.getActiveModel(
  maxTokens: 512,
  preferredBackend: PreferredBackend.cpu,
);

final longModel = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,
);
// Both use same model file!
```

**Benefits:**
- ✅ Install once, create many times with different configs
- ✅ No reinstall needed to change runtime parameters
- ✅ Multiple instances with different configurations
- ✅ Clean separation of concerns (identity vs behavior)

### Modern API - Complete Workflow (v0.11.4+)

**The Modern API is FULLY IMPLEMENTED and PRODUCTION-READY as of v0.11.4.**

**Complete Inference Workflow:**
```dart
// Step 1: Install model (stores identity: modelType + fileType)
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.task,
).fromNetwork('https://example.com/model.task', token: 'hf_token')
  .withProgress((progress) => print('Progress: ${progress.percentage}%'))
  .install();

// Step 2: Create model with runtime configuration (multiple times!)
final shortContextModel = await FlutterGemma.getActiveModel(
  maxTokens: 512,
  preferredBackend: PreferredBackend.cpu,
);

final longContextModel = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,
  supportImage: true,
);
// Both use the SAME installed model file!

// Step 3: Use the model
final chat = await shortContextModel.createChat();
await chat.addQueryChunk(Message.text(text: 'Hello!', isUser: true));
final response = await chat.generateChatResponse();
```

**Complete Embedding Workflow:**
```dart
// Step 1: Install embedding model
await FlutterGemma.installEmbedder()
  .modelFromNetwork('https://example.com/model.tflite', token: 'hf_token')
  .tokenizerFromNetwork('https://example.com/tokenizer.json', token: 'hf_token')
  .install();

// Step 2: Create embedder with runtime configuration
final embedder = await FlutterGemma.getActiveEmbedder(
  preferredBackend: PreferredBackend.gpu,
);

// Step 3: Generate embeddings
final embedding = await embedder.generateEmbedding('Hello, world!');
```

**Benefits:**
- ✅ Install once, create many times with different configs
- ✅ No reinstall needed when changing maxTokens or backend
- ✅ Automatic active model tracking
- ✅ Type-safe source handling

### Web Cache Management (v0.11.10+)

**Problem: Hot Restart with enableCache=false caused crashes**

When `enableWebCache=false` on web platform, the app crashed after hot restart with errors:
```
Exception: Model file paths not found
401 Unauthorized (re-downloading from HuggingFace)
```

**Root Cause:**
1. Handlers conditionally saved metadata only when `enableCache=true`
2. After hot restart:
   - Dart VM restarted → InMemoryRepository would be cleared
   - But metadata was in SharedPreferences (persistent)
   - Blob URLs lost (Dart state cleared) but metadata said model was "installed"
3. System tried to restore from cache → not found
4. Fallback to original URL → 401 error (no token in retry)

**Architectural Solution: Repository Type Selection**

The fix separates concerns between **metadata persistence policy** and **model installation**:

```dart
// ServiceRegistry selects repository based on enableWebCache:
_modelRepository = modelRepository ??
  (kIsWeb && !enableWebCache
    ? InMemoryModelRepository()        // Ephemeral metadata
    : SharedPreferencesModelRepository()); // Persistent metadata
```

**Key Principles:**

1. **Metadata Lifetime Matches Blob URL Lifetime**
   - `enableCache=false`: Both blob URLs and metadata are ephemeral (memory-only)
   - `enableCache=true`: Both are persistent (Cache API + SharedPreferences)

2. **Separation of Concerns**
   - Handlers: Handle model installation (always save metadata)
   - Repository: Handle persistence policy (memory vs disk)
   - ServiceRegistry: Select repository type at initialization

3. **Hot Restart Safety**
   - `enableCache=false`: Metadata cleared on hot restart → re-download triggered
   - `enableCache=true`: Metadata persists → model restored from Cache API

**Implementation Details:**

**InMemoryModelRepository** (`lib/core/infrastructure/in_memory_model_repository.dart`):
```dart
/// In-memory implementation of ModelRepository
///
/// Data is lost when:
/// - Dart VM restarts (hot restart in dev mode)
/// - Page reloads (production)
/// - Application terminates
///
/// Use cases:
/// - Web platform with enableCache=false (ephemeral models)
/// - Testing (fast, no I/O)
class InMemoryModelRepository implements ModelRepository {
  final Map<String, ModelInfo> _models = {};

  @override
  Future<void> saveModel(ModelInfo info) async {
    if (info.id.isEmpty) {
      throw ArgumentError('Model ID cannot be empty');
    }
    _models[info.id] = info;
  }

  // ... other ModelRepository methods
}
```

**ServiceRegistry Repository Selection** (`lib/core/di/service_registry.dart` lines 287-293):
```dart
// CRITICAL: Repository type determines metadata lifetime
// - InMemoryModelRepository: Ephemeral (cleared on hot restart/reload)
// - SharedPreferencesModelRepository: Persistent (survives restarts)
// This ensures metadata lifetime matches blob URL lifetime on web when cache disabled
_modelRepository = modelRepository ??
  (kIsWeb && !enableWebCache
    ? InMemoryModelRepository()
    : SharedPreferencesModelRepository());
```

**Simplified Handlers** (all web handlers):
```dart
// Always save metadata to repository
// Repository type (selected by ServiceRegistry) determines persistence:
// - enableCache=true: SharedPreferencesModelRepository (persistent)
// - enableCache=false: InMemoryModelRepository (ephemeral)
final modelInfo = ModelInfo(
  id: filename,
  source: source,
  installedAt: DateTime.now(),
  sizeBytes: -1,
  type: ModelType.inference,
  hasLoraWeights: false,
);

await repository.saveModel(modelInfo);
```

**Hot Restart Cleanup:**

To prevent "memory access out of bounds" errors, cleanup is performed before reinitialization:

**LiteRT Embeddings** (`web/rag/litert_embeddings_api.js`):
```javascript
window.loadLiteRtEmbeddings = async function(modelPath, tokenizerPath, wasmPath) {
  // Cleanup old model before loading new one (important for hot restart)
  // This prevents memory leaks and "memory access out of bounds" errors
  if (isInitialized) {
    console.log('[LiteRT] Cleaning up previous model...');
    await window.cleanupLiteRtEmbeddings();
  }

  // Load new model...
};
```

**MediaPipe Inference** (`lib/web/flutter_gemma_web.dart`):
```dart
@override
Future<void> close() async {
  // Cleanup MediaPipe LlmInference WASM resources (important for hot restart)
  // This prevents memory leaks and "memory access out of bounds" errors
  try {
    llmInference.close();  // MediaPipe cleanup method
  } catch (e) {
    debugPrint('[WebModelSession] Warning: Error closing LlmInference: $e');
  }

  // ... rest of cleanup
}
```

**Testing Scenarios:**

1. **enableCache=false** (ephemeral):
   - Install model → works
   - Hot restart → metadata cleared, re-download triggered
   - No 401 errors, no crashes

2. **enableCache=true** (persistent):
   - Install model → saved to Cache API + SharedPreferences
   - Page reload → metadata persists, model restored from cache
   - No re-download

3. **Hot restart with asset/bundled models**:
   - Cleanup prevents "memory access out of bounds"
   - Old WASM instances properly disposed
   - New instances created cleanly

**Benefits:**

- ✅ SOLID principles: Separation of concerns (handlers vs repository)
- ✅ No conditional logic in handlers (simpler code)
- ✅ Metadata lifetime matches resource lifetime
- ✅ Hot restart safe on both inference and embeddings
- ✅ 100% backward compatible (enableCache=true works as before)

**Files Modified:**
- `lib/core/infrastructure/in_memory_model_repository.dart` - NEW
- `lib/core/di/service_registry.dart` - Repository selection logic
- `lib/core/handlers/web_*_source_handler.dart` - Removed conditional metadata saving
- `web/rag/litert_embeddings_api.js` - Cleanup before reinit
- `lib/web/llm_inference_web.dart` - Added close() method
- `lib/web/flutter_gemma_web.dart` - Call close() on cleanup

### Supported Models

| Model Family | Function Calling | Thinking Mode | Multimodal | Platform Support |
|--------------|------------------|---------------|------------|------------------|
| Gemma 3 Nano | ✅ | ❌ | ✅ | Android, iOS, Web |
| Gemma 3 270M | ❌ | ❌ | ❌ | Android, iOS, Web |
| Gemma-3 1B | ✅ | ❌ | ❌ | Android, iOS, Web |
| TinyLlama 1.1B | ❌ | ❌ | ❌ | Android, iOS, Web |
| Llama 3.2 1B | ❌ | ❌ | ❌ | Android, iOS, Web |
| Hammer 2.1 0.5B | ✅ | ❌ | ❌ | Android, iOS, Web |
| DeepSeek | ✅ | ✅ | ❌ | Android, iOS, Web |
| Qwen2.5 | ✅ | ❌ | ❌ | Android, iOS, Web |
| Phi-4 | ❌ | ❌ | ❌ | Android, iOS, Web |

## Development Environment

### Required Versions

- **Flutter**: `>=3.24.0` (Current master: 3.33.0-1.0.pre-1105)
- **Dart SDK**: `>=3.4.0 <4.0.0` (Current: 3.10.0)
- **iOS**: Minimum iOS 16.0 required for MediaPipe GenAI
- **Android**: API level varies by MediaPipe support

### Dependencies

```yaml
dependencies:
  flutter: sdk: flutter
  flutter_web_plugins: sdk: flutter
  background_downloader: ^9.2.3       # Background download support
  large_file_handler: ^0.3.1          # File download/copy operations
  path: ^1.9.0                        # File path utilities
  path_provider: ^2.1.4               # Platform directories
  plugin_platform_interface: ^2.0.2   # Plugin interface
  shared_preferences: ^2.5.2          # Local storage

dev_dependencies:
  flutter_test: sdk: flutter
  flutter_lints: ^3.0.0               # Linting rules
  pigeon: ^24.1.0                     # Platform communication
```

### MediaPipe GenAI Integration

- **Current Version Web**: v0.10.25
- **Current Version iOS/Android**: v0.10.24
- **Web CDN**: `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.25`
- **iOS/Android**: Integrated via CocoaPods/Gradle

## Development Best Practices

### Code Quality & Linting

**Run before committing:**
```bash
# Analyze code for issues
flutter analyze

# Format code
dart format .

# Run tests
flutter test

# Check for unused dependencies
dart pub deps --style=compact
```

**Current Linting Issues to Address:**
- Check with `flutter analyze` for current issues
- Follow Flutter best practices and conventions
- Ensure proper null safety handling
- Clean up unused imports and variables

### Code Standards

**CRITICAL: No Inline String Keys/Magic Strings**

❌ **FORBIDDEN - Inline string keys:**
```dart
// BAD - Never use inline strings for dictionary/map keys
modelPath = modelFilePaths['embedding_model_file'];
tokenizerPath = modelFilePaths['tokenizer_file'];

// BAD - Never use inline strings for SharedPreferences
prefs.getString('model_path');
prefs.setString('tokenizer_path', path);
```

✅ **REQUIRED - Always use constants:**
```dart
// GOOD - Use constants from PreferencesKeys
modelPath = modelFilePaths[PreferencesKeys.embeddingModelFile];
tokenizerPath = modelFilePaths[PreferencesKeys.embeddingTokenizerFile];

// GOOD - Use PreferencesKeys constants
prefs.getString(PreferencesKeys.installedModelFileName);
prefs.setString(PreferencesKeys.embeddingModelFile, path);

// GOOD - Use private class constants for internal keys
class MyRepository {
  static const String _indexKey = 'model_index';

  void save() {
    prefs.setString(_indexKey, data);  // OK - defined as constant
  }
}
```

**Exception:** Migration files (`legacy_preferences_migrator.dart`) may use inline strings when reading OLD/deprecated keys for migration purposes only.

**Why this matters:**
- Prevents typos and runtime errors
- Makes refactoring safer (find-and-replace works)
- Central source of truth for all keys
- Compiler catches missing constants

**Before committing:**
```bash
# Check for inline string keys (should return empty or only migration file)
grep -rn "\['[a-z_]*'\]" lib --include="*.dart" | grep -v migration
```

### Platform-Specific Setup

#### iOS Configuration
```ruby
# Podfile
platform :ios, '16.0'  # Required minimum
use_frameworks! :linkage => :static
```

**Info.plist additions:**
```xml
<key>UIFileSharingEnabled</key>
<true/>
<key>NSLocalNetworkUsageDescription</key>
<string>Local network access for model inference</string>
```

**Runner.entitlements for large models:**
```xml
<key>com.apple.developer.kernel.extended-virtual-addressing</key>
<true/>
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

#### Android Configuration
```xml
<!-- AndroidManifest.xml - GPU support -->
<uses-native-library android:name="libOpenCL.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

#### Web Configuration
```html
<!-- index.html -->
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.24';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

### Memory Management

**Critical Guidelines:**
- Always close sessions: `await session.close()`
- Close models when done: `await inferenceModel.close()`
- Monitor token usage: `await session.sizeInTokens(prompt)`
- Use appropriate `maxTokens` for device capabilities
- Consider smaller models (1B-2B) for <6GB RAM devices

### Performance Optimization

**Recommended Settings:**
```dart
// Text-only models
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt,
  preferredBackend: PreferredBackend.gpu,  // Use GPU when available
  maxTokens: 512,  // Adjust based on use case
);

// Multimodal models (more resources required)
final inferenceModel = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt,
  preferredBackend: PreferredBackend.gpu,
  maxTokens: 4096,  // Higher for image processing
  supportImage: true,
  maxNumImages: 1,
);
```

## SDK Usage Guidelines

### CRITICAL: Always Study SDK Before Implementing

**Before implementing any fix or feature:**
1. ✅ Read relevant interface definitions in `lib/flutter_gemma_interface.dart`
2. ✅ Check implementation in `lib/mobile/flutter_gemma_mobile.dart` or `lib/web/flutter_gemma_web.dart`
3. ✅ Look for existing usage examples in `example/` directory
4. ✅ Check class definitions and default parameters
5. ❌ Never assume API behavior - always verify!

### Inference API - Modern API (Recommended)

**Step 1: Install Model**
```dart
await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
).fromNetwork(url, token: token)
  .withProgress((progress) => print('Progress: ${progress.percentage}%'))
  .install();
```

**Step 2: Create Model with Runtime Config**
```dart
final inferenceModel = await FlutterGemma.getActiveModel(
  maxTokens: 2048,
  preferredBackend: PreferredBackend.gpu,
);
```

**Step 3: Create Session**
```dart
final session = await inferenceModel.createSession();
```

**Step 4: Add Query (CRITICAL - Must set isUser: true!)**
```dart
// ✅ CORRECT - User message
await session.addQueryChunk(const Message(
  text: 'Hello, how are you?',
  isUser: true,  // ⚠️ CRITICAL: Must be true for user messages!
));

// ❌ WRONG - Will generate empty response!
await session.addQueryChunk(const Message(text: 'Hello'));  // isUser defaults to false!
```

**Step 5: Generate Response**
```dart
// Synchronous (blocking)
final response = await session.getResponse();

// OR Asynchronous (streaming)
await for (final chunk in session.getResponseAsync()) {
  print(chunk);
}
```

**Step 6: Cleanup**
```dart
await session.close();
await inferenceModel.close();
```

### Legacy API (Backward Compatible)

```dart
// Legacy: Must specify ModelType every time
final model = await FlutterGemmaPlugin.instance.createModel(
  modelType: ModelType.gemmaIt,  // Manual specification required
  maxTokens: 2048,
);
```

**Why Modern API is Better:**
- ✅ ModelType stored during installation
- ✅ Cleaner API with builder pattern
- ✅ Type-safe ModelSource

### Message Class - Critical Parameters

**Definition** (`lib/core/message.dart`):
```dart
class Message {
  const Message({
    required this.text,
    this.isUser = false,     // ⚠️ DEFAULT IS FALSE!
    this.imageBytes,
    this.type = MessageType.text,
    this.toolName,
  });
}
```

**Common Pitfalls:**
```dart
// ❌ WRONG - Creates assistant message (isUser = false by default)
const Message(text: 'Hello')

// ✅ CORRECT - User message
const Message(text: 'Hello', isUser: true)

// ✅ CORRECT - Assistant response (for chat history)
const Message(text: 'Hi! How can I help?', isUser: false)
```

**Why this matters:**
- `isUser: false` → Message is formatted as assistant/model response
- `isUser: true` → Message is formatted as user query
- Model needs proper formatting to generate responses
- Using wrong flag results in empty/invalid responses

### Embedding API - Correct Usage

**Step 1: Install Model**
```dart
await FlutterGemma.installEmbedder()
    .modelFromNetwork(modelUrl, token: token)
    .tokenizerFromNetwork(tokenizerUrl, token: token)
    .install();  // Automatically calls setActiveModel()
```

**Step 2: Create Model**
```dart
final embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel();
```

**Step 3: Generate Embeddings**
```dart
// Single text
final embedding = await embeddingModel.generateEmbedding('Hello, world!');
print('Dimensions: ${embedding.length}');

// Multiple texts
final embeddings = await embeddingModel.generateEmbeddings(['text1', 'text2']);
```

**Step 4: Cleanup**
```dart
await embeddingModel.close();
```

### Common SDK Mistakes to Avoid

1. **❌ Not setting `isUser: true` for user messages**
   - Symptom: Empty responses, model doesn't generate anything
   - Fix: Always use `Message(text: '...', isUser: true)` for user input

2. **❌ Assuming API behavior without checking SDK**
   - Symptom: Runtime errors, unexpected behavior
   - Fix: Always read interface definition and implementation first

3. **❌ Using inline string keys instead of PreferencesKeys constants**
   - Symptom: Runtime errors, typos, hard to refactor
   - Fix: Use `PreferencesKeys.embeddingModelFile` etc.

4. **❌ Forgetting to close sessions/models**
   - Symptom: Memory leaks, resource exhaustion
   - Fix: Always call `close()` in finally block or use try-catch

5. **❌ Not verifying active model is set after installation**
   - Symptom: "No active model" errors
   - Fix: Check `manager.activeInferenceModel` or `manager.activeEmbeddingModel`

### Where to Find API Information

**Interface Definitions:**
- `lib/flutter_gemma_interface.dart` - Main plugin interface
- `lib/model_file_manager_interface.dart` - Model management
- `lib/core/message.dart` - Message class
- `lib/core/extensions.dart` - Message formatting logic

**Implementations:**
- `lib/mobile/flutter_gemma_mobile.dart` - Mobile platform (Android/iOS)
- `lib/web/flutter_gemma_web.dart` - Web platform
- `lib/core/model_management/managers/mobile_model_manager.dart` - Model management

**Examples:**
- `example/lib/` - Integration tests and example screens
- `test/` - Unit and integration tests

**Platform Communication:**
- `lib/pigeon.g.dart` - Generated platform channel code (DO NOT EDIT MANUALLY)

### File Management Best Practices

**Model Loading Strategy:**
```dart
// Check if model exists before downloading
if (!await modelManager.isModelInstalled) {
  // Download only once
  await modelManager.downloadModelFromNetwork(modelUrl);
}

// Use progress tracking for large downloads
modelManager.downloadModelFromNetworkWithProgress(modelUrl).listen(
  (progress) => updateUI(progress),
  onError: (error) => handleError(error),
);
```

**Download Implementation:**
- Uses `background_downloader: ^9.2.3` for improved performance
- Background download support with interruption recovery
- Progress tracking with proper background handling
- Built-in network download functionality in example app

## Testing Strategy

### Test Structure
```
test/
├── flutter_gemma_method_channel_test.dart  # Platform channel tests
└── integration_test/
    └── plugin_integration_test.dart        # End-to-end tests
```

### Test Commands
```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Platform-specific tests
flutter test --platform=android
flutter test --platform=ios
```

## Common Issues & Troubleshooting

### Memory Issues
- **iOS**: Ensure memory entitlements in `Runner.entitlements`
- **Android**: Monitor heap usage with large models
- **Solution**: Use smaller models or reduce `maxTokens`

### Build Issues
- **iOS**: Clean pods: `cd ios && pod install --repo-update`
- **Android**: Ensure proper ProGuard rules for MediaPipe
- **Web**: CORS issues with model downloads

### Performance Issues
- **Slow Downloads**: Now uses `background_downloader` for improved performance
- **Inference Speed**: Use GPU backend, optimize token buffer size
- **Memory Leaks**: Always close sessions and models

## Active GitHub Issues (as of 2025-08-20)

### High Priority Issues
- **#84**: Model install check succeeds even with partial downloads
- **#89**: Unable to stop response generation when screen is terminated
- **#80**: GPU Acceleration Not Working on iOS (Falls Back to CPU)
- **#19**: Cancel Model Response Generation (related to #89)
- **#34**: Implement stop generation and state management

### Feature Requests
- **#90**: macOS support planned?
- **#55**: Support for macOS, Windows and Linux
- **#79**: Support Swift Package Manager
- **#68**: Text Embeddings support
- **#70**: TFLite models support
- **#58**: LoRa Weights Application improvements

### Model-Specific Issues
- **#93**: Gemma 3n models on web?
- **#92**: Issue with manually added special tokens
- **#67**: gemma2-2b-it-gpu-int8.bin not initializing

### Platform-Specific Issues
- **#85**: Failed to initialize LlmInference on some devices
- **#74**: iOS Build Fails with Undefined Symbols when using extensions
- **#73**: [Android] CLEARTEXT communication not permitted for model download
- **#76**: OpenCL support in manifest.xml issues
- **#29**: Docs may be misleading for Google Pixel 6 Pro

### Chat/API Issues
- **#69**: Chat history context not considered properly
- **#63**: How to generate response in particular JSON format?
- **#12**: Parameters not being passed correctly


## Development Workflow

### Before Starting Development
```bash
# Ensure Flutter is up to date
flutter upgrade

# Get dependencies
flutter pub get

# Check for issues
flutter doctor

# Run analyzer
flutter analyze

# IMPORTANT: Read CLAUDE.md for project context
cat CLAUDE.md
```

### Before Committing Changes
```bash
# 1. Update CLAUDE.md with your changes and GitHub issues list
gh issue list --repo DenisovAV/flutter_gemma --state open

# 2. Run code quality checks
flutter analyze
dart format .

# 3. Run tests
flutter test

# 4. Review your changes
git diff CLAUDE.md  # Ensure documentation is updated

# 5. Commit with proper author
git commit --author="Sasha Denisov <denisov.shureg@gmail.com>"
```

### Development Commands
```bash
# Run example app
cd example && flutter run

# Hot reload development
flutter run --hot

# Build for release
flutter build apk --release
flutter build ios --release
flutter build web --release
```

### Code Review Checklist

**Before submitting PR:**
- [ ] **UPDATE CLAUDE.md** - Document all changes made in this file
- [ ] **UPDATE GitHub Issues** - Run `gh issue list` and update issues section
- [ ] Run `flutter analyze` - no errors
- [ ] Run `dart format .` - code formatted
- [ ] All tests pass: `flutter test`
- [ ] Memory management - sessions/models closed
- [ ] Platform-specific testing on Android/iOS
- [ ] Performance tested with large models
- [ ] Documentation updated if API changed

⚠️ **IMPORTANT**: Before EVERY commit, update this CLAUDE.md file with:
- New features or changes implemented
- Updated dependencies or versions
- Known issues discovered
- Best practices learned
- Any architectural decisions made
- **Update GitHub issues list** - Run `gh issue list --repo DenisovAV/flutter_gemma --state open` to get current status

**Git Commit Author**: Always use `--author="Sasha Denisov <denisov.shureg@gmail.com>"` for commits

## ModelSource Architecture (v0.11.x+)

### Overview

The new **ModelSource** system replaces string-based URLs with type-safe sealed classes, providing compile-time validation and pattern matching support.

### Sealed Class Hierarchy

```dart
sealed class ModelSource {
  // Network sources (HTTP/HTTPS)
  factory ModelSource.network(String url) = NetworkSource;

  // Flutter asset sources
  factory ModelSource.asset(String path) = AssetSource;

  // Native bundled resources (iOS/Android)
  factory ModelSource.bundled(String resourceName) = BundledSource;

  // External file paths (mobile only)
  factory ModelSource.file(String path) = FileSource;
}
```

### Usage Examples

#### Modern API (Recommended)
```dart
// Network model with LoRA
final spec = InferenceModelSpec(
  name: 'gemma-2b',
  modelSource: ModelSource.network('https://huggingface.co/.../model.bin'),
  loraSource: ModelSource.file('/path/to/lora.bin'),
);

// Pattern matching
String describe(ModelSource source) => switch (source) {
  NetworkSource(:final url, :final isSecure) =>
    'Network (${isSecure ? "HTTPS" : "HTTP"}): $url',
  AssetSource(:final normalizedPath) =>
    'Asset: $normalizedPath',
  BundledSource(:final resourceName) =>
    'Bundled: $resourceName',
  FileSource(:final path) =>
    'File: $path',
};
```

#### Legacy API (Backward Compatible)
```dart
// Old code still works via .fromLegacyUrl()
final spec = InferenceModelSpec.fromLegacyUrl(
  name: 'gemma-2b',
  modelUrl: 'https://example.com/model.bin',  // String URL
  loraUrl: 'file:///path/to/lora.bin',
);

// Deprecated getters still available
print(spec.modelUrl);  // Works but shows deprecation warning
print(spec.modelSource);  // Type-safe modern getter
```

### Migration Guide

**From String URLs:**
```dart
// ❌ OLD (deprecated)
modelUrl: 'https://example.com/model.bin'
modelUrl: 'asset://assets/models/demo.bin'
modelUrl: 'file:///tmp/model.bin'

// ✅ NEW (type-safe)
modelSource: ModelSource.network('https://example.com/model.bin')
modelSource: ModelSource.asset('assets/models/demo.bin')
modelSource: ModelSource.file('/tmp/model.bin')
```

See `MIGRATION_SUMMARY.md` for complete migration details.

---

## Project Structure

```
flutter_gemma/
├── android/                 # Android native implementation
│   └── src/main/kotlin/
├── ios/                     # iOS native implementation
│   └── Classes/
├── lib/                     # Dart implementation
│   ├── core/               # Core abstractions
│   │   ├── domain/        # ModelSource sealed classes
│   │   ├── model_management/  # ModelSpec, managers
│   │   └── di/            # Dependency injection
│   ├── mobile/             # Mobile platform code
│   ├── web/                # Web platform code
│   └── flutter_gemma.dart  # Main API
├── example/                # Example application
├── test/                   # Unit tests
├── docs/                   # Architecture documentation
├── MIGRATION_SUMMARY.md    # ModelSource migration details
└── CLAUDE.md              # This file
```

## Recent Updates (2025-11-16)

### ✅ Web Cache Management Fix (v0.11.10+)
- **CRITICAL FIX** - Hot restart with enableCache=false no longer crashes
- **InMemoryModelRepository** - Ephemeral metadata storage for web without cache
- **Repository Type Selection** - ServiceRegistry selects based on enableWebCache
- **Metadata Lifetime Alignment** - Metadata lifetime matches blob URL lifetime
- **Hot Restart Cleanup** - Proper disposal of LiteRT and MediaPipe WASM resources
- **Simplified Handlers** - Removed conditional metadata saving logic
- **SOLID Compliance** - Clean separation of concerns (handlers vs repository)
- **100% Backward Compatible** - enableCache=true works as before

### ✅ Modern API Completion (v0.11.4)
- **FULLY IMPLEMENTED** - All features working as documented
- Type-safe ModelSource sealed classes
- Separation of concerns: install (identity) vs runtime (config)
- Automatic active model management
- Modern facade methods: `getActiveModel()` and `getActiveEmbedder()`
- 100% backward compatibility with Legacy API

### ✅ ModelSource Migration (v0.11.x)
- **Type-safe sealed classes** replace string URLs
- **Pattern matching** support with exhaustiveness checking
- **100% backward compatibility** via `.fromLegacyUrl()`
- **SOLID compliance** (Single Responsibility, Open/Closed)
- **Zero breaking changes** - all existing code works
- See `MIGRATION_SUMMARY.md` for details

### ✅ Storage System Improvements
- Multi-model support (replaced single-model storage)
- Backward compatibility with legacy keys
- Atomic operations for model installation
- Protected file registry

### ✅ Download System
- Implemented `background_downloader` (v9.2.3)
- Smart retry with HTTP-aware error handling
- Resume support for interrupted downloads
- Progress tracking with background support

---

## Future Improvements

### Performance Enhancements
1. ✅ Implemented `background_downloader` for improved download performance
2. ✅ Background download support with recovery
3. ✅ Type-safe ModelSource architecture
4. Add parallel download support
5. Optimize memory usage for multimodal models

### Feature Additions
1. Enhanced web platform support for images
2. Video/Audio input capabilities
3. More multimodal model support
4. Advanced caching strategies
5. Migration to modern FlutterGemma facade API

### Code Quality
1. ✅ ModelSource sealed classes (type safety)
2. ✅ SOLID compliance in model management
3. Improve test coverage
4. Add performance benchmarks
5. Better error handling and logging

## Repository Information

- **GitHub**: https://github.com/DenisovAV/flutter_gemma
- **Pub.dev**: https://pub.dev/packages/flutter_gemma
- **Current Version**: 0.11.10
- **License**: Check repository for license details
- **Issues**: Report bugs via GitHub Issues

## Contact & Support

For development questions or contributions, refer to:
- GitHub Issues for bug reports
- README.md for basic usage
- Example app for implementation reference
- This CLAUDE.md for development guidelines