import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/handlers/source_handler.dart';
import 'package:flutter_gemma/core/model_management/cancel_token.dart';
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
  Future<void> install(
    ModelSource source, {
    CancelToken? cancelToken,
  }) async {
    // Web assets are instant URL registration, no cancellation needed
    if (source is! AssetSource) {
      throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);

    // Strategy: Create Blob URL from asset (works in debug + production)
    // LiteRT.js doesn't support blob URLs directly, but JS code will convert to ArrayBuffer
    try {
      debugPrint('[WebAssetSourceHandler] Loading asset: ${source.normalizedPath}');

      // Load asset via rootBundle
      final ByteData data = await rootBundle.load(source.normalizedPath);
      final Uint8List bytes = data.buffer.asUint8List();

      debugPrint('[WebAssetSourceHandler] Asset loaded: ${bytes.length} bytes');

      // Create Blob URL
      final blobUrl = await _createBlobUrlFromBytes(bytes, filename);

      debugPrint('[WebAssetSourceHandler] Blob URL created: $blobUrl');

      // Register Blob URL
      fileSystem.registerUrl(filename, blobUrl);
    } catch (e) {
      debugPrint('[WebAssetSourceHandler] ❌ Failed to load asset: $e');
      rethrow;
    }

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1,
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  }

  /// Creates a Blob URL from byte data
  Future<String> _createBlobUrlFromBytes(Uint8List bytes, String filename) async {
    debugPrint('[WebAssetSourceHandler] Creating blob from ${bytes.length} bytes');

    // Create JSArray with single chunk
    final jsChunks = [bytes.toJS].toJS;

    final options = {
      'type': 'application/octet-stream',
    }.jsify()!;

    // Invoke Blob constructor
    final blobConstructor = globalContext['Blob'] as JSFunction;
    final blob = blobConstructor.callAsConstructor(jsChunks, options);

    // Create blob URL
    final blobUrl = _createObjectURL(blob);

    debugPrint('[WebAssetSourceHandler] Blob URL created: $blobUrl');

    return blobUrl;
  }

  /// Creates object URL from blob
  String _createObjectURL(JSAny blob) {
    final urlApi = globalContext['URL'] as JSObject;
    final createObjectURL = urlApi['createObjectURL'] as JSFunction;
    final blobUrl = createObjectURL.callAsFunction(urlApi, blob) as JSString;
    return blobUrl.toDart;
  }

  @override
  Stream<int> installWithProgress(
    ModelSource source, {
    CancelToken? cancelToken,
  }) async* {
    // Same as install() but with progress tracking
    if (source is! AssetSource) {
      throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
    }

    // Generate filename from path
    final filename = path.basename(source.path);

    // Progress: Loading asset
    yield 0;
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      debugPrint('[WebAssetSourceHandler] Loading asset with progress: ${source.normalizedPath}');

      // Load asset data via rootBundle
      yield 33;
      final ByteData data = await rootBundle.load(source.normalizedPath);
      final Uint8List bytes = data.buffer.asUint8List();

      debugPrint('[WebAssetSourceHandler] Asset loaded: ${bytes.length} bytes');

      // Create Blob URL from bytes
      yield 66;
      final blobUrl = await _createBlobUrlFromBytes(bytes, filename);

      debugPrint('[WebAssetSourceHandler] Blob URL created: $blobUrl');

      // Register Blob URL with WebFileSystemService
      fileSystem.registerUrl(filename, blobUrl);

      yield 100;
    } catch (e) {
      debugPrint('[WebAssetSourceHandler] ❌ Failed to load asset: $e');
      rethrow;
    }

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1,
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
