import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/mobile/flutter_gemma_mobile.dart';
import 'package:flutter_gemma_example/models/embedding_model.dart' as ExampleEmbeddingModel;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmbeddingModelDownloadService {
  final ExampleEmbeddingModel.EmbeddingModel model;

  EmbeddingModelDownloadService({
    required this.model,
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

  /// Helper method to get the model file path.
  Future<String> getModelFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${model.filename}';
  }

  /// Helper method to get the tokenizer file path.
  Future<String> getTokenizerFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${model.tokenizerFilename}';
  }

  /// Checks if both model and tokenizer files exist and match remote file sizes.
  Future<bool> checkModelExistence(String token) async {
    try {
      // First check via unified system (which handles SharedPreferences correctly)
      final spec = MobileModelManager.createEmbeddingSpec(
        name: model.displayName,
        modelUrl: model.url,
        tokenizerUrl: model.tokenizerUrl,
      );

      final manager = FlutterGemmaPlugin.instance.modelManager;
      final isInstalled = await manager.isModelInstalled(spec);

      if (isInstalled) {
        return true;
      }

      // Fallback: check physical file existence with size validation
      final modelFilePath = await getModelFilePath();
      final tokenizerFilePath = await getTokenizerFilePath();
      final modelFile = File(modelFilePath);
      final tokenizerFile = File(tokenizerFilePath);

      // Both files must exist
      if (!await modelFile.exists() || !await tokenizerFile.exists()) {
        return false;
      }

      final Map<String, String> headers = token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};

      // Check model file size
      final modelHeadResponse = await http.head(Uri.parse(model.url), headers: headers);
      if (modelHeadResponse.statusCode == 200) {
        final modelContentLengthHeader = modelHeadResponse.headers['content-length'];
        if (modelContentLengthHeader != null) {
          final remoteModelSize = int.parse(modelContentLengthHeader);
          final localModelSize = await modelFile.length();
          if (remoteModelSize != localModelSize) {
            return false;
          }
        }
      }

      // Check tokenizer file size
      final tokenizerHeadResponse = await http.head(Uri.parse(model.tokenizerUrl), headers: headers);
      if (tokenizerHeadResponse.statusCode == 200) {
        final tokenizerContentLengthHeader = tokenizerHeadResponse.headers['content-length'];
        if (tokenizerContentLengthHeader != null) {
          final remoteTokenizerSize = int.parse(tokenizerContentLengthHeader);
          final localTokenizerSize = await tokenizerFile.length();
          if (remoteTokenizerSize != localTokenizerSize) {
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking model existence: $e');
      }
      return false;
    }
  }

  /// Downloads both model and tokenizer with progress tracking using plugin methods.
  /// 
  /// [onProgress] callback receives (modelProgress, tokenizerProgress) as doubles 0-100
  Future<void> downloadModel(
    String token,
    void Function(double modelProgress, double tokenizerProgress) onProgress,
  ) async {
    try {
      if (kIsWeb) {
        throw UnsupportedError('Embedding model download is not supported on web platform');
      }
      


      // Use plugin's unified model manager with new API
      final mobileManager = FlutterGemmaPlugin.instance.modelManager as MobileModelManager;

      // Create embedding model spec
      final spec = MobileModelManager.createEmbeddingSpec(
        name: model.displayName,
        modelUrl: model.url,
        tokenizerUrl: model.tokenizerUrl,
      );

      final downloadStream = mobileManager.downloadModelWithProgress(
        spec,
        token: model.needsAuth && token.isNotEmpty ? token : null,
      );

      // Track download progress
      await for (final progress in downloadStream) {
        final progressValue = progress.overallProgress.toDouble();
        onProgress(progressValue, progressValue); // Same progress for both indicators
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error downloading embedding model: $e');
      }
      rethrow;
    }
  }

  /// Deletes both downloaded files using plugin methods.
  Future<void> deleteModel() async {
    try {
      // Use plugin's cleanup method to delete embedding models
      if (!kIsWeb) {
        final mobileManager = FlutterGemmaPlugin.instance.modelManager as MobileModelManager;

        // Get all embedding model files and delete them
        final embeddingFiles = await mobileManager.getInstalledModels(ModelManagementType.embedding);
        for (final filename in embeddingFiles) {
          try {
            await ModelFileSystemManager.deleteModelFile(filename);
          } catch (e) {
            if (kDebugMode) {
              print('Failed to delete $filename: $e');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting embedding model: $e');
      }
      // Fallback to manual file deletion if plugin method fails
      try {
        final modelFilePath = await getModelFilePath();
        final tokenizerFilePath = await getTokenizerFilePath();
        final modelFile = File(modelFilePath);
        final tokenizerFile = File(tokenizerFilePath);

        if (await modelFile.exists()) {
          await modelFile.delete();
        }

        if (await tokenizerFile.exists()) {
          await tokenizerFile.delete();
        }
      } catch (fallbackError) {
        if (kDebugMode) {
          print('Fallback deletion also failed: $fallbackError');
        }
      }
    }
  }

  /// Check if the embedding model is installed using plugin methods
  Future<bool> isEmbeddingModelInstalled() async {
    try {
      if (kIsWeb) {
        return false; // Not supported on web
      }
      
      // Use plugin's method to check installation with new API
      final mobileManager = FlutterGemmaPlugin.instance.modelManager as MobileModelManager;
      return await mobileManager.isAnyModelInstalled(ModelManagementType.embedding);
    } catch (e) {
      if (kDebugMode) {
        print('Error checking embedding model installation: $e');
      }
      // Fallback to file existence check
      return await checkModelExistence('');
    }
  }

}