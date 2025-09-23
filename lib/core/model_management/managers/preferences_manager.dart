part of '../../../mobile/flutter_gemma_mobile.dart';

/// Unified SharedPreferences operations for model management
class ModelPreferencesManager {
  static final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  /// Saves model files using new multi-model list system
  static Future<void> saveModelFiles(ModelSpec spec) async {
    try {
      final prefs = await _prefs;

      debugPrint('Saving model files for: ${spec.name} with policy: ${spec.replacePolicy}');

      if (spec.replacePolicy == ModelReplacePolicy.replace) {
        // Replace: clear ALL models of this type
        await _clearAllModelsOfType(spec.type, prefs);
      }

      // Add files to appropriate lists
      await _addFilesToLists(spec, prefs);

      debugPrint('Saved model files to lists: ${spec.name} (${spec.files.length} files)');
    } catch (e) {
      debugPrint('Failed to save model files for ${spec.name}: $e');
      throw ModelStorageException(
        'Failed to save model files',
        e,
        'save_files',
      );
    }
  }

  /// Removes all files of a model specification from SharedPreferences
  static Future<void> clearModelFiles(ModelSpec spec) async {
    try {
      final prefs = await _prefs;

      final operations = <Future<bool>>[];

      for (final file in spec.files) {
        operations.add(prefs.remove(file.prefsKey));
      }

      await Future.wait(operations);
      debugPrint('Cleared model files from SharedPreferences: ${spec.name}');
    } catch (e) {
      debugPrint('Failed to clear model files for ${spec.name}: $e');
      throw ModelStorageException(
        'Failed to clear model files from SharedPreferences',
        e,
        'clear_prefs',
      );
    }
  }

  /// Gets all installed files for a specific model type
  static Future<List<String>> getInstalledFiles(ModelManagementType type) async {
    try {
      final prefs = await _prefs;
      final keys = _getPrefsKeysForType(type);

      final installedFiles = <String>[];

      for (final key in keys) {
        final filename = prefs.getString(key);
        if (filename != null) {
          installedFiles.add(filename);
        }
      }

      return installedFiles;
    } catch (e) {
      debugPrint('Failed to get installed files for type $type: $e');
      return [];
    }
  }

  /// Gets all protected files from multi-model lists
  static Future<List<String>> getAllProtectedFiles() async {
    try {
      final prefs = await _prefs;
      final protectedFiles = <String>[];

      // Get files from new multi-model lists
      final keys = _getAllModelPrefsKeys();
      for (final key in keys) {
        final filesList = prefs.getStringList(key);
        if (filesList != null) {
          protectedFiles.addAll(filesList);
        }
      }

      debugPrint('Protected ${protectedFiles.length} model files from multi-model lists');
      return protectedFiles;
    } catch (e) {
      debugPrint('Failed to get protected files: $e');
      return [];
    }
  }

