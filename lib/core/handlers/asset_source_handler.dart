import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
import 'package:flutter_gemma/core/services/asset_loader.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';
import 'package:flutter_gemma/core/infrastructure/flutter_asset_loader_stub.dart'
    if (dart.library.io) 'package:flutter_gemma/core/infrastructure/flutter_asset_loader.dart';
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
  Future<void> install(
    ModelSource source, {
    CancelToken? cancelToken,
  }) async {
    // No changes to logic - just add parameter for interface compliance
    // Asset copies are fast (<30s), cancellation not critical
    if (source is! AssetSource) {
      throw ArgumentError('AssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);
    final targetPath = await fileSystem.getTargetPath(filename);

    // Copy asset file directly using LargeFileHandler (no memory loading!).
    // Pass the absolute targetPath because the Android plugin treats it as a
    // literal `File(...)` relative to the JVM cwd otherwise (#250).
    // Falls back to in-memory loadAsset → writeFile on platforms where
    // large_file_handler doesn't ship a plugin (macOS / Windows / Linux —
    // it only declares Android + iOS), and on web (FlutterAssetLoader stub).
    if (assetLoader is FlutterAssetLoader) {
      try {
        await (assetLoader as FlutterAssetLoader).copyAssetToFile(
          source.pathForLookupKey,
          targetPath,
        );
      } on MissingPluginException {
        final assetData = await assetLoader.loadAsset(source.pathForLookupKey);
        await fileSystem.writeFile(targetPath, assetData);
      }
    } else {
      // Fallback for other loaders (testing, web stub)
      final assetData = await assetLoader.loadAsset(source.pathForLookupKey);
      await fileSystem.writeFile(targetPath, assetData);
    }

    // Get size for metadata (after file is copied)
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
  Stream<int> installWithProgress(
    ModelSource source, {
    CancelToken? cancelToken,
  }) async* {
    // Same as above - add parameter but don't use it
    // Asset copies are fast (<30s), cancellation not critical
    if (source is! AssetSource) {
      throw ArgumentError('AssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);
    final targetPath = await fileSystem.getTargetPath(filename);

    // Copy asset file with REAL progress tracking (LargeFileHandler).
    // Same fixes as install() above (#250): pass absolute targetPath and
    // fall back to in-memory copy when the plugin is missing (desktop / web).
    if (assetLoader is FlutterAssetLoader) {
      try {
        await for (final progress in (assetLoader as FlutterAssetLoader)
            .copyAssetToFileWithProgress(source.pathForLookupKey, targetPath)) {
          yield progress;
        }
      } on MissingPluginException {
        final assetData = await assetLoader.loadAsset(source.pathForLookupKey);
        await fileSystem.writeFile(targetPath, assetData);
        yield 100;
      }
    } else {
      final assetData = await assetLoader.loadAsset(source.pathForLookupKey);
      await fileSystem.writeFile(targetPath, assetData);
      yield 100;
    }

    // Get size for metadata (after file is copied)
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
