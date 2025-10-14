import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';

/// Handles installation of models from native bundled resources
///
/// Features:
/// - Uses platform-specific native resource paths
/// - Android: assets/models/{resourceName}
/// - iOS: Bundle.main.path(forResource:)
/// - Web: /assets/{resourceName}
/// - No copying required (uses native path directly)
/// - Single-step progress (resources already available)
class BundledSourceHandler implements SourceHandler {
  final FileSystemService fileSystem;
  final ModelRepository repository;

  BundledSourceHandler({
    required this.fileSystem,
    required this.repository,
  });

  @override
  bool supports(ModelSource source) => source is BundledSource;

  @override
  Future<void> install(ModelSource source) async {
    if (source is! BundledSource) {
      throw ArgumentError('BundledSourceHandler only supports BundledSource');
    }

    // Get platform-specific bundled resource path
    // This path is used directly by the native layer (no copying needed)
    final bundledPath = await fileSystem.getBundledResourcePath(source.resourceName);

    // Get file size for metadata
    final sizeBytes = await fileSystem.getFileSize(bundledPath);

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: source.resourceName,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: sizeBytes,
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  @override
  Stream<int> installWithProgress(ModelSource source) async* {
    if (source is! BundledSource) {
      throw ArgumentError('BundledSourceHandler only supports BundledSource');
    }

    // Get platform-specific bundled resource path
    final bundledPath = await fileSystem.getBundledResourcePath(source.resourceName);

    // Bundled resources are immediately available, report 100% after verification
    yield 100;

    // Get file size for metadata
    final sizeBytes = await fileSystem.getFileSize(bundledPath);

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: source.resourceName,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: sizeBytes,
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
