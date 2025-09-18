import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelDownloadService {
  ModelDownloadService({
    required this.modelUrl,
    required this.modelFilename,
    required this.licenseUrl,
  });

  final String modelUrl;
  final String modelFilename;
  final String licenseUrl;

  /// Load the token from SharedPreferences.
  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Save the token to SharedPreferences.
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Clear the token from SharedPreferences.
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  /// Check if the model exists
  Future<bool> checkModelExistence(String token) async {
    return await FlutterGemmaPlugin.instance.modelManager.isModelInstalled;
  }

  /// Download the model with progress tracking
  Future<void> downloadModel({
    required String token,
    Function(double)? onProgress,
  }) async {
    final plugin = FlutterGemmaPlugin.instance;

    // Set the model path first
    await plugin.modelManager.setModelPath(modelUrl);

    // Download with progress tracking
    await for (final progress in plugin.modelManager.downloadModelFromNetworkWithProgress(
      modelUrl,
      token: token.isNotEmpty ? token : null
    )) {
      onProgress?.call(progress.toDouble());
    }
  }

  /// Delete the model
  Future<void> deleteModel() async {
    await FlutterGemmaPlugin.instance.modelManager.deleteModel();
  }
}