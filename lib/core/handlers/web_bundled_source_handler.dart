import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';

/// Handles installation of models from native bundled resources (WEB PLATFORM)
///
/// On web, bundled resources are served by the web server at paths like:
/// - assets/models/gemma.task
/// - assets/models/lora-weights.bin
///
/// This handler:
/// 1. Constructs the bundled resource URL path
/// 2. Registers the URL with WebFileSystemService
/// 3. Saves metadata to ModelRepository
/// 4. MediaPipe loads directly from the URL (no file copy)
///
/// Features:
/// - No file copying (web has no local file system)
/// - Direct URL registration for MediaPipe
/// - Simulated progress for UX consistency
/// - Instant "installation" (resources already bundled)
///
/// Platform: Web only
class WebBundledSourceHandler implements SourceHandler {
  final WebFileSystemService fileSystem;
  final ModelRepository repository;

  WebBundledSourceHandler({
    required this.fileSystem,
    required this.repository,
  });

  @override
  bool supports(ModelSource source) => source is BundledSource;

  @override
  Future<void> install(ModelSource source) async {
    if (source is! BundledSource) {
      throw ArgumentError('WebBundledSourceHandler only supports BundledSource');
    }

    // Construct the bundled resource URL
    // On web, bundled resources are served from assets/models/
    final bundledUrl = 'assets/models/${source.resourceName}';

    // Register URL with WebFileSystemService
    // This is CRITICAL - MediaPipe looks up URLs via getUrl()
    fileSystem.registerUrl(source.resourceName, bundledUrl);

    // Save metadata to repository
    // Note: Web can't determine file size without HTTP HEAD request
    // Use -1 to indicate "unknown but exists"
    final modelInfo = ModelInfo(
      id: source.resourceName,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web bundled resources
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  @override
  Stream<int> installWithProgress(ModelSource source) async* {
    if (source is! BundledSource) {
      throw ArgumentError('WebBundledSourceHandler only supports BundledSource');
    }

    // Simulate progress for UX consistency
    // Bundled resources are already available, so this is instant
    yield 0;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 50;
    await Future.delayed(const Duration(milliseconds: 50));

    // Construct the bundled resource URL
    final bundledUrl = 'assets/models/${source.resourceName}';

    // Register URL with WebFileSystemService
    fileSystem.registerUrl(source.resourceName, bundledUrl);

    yield 100;

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: source.resourceName,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web bundled resources
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  @override
  bool supportsResume(ModelSource source) {
    // Bundled resources are always available, no resume needed
    return false;
  }
}
