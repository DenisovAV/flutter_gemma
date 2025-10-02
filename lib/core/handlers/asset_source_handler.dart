import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/services/asset_loader.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';
import 'package:path/path.dart' as path;

/// Handles installation of models from Flutter assets
///
/// Features:
/// - Loads assets using AssetLoader (supports web and mobile)
/// - Copies asset data to app documents directory
/// - Normalizes asset paths (handles assets/ prefix automatically)
/// - Single-step progress (no chunked loading for assets)
class AssetSourceHandler implements SourceHandler {
  final AssetLoader assetLoader;
  final FileSystemService fileSystem;
  final ModelRepository repository;

  AssetSourceHandler({
    required this.assetLoader,
    required this.fileSystem,
    required this.repository,
  });

  @override
  bool supports(ModelSource source) => source is AssetSource;

  @override
  Future<void> install(ModelSource source) async {
    if (source is! AssetSource) {
      throw ArgumentError('AssetSourceHandler only supports AssetSource');
    }

    // Load asset data
    final assetData = await assetLoader.loadAsset(source.normalizedPath);

    // Generate filename from path
    final filename = path.basename(source.path);
    final targetPath = await fileSystem.getTargetPath(filename);

    // Write asset data to file system
    await fileSystem.writeFile(targetPath, assetData);

    // Get file size for metadata
    final sizeBytes = await fileSystem.getFileSize(targetPath);

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
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
    if (source is! AssetSource) {
      throw ArgumentError('AssetSourceHandler only supports AssetSource');
    }

    // Load asset data
    final assetData = await assetLoader.loadAsset(source.normalizedPath);

    // Generate filename from path
    final filename = path.basename(source.path);
    final targetPath = await fileSystem.getTargetPath(filename);

    // Write asset data to file system
    await fileSystem.writeFile(targetPath, assetData);

    // Assets don't support chunked loading, so report 100% after completion
    yield 100;

    // Get file size for metadata
    final sizeBytes = await fileSystem.getFileSize(targetPath);

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
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
    // Assets are loaded in a single operation, cannot be resumed
    return false;
  }
}