  /// Checks if a specific model specification is currently installed
  static Future<bool> isModelInstalled(ModelSpec spec) async {
    try {
      final prefs = await _prefs;

      // Check if ALL files of this spec are in the appropriate lists
      for (final file in spec.files) {
        final isFileInstalled = _isFileInLists(prefs, file);
        if (!isFileInstalled) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Failed to check if model is installed: ${spec.name}: $e');
      return false;
    }
  }

  /// Checks if ANY model of the given type is installed
  static Future<bool> isAnyModelInstalled(ModelManagementType type) async {
    try {
      final prefs = await _prefs;

      switch (type) {
        case ModelManagementType.inference:
          final models = prefs.getStringList('installed_models') ?? <String>[];
          return models.isNotEmpty;
        case ModelManagementType.embedding:
          final models = prefs.getStringList('installed_embedding_models') ?? <String>[];
          final tokenizers = prefs.getStringList('installed_tokenizers') ?? <String>[];
          return models.isNotEmpty && tokenizers.isNotEmpty;
      }
    } catch (e) {
      debugPrint('Failed to check if any model is installed: $e');
      return false;
    }
  }

  /// Helper to check if a file is in the appropriate lists
  static bool _isFileInLists(SharedPreferences prefs, ModelFile file) {
    switch (file.prefsKey) {
      case 'installed_model_file_name':
        final models = prefs.getStringList('installed_models') ?? <String>[];
        return models.contains(file.filename);
      case 'installed_lora_file_name':
        final loras = prefs.getStringList('installed_loras') ?? <String>[];
        return loras.contains(file.filename);
      case 'embedding_model_file':
        final models = prefs.getStringList('installed_embedding_models') ?? <String>[];
        return models.contains(file.filename);
      case 'embedding_tokenizer_file':
        final tokenizers = prefs.getStringList('installed_tokenizers') ?? <String>[];
        return tokenizers.contains(file.filename);
      default:
        return false;
    }
  }

  /// Loads a model specification from SharedPreferences if it exists
  static Future<ModelSpec?> loadModelSpec(ModelManagementType type, String expectedName) async {
    try {
      final prefs = await _prefs;

      switch (type) {
        case ModelManagementType.inference:
          final modelFilename = prefs.getString('installed_model_file_name');
          final loraFilename = prefs.getString('installed_lora_file_name');

          if (modelFilename != null) {
            // Create a basic spec from saved data
            return InferenceModelSpec(
              name: expectedName,
              modelUrl: 'local://$modelFilename', // Placeholder URL
              loraUrl: loraFilename != null ? 'local://$loraFilename' : null,
            );
          }
          break;

        case ModelManagementType.embedding:
          final modelFilename = prefs.getString('embedding_model_file');
          final tokenizerFilename = prefs.getString('embedding_tokenizer_file');

          if (modelFilename != null && tokenizerFilename != null) {
            return EmbeddingModelSpec(
              name: expectedName,
              modelUrl: 'local://$modelFilename', // Placeholder URL
              tokenizerUrl: 'local://$tokenizerFilename',
            );
          }
          break;
      }

      return null;
    } catch (e) {
      debugPrint('Failed to load model spec for $type/$expectedName: $e');
      return null;
    }
  }

  /// Gets SharedPreferences keys for a specific model type
  static List<String> _getPrefsKeysForType(ModelManagementType type) {
    switch (type) {
      case ModelManagementType.inference:
        return ['installed_model_file_name', 'installed_lora_file_name'];
      case ModelManagementType.embedding:
        return ['embedding_model_file', 'embedding_tokenizer_file'];
    }
  }

  /// Gets all SharedPreferences keys used for model storage (new multi-model system)
  static List<String> _getAllModelPrefsKeys() {
    return [
      'installed_models',              // List<String> of inference model files
      'installed_loras',               // List<String> of LoRA files
      'installed_embedding_models',    // List<String> of embedding model files
      'installed_embedding_tokenizers', // List<String> of tokenizer files
    ];
  }

  /// Legacy keys for migration (old single-model system)
  static List<String> _getLegacyModelPrefsKeys() {
    return [
      'installed_model_file_name',
      'installed_lora_file_name',
      'embedding_model_file',
      'embedding_tokenizer_file',
    ];
  }


  /// Migrates old preferences format to new format if needed
  static Future<void> migrateOldPreferences() async {
    await _migrateToMultiModelSystem();
  }

  /// Migrates from single-model to multi-model SharedPreferences structure
  static Future<void> _migrateToMultiModelSystem() async {
    try {
      final prefs = await _prefs;

      // Check if migration is needed (if any legacy keys exist)
      final legacyKeys = _getLegacyModelPrefsKeys();
      bool needsMigration = false;
      for (final key in legacyKeys) {
        if (prefs.containsKey(key)) {
          needsMigration = true;
          break;
        }
      }

      if (!needsMigration) return;

      debugPrint('Migrating to multi-model system...');

      // Migrate inference model
      final oldModel = prefs.getString('installed_model_file_name');
      if (oldModel != null) {
        await prefs.setStringList('installed_models', [oldModel]);
        await prefs.remove('installed_model_file_name');
        debugPrint('Migrated inference model: $oldModel');
      }

      // Migrate LoRA
      final oldLora = prefs.getString('installed_lora_file_name');
      if (oldLora != null) {
        await prefs.setStringList('installed_loras', [oldLora]);
        await prefs.remove('installed_lora_file_name');
        debugPrint('Migrated LoRA: $oldLora');
      }

      // Migrate embedding model
      final oldEmbeddingModel = prefs.getString('embedding_model_file');
      if (oldEmbeddingModel != null) {
        await prefs.setStringList('installed_embedding_models', [oldEmbeddingModel]);
        await prefs.remove('embedding_model_file');
        debugPrint('Migrated embedding model: $oldEmbeddingModel');
      }

      // Migrate embedding tokenizer
      final oldTokenizer = prefs.getString('embedding_tokenizer_file');
      if (oldTokenizer != null) {
        await prefs.setStringList('installed_embedding_tokenizers', [oldTokenizer]);
        await prefs.remove('embedding_tokenizer_file');
        debugPrint('Migrated tokenizer: $oldTokenizer');
      }

      // Ensure we have the replace policy setting
      if (!prefs.containsKey('model_replace_policy')) {
        await prefs.setBool('model_replace_policy', false); // Default to keep
      }

      debugPrint('Migration completed (legacy support)');
    } catch (e) {
      debugPrint('Failed to migrate preferences: $e');
      // Don't rethrow - migration failures should not break the app
    }
  }

  /// Clears all models of a specific type from lists (replace policy)
  static Future<void> _clearAllModelsOfType(ModelManagementType type, SharedPreferences prefs) async {
    switch (type) {
      case ModelManagementType.inference:
        await prefs.remove('installed_models');
        await prefs.remove('installed_loras');
        debugPrint('Cleared all inference models and LoRAs');
        break;
      case ModelManagementType.embedding:
        await prefs.remove('installed_embedding_models');
        await prefs.remove('installed_tokenizers');
        debugPrint('Cleared all embedding models and tokenizers');
        break;
    }
  }

  /// Adds model files to appropriate lists
  static Future<void> _addFilesToLists(ModelSpec spec, SharedPreferences prefs) async {
    switch (spec.type) {
      case ModelManagementType.inference:
        // Add inference model
        final modelFile = spec.files.where((f) => f.prefsKey == 'installed_model_file_name').firstOrNull;
        if (modelFile != null) {
          final models = prefs.getStringList('installed_models') ?? <String>[];
          if (!models.contains(modelFile.filename)) {
            models.add(modelFile.filename);
            await prefs.setStringList('installed_models', models);
          }
        }

        // Add LoRA if present
        final loraFile = spec.files.where((f) => f.prefsKey == 'installed_lora_file_name').firstOrNull;
        if (loraFile != null) {
          final loras = prefs.getStringList('installed_loras') ?? <String>[];
          if (!loras.contains(loraFile.filename)) {
            loras.add(loraFile.filename);
            await prefs.setStringList('installed_loras', loras);
          }
        }
        break;

      case ModelManagementType.embedding:
        // Add embedding model
        final modelFile = spec.files.where((f) => f.prefsKey == 'embedding_model_file').firstOrNull;
        if (modelFile != null) {
          final models = prefs.getStringList('installed_embedding_models') ?? <String>[];
          if (!models.contains(modelFile.filename)) {
            models.add(modelFile.filename);
            await prefs.setStringList('installed_embedding_models', models);
          }
        }

        // Add tokenizer
        final tokenizerFile = spec.files.where((f) => f.prefsKey == 'embedding_tokenizer_file').firstOrNull;
        if (tokenizerFile != null) {
          final tokenizers = prefs.getStringList('installed_tokenizers') ?? <String>[];
          if (!tokenizers.contains(tokenizerFile.filename)) {
            tokenizers.add(tokenizerFile.filename);
            await prefs.setStringList('installed_tokenizers', tokenizers);
          }
        }
        break;
    }

    debugPrint('Added model files to lists for: ${spec.name}');
  }

  /// Gets all installed model files for a specific type
  static Future<List<String>> getInstalledModels(ModelManagementType type) async {
    try {
      final prefs = await _prefs;
      final files = <String>[];

      switch (type) {
        case ModelManagementType.inference:
          final models = prefs.getStringList('installed_models') ?? <String>[];
          final loras = prefs.getStringList('installed_loras') ?? <String>[];
          files.addAll(models);
          files.addAll(loras);
          break;
        case ModelManagementType.embedding:
          final models = prefs.getStringList('installed_embedding_models') ?? <String>[];
          final tokenizers = prefs.getStringList('installed_tokenizers') ?? <String>[];
          files.addAll(models);
          files.addAll(tokenizers);
          break;
      }

      return files;
    } catch (e) {
      debugPrint('Failed to get installed models: $e');
      return [];
    }
  }

  /// Removes a specific model from the lists
  static Future<void> removeModelFromLists(ModelSpec spec) async {
    try {
      final prefs = await _prefs;

      for (final file in spec.files) {
        switch (file.prefsKey) {
          case 'installed_model_file_name':
            final models = prefs.getStringList('installed_models') ?? <String>[];
            models.remove(file.filename);
            await prefs.setStringList('installed_models', models);
            break;
          case 'installed_lora_file_name':
            final loras = prefs.getStringList('installed_loras') ?? <String>[];
            loras.remove(file.filename);
            await prefs.setStringList('installed_loras', loras);
            break;
          case 'embedding_model_file':
            final models = prefs.getStringList('installed_embedding_models') ?? <String>[];
            models.remove(file.filename);
            await prefs.setStringList('installed_embedding_models', models);
            break;
          case 'embedding_tokenizer_file':
            final tokenizers = prefs.getStringList('installed_tokenizers') ?? <String>[];
            tokenizers.remove(file.filename);
            await prefs.setStringList('installed_tokenizers', tokenizers);
            break;
        }
      }

      debugPrint('Removed model from lists: ${spec.name}');
    } catch (e) {
      debugPrint('Failed to remove model from lists: $e');
    }
  }
}