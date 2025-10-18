import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma_example/services/auth_token_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelDownloadService {
  ModelDownloadService({
    required this.modelUrl,
    required this.modelFilename,
    required this.licenseUrl,
    required this.modelType,
    this.fileType = ModelFileType.task,
  });

  final String modelUrl;
  final String modelFilename;
  final String licenseUrl;
  final ModelType modelType;
  final ModelFileType fileType;

  /// Load the token from SharedPreferences.
  Future<String?> loadToken() => AuthTokenService.loadToken();

  /// Save the token to SharedPreferences.
  Future<void> saveToken(String token) => AuthTokenService.saveToken(token);

  /// Helper method to get the file path.
  Future<String> getFilePath() async {
    // Use the same path correction logic as the unified system
    final directory = await getApplicationDocumentsDirectory();
    // Apply Android path correction for consistency with unified download system
    final correctedPath = directory.path.contains('/data/user/0/')
        ? directory.path.replaceFirst('/data/user/0/', '/data/data/')
        : directory.path;
    return '$correctedPath/$modelFilename';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence(String token) async {
    try {
      // Modern API: Check if model is installed
      final isInstalled = await FlutterGemma.isModelInstalled(modelFilename);

      if (isInstalled) {
        return true;
      }

      // Fallback: check physical file existence with size validation
      final filePath = await getFilePath();
      final file = File(filePath);

      // Check remote file size
      final Map<String, String> headers =
          token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
      final headResponse = await http.head(Uri.parse(modelUrl), headers: headers);

      if (headResponse.statusCode == 200) {
        final contentLengthHeader = headResponse.headers['content-length'];
        if (contentLengthHeader != null) {
          final remoteFileSize = int.parse(contentLengthHeader);
          if (file.existsSync() && await file.length() == remoteFileSize) {
            return true;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking model existence: $e');
      }
    }
    return false;
  }

  /// Downloads the model file and tracks progress using Modern API.
  Future<void> downloadModel({
    required String token,
    required Function(double) onProgress,
  }) async {
    try {
      // Convert empty string to null for cleaner API
      final authToken = token.isEmpty ? null : token;

      // Modern API: Install inference model from network with progress tracking
      await FlutterGemma.installModel(
        modelType: modelType,
        fileType: fileType,
      ).fromNetwork(modelUrl, token: authToken).withProgress((progress) {
        onProgress(progress.toDouble());
      }).install();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error downloading model: $e');
      }
      rethrow;
    }
  }

  /// Deletes the downloaded file.
  Future<void> deleteModel() async {
    try {
      final filePath = await getFilePath();
      final file = File(filePath);

      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting model: $e');
      }
    }
  }
}
