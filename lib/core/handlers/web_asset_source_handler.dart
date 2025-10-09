import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/infrastructure/web_file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';
import 'package:path/path.dart' as path;

/// Handles installation of models from Flutter assets on web platform
///
/// On web, Flutter assets are served by the web server at paths like:
/// - assets/models/gemma.task
/// - assets/lora/weights.bin
///
/// This handler:
/// 1. Registers the asset URL with WebFileSystemService
/// 2. Saves metadata to ModelRepository
/// 3. MediaPipe loads directly from the URL (no file copy)
///
/// Features:
/// - No file copying (web has no local file system)
/// - Direct URL registration for MediaPipe
/// - Simulated progress for UX consistency
/// - Instant "installation" (assets already bundled)
///
/// Platform: Web only
class WebAssetSourceHandler implements SourceHandler {
  final WebFileSystemService fileSystem;
  final ModelRepository repository;

  WebAssetSourceHandler({
    required this.fileSystem,
    required this.repository,
  });

  @override
  bool supports(ModelSource source) => source is AssetSource;

  @override
  Future<void> install(ModelSource source) async {
    if (source is! AssetSource) {
      throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);

    // Register asset URL with WebFileSystemService
    // normalizedPath includes 'assets/' prefix (e.g., 'assets/models/file.task')
    // This is the URL path where the web server serves the asset
    fileSystem.registerUrl(filename, source.normalizedPath);

    // Save metadata to repository
    // Note: Web can't determine file size without HTTP HEAD request
    // Use -1 to indicate "unknown but exists"
    final modelInfo = ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web assets
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  @override
  Stream<int> installWithProgress(ModelSource source) async* {
    if (source is! AssetSource) {
      throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);

    // Simulate progress for UX consistency
    // Assets are already bundled with the app, so this is instant
    yield 0;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 50;
    await Future.delayed(const Duration(milliseconds: 50));

    // Register asset URL with WebFileSystemService
    fileSystem.registerUrl(filename, source.normalizedPath);

    yield 100;

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web assets
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  @override
  bool supportsResume(ModelSource source) {
    // Assets are bundled with the app, no download/resume needed
    return false;
  }
}
