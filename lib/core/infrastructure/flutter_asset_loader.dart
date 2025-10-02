import 'package:flutter/services.dart';
import 'package:flutter_gemma/core/services/asset_loader.dart';

/// Flutter asset loader using rootBundle
///
/// Features:
/// - Loads assets from Flutter asset bundle
/// - Works on all platforms (Android, iOS, Web)
/// - Returns binary data as Uint8List
/// - Throws clear exceptions for missing assets
class FlutterAssetLoader implements AssetLoader {
  @override
  Future<Uint8List> loadAsset(String path) async {
    try {
      final ByteData data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    } catch (e) {
      // Asset not found or other error
      throw Exception('Failed to load asset: $path - $e');
    }
  }
}
