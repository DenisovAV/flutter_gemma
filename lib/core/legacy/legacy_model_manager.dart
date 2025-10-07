/// Legacy Model Manager - Migration Guide
///
/// ## ⚠️ Legacy API Deprecation Notice
///
/// The old ModelSpec-based API (`UnifiedDownloadEngine`, `ModelFileManager`, etc.)
/// continues to work but is now deprecated. New code should use the Modern API.
///
/// ## Migration Guide
///
/// ### Old API (Legacy - Deprecated):
/// ```dart
/// // OLD - Still works but deprecated
/// final spec = InferenceModelSpec(
///   name: 'gemma-2b',
///   files: [ModelFile(filename: 'model.bin', url: 'https://...')],
/// );
///
/// // Using UnifiedDownloadEngine
/// await UnifiedDownloadEngine.downloadModel(spec);
/// ```
///
/// ### New API (Modern - Recommended):
/// ```dart
/// // NEW - Modern API with type safety
/// import 'package:flutter_gemma/core/api/flutter_gemma.dart';
///
/// // Initialize once
/// FlutterGemma.initialize(huggingFaceToken: 'hf_...');
///
/// // Install from network
/// await FlutterGemma.installModel()
///   .fromNetwork('https://...')
///   .withProgress((progress) => print('Progress: $progress%'))
///   .install();
///
/// // Install from asset
/// await FlutterGemma.installModel()
///   .fromAsset('models/gemma.bin')
///   .install();
///
/// // Install from bundled resource
/// await FlutterGemma.installModel()
///   .fromBundled('gemma.bin')
///   .install();
///
/// // Install from external file
/// await FlutterGemma.installModel()
///   .fromFile('/path/to/model.bin')
///   .install();
/// ```
///
/// ## API Comparison
///
/// | Legacy API | Modern API |
/// |------------|------------|
/// | `UnifiedDownloadEngine.downloadModel(spec)` | `FlutterGemma.installModel().fromNetwork(url).install()` |
/// | `UnifiedDownloadEngine.downloadModelWithProgress(spec)` | `FlutterGemma.installModel().fromNetwork(url).withProgress(...).install()` |
/// | `UnifiedDownloadEngine.isModelInstalled(spec)` | `FlutterGemma.isModelInstalled(modelId)` |
/// | `ModelFileSystemManager.deleteModel(spec)` | `FlutterGemma.uninstallModel(modelId)` |
///
/// ## Why Migrate?
///
/// The Modern API provides:
/// - ✅ Type-safe sealed classes (NetworkSource, AssetSource, BundledSource, FileSource)
/// - ✅ Dependency injection for testability
/// - ✅ SOLID principles compliance
/// - ✅ Cleaner error handling
/// - ✅ Better progress tracking
/// - ✅ Resume capability
/// - ✅ Simpler API surface
/// - ✅ Better documentation
///
/// ## Compatibility
///
/// Both APIs work simultaneously:
/// - Legacy API (UnifiedDownloadEngine) - continues to work
/// - Modern API (FlutterGemma) - new features
///
/// Gradual migration is recommended. Legacy API will be removed in v2.0.0.
///
/// ## Getting Started
///
/// See [lib/core/README.md](../README.md) for complete Modern API documentation.
library legacy_model_manager;
