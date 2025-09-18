import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelDownloadService {
  final String modelUrl;
  final String modelFilename;
  final String licenseUrl;

  ModelDownloadService({
    required this.modelUrl,
    required this.modelFilename,
    required this.licenseUrl,
  });

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

  /// Helper method to get the file path.
  Future<String> getFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$modelFilename';
  }

  /// Checks if the model file exists and matches the remote file size.
  Future<bool> checkModelExistence(String token) async {
    try {
      final filePath = await getFilePath();
      final file = File(filePath);

      // Check remote file size
      final Map<String, String> headers = token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
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
        print('Error checking model existence: $e');
      }
    }
    return false;
  }

  /// Downloads the model file and tracks progress.
  Future<void> downloadModel({
    required String token,
    required Function(double) onProgress,
  }) async {
    try {
      final stream = FlutterGemmaPlugin.instance.modelManager.downloadModelFromNetworkWithProgress(modelUrl, token: token);

      // Wait for stream to complete - same logic as original but with new downloader
      await for (final progress in stream) {
        // Keep progress as 0-100 (double)
        onProgress(progress.toDouble());
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading model: $e');
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
        print('Error deleting model: $e');
      }
    }
  }
}
