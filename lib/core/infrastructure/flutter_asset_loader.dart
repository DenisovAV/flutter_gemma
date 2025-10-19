import 'dart:typed_data';
import 'package:flutter_gemma/core/services/asset_loader.dart';
import 'package:large_file_handler/large_file_handler.dart';

/// Flutter asset loader using LargeFileHandler plugin
///
/// Features:
/// - Loads assets using native platform code (iOS/Android)
/// - Handles LARGE files efficiently (290MB+) without loading into memory
/// - Copies files in chunks, avoiding memory issues
/// - Works on all platforms (Android, iOS, Web)
class FlutterAssetLoader implements AssetLoader {
  final _handler = LargeFileHandler();

  @override
  Future<Uint8List> loadAsset(String path) async {
    try {
      // LargeFileHandler doesn't return bytes, it copies files
      // For the AssetLoader interface, we need to read after copy
      // But this is still memory-intensive for large files
      // Better approach: change AssetSourceHandler to use copyAssetToLocalStorage directly
      throw UnimplementedError('FlutterAssetLoader.loadAsset() is deprecated for large files. '
          'Use copyAssetToFile() instead or call LargeFileHandler directly.');
    } catch (e) {
      throw Exception('Failed to load asset: $path - $e');
    }
  }

  /// Copies asset file directly to target path using LargeFileHandler
  /// This is the CORRECT way to handle large files
  Future<void> copyAssetToFile(String assetPath, String targetPath) async {
    try {
      await _handler.copyAssetToLocalStorage(
        assetName: assetPath,
        targetPath: targetPath,
      );
    } catch (e) {
      throw Exception('Failed to copy asset: $assetPath - $e');
    }
  }

  /// Copies asset with progress tracking
  Stream<int> copyAssetToFileWithProgress(String assetPath, String targetPath) {
    return _handler.copyAssetToLocalStorageWithProgress(
      assetName: assetPath,
      targetPath: targetPath,
    );
  }
}
