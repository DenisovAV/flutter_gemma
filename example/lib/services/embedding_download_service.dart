import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/domain/model_source.dart'; // For ModelSource
import 'package:flutter_gemma/core/utils/file_name_utils.dart'; // For FileNameUtils
import 'package:flutter_gemma/flutter_gemma.dart'; // For EmbeddingModelSpec
import 'package:flutter_gemma_example/models/embedding_model.dart' as example_embedding_model;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmbeddingModelDownloadService {
  final example_embedding_model.EmbeddingModel model;

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
      // Modern API: Check if embedding model spec is installed
      final manager = FlutterGemmaPlugin.instance.modelManager;

      // Create spec to check
      final spec = EmbeddingModelSpec(
        name: FileNameUtils.getBaseName(model.filename),
        modelSource: ModelSource.network(model.url, authToken: token.isEmpty ? null : token),
        tokenizerSource: ModelSource.network(model.tokenizerUrl, authToken: token.isEmpty ? null : token),
      );

      final installed = await manager.isModelInstalled(spec);
      if (installed) {
        debugPrint('[EmbeddingDownloadService] Model ${spec.name} is installed');
        return true;
      }

      debugPrint('[EmbeddingDownloadService] Model ${spec.name} is NOT installed');
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking model existence: $e');
      }
      return false;
    }
  }

  /// Downloads both model and tokenizer with progress tracking using Modern API.
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

      // Convert empty string to null for cleaner API
      final authToken = token.isEmpty ? null : token;

      double modelProgress = 0;
      double tokenizerProgress = 0;

      // Modern API: Download both model and tokenizer using installEmbedder
      await FlutterGemma.installEmbedder()
          .modelFromNetwork(model.url, token: authToken)
          .tokenizerFromNetwork(model.tokenizerUrl, token: authToken)
          .withModelProgress((progress) {
            modelProgress = progress.toDouble();
            onProgress(modelProgress, tokenizerProgress);
          })
          .withTokenizerProgress((progress) {
            tokenizerProgress = progress.toDouble();
            onProgress(modelProgress, tokenizerProgress);
          })
          .install();

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error downloading embedding model: $e');
      }
      rethrow;
    }
  }

  /// Deletes both downloaded files.
  Future<void> deleteModel() async {
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
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting embedding model: $e');
      }
    }
  }

  /// Check if the embedding model is installed
  Future<bool> isEmbeddingModelInstalled() async {
    try {
      if (kIsWeb) {
        return false; // Not supported on web
      }

      // Modern API: Check if both files are installed
      final modelInstalled = await FlutterGemma.isModelInstalled(model.filename);
      final tokenizerInstalled = await FlutterGemma.isModelInstalled(model.tokenizerFilename);
      return modelInstalled && tokenizerInstalled;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking embedding model installation: $e');
      }
      // Fallback to file existence check
      return await checkModelExistence('');
    }
  }

}