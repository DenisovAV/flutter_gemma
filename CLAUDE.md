# Flutter Gemma - Claude Code Documentation

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

1. **ModelFileManager** - Handles model and LoRA weights file management
2. **InferenceModel** - Manages model initialization and response generation
3. **Chat/Session APIs** - Different interfaces for conversation vs single inference
4. **Native Integration** - Platform-specific implementations using MediaPipe GenAI

### Supported Models

| Model Family | Function Calling | Thinking Mode | Multimodal | Platform Support |
|--------------|------------------|---------------|------------|------------------|
| Gemma 3 Nano | ✅ | ❌ | ✅ | Android, iOS, Web |
| Gemma-3 1B | ❌ | ❌ | ❌ | Android, iOS, Web |
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

- **Current Version**: v0.10.24
- **Web CDN**: `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.24`
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
- 27 analyzer issues detected (mostly info level)
- Unused imports in web implementation
- Deprecated `withOpacity` usage (use `.withValues()`)
- Unnecessary string escapes
- Unused local variables

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

**Large File Handler Issues:**
- Current implementation uses `large_file_handler: ^0.3.1`
- Performance bottlenecks in network downloads
- Consider migration to `background_downloader` for better performance
- No optimal buffering or chunk size configuration

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
- **Slow Downloads**: Consider replacing `large_file_handler` with `background_downloader`
- **Inference Speed**: Use GPU backend, optimize token buffer size
- **Memory Leaks**: Always close sessions and models

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
- [ ] Run `flutter analyze` - no errors
- [ ] Run `dart format .` - code formatted
- [ ] All tests pass: `flutter test`
- [ ] Memory management - sessions/models closed
- [ ] Platform-specific testing on Android/iOS
- [ ] Performance tested with large models
- [ ] Documentation updated if API changed

## Project Structure

```
flutter_gemma/
├── android/                 # Android native implementation
│   └── src/main/kotlin/
├── ios/                     # iOS native implementation  
│   └── Classes/
├── lib/                     # Dart implementation
│   ├── core/               # Core abstractions
│   ├── mobile/             # Mobile platform code
│   ├── web/                # Web platform code
│   └── flutter_gemma.dart  # Main API
├── example/                # Example application
├── test/                   # Unit tests
└── docs/                   # Documentation
```

## Future Improvements

### Performance Enhancements
1. Replace `large_file_handler` with `background_downloader`
2. Implement better chunk size configuration
3. Add parallel download support
4. Optimize memory usage for multimodal models

### Feature Additions
1. Enhanced web platform support for images
2. Video/Audio input capabilities
3. More multimodal model support
4. Advanced caching strategies

### Code Quality
1. Address current linting issues (27 warnings/info)
2. Improve test coverage
3. Add performance benchmarks
4. Better error handling and logging

## Repository Information

- **GitHub**: https://github.com/DenisovAV/flutter_gemma
- **Pub.dev**: https://pub.dev/packages/flutter_gemma
- **Current Version**: 0.10.1
- **License**: Check repository for license details
- **Issues**: Report bugs via GitHub Issues

## Contact & Support

For development questions or contributions, refer to:
- GitHub Issues for bug reports
- README.md for basic usage
- Example app for implementation reference
- This CLAUDE.md for development guidelines