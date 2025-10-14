import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_gemma/core/di/service_registry.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/services/model_repository.dart' as repo;

/// Migrates old Legacy preference keys to Modern ModelRepository
///
/// This is an OPTIONAL migration tool for users upgrading from old versions.
/// Does NOT run automatically - must be called explicitly by the user.
///
/// Usage:
/// ```dart
/// final migrator = LegacyPreferencesMigrator();
/// final result = await migrator.migrate();
/// print('Migrated ${result.migratedCount} models');
/// ```
class LegacyPreferencesMigrator {
  /// Checks if migration has already been completed
  Future<bool> isMigrationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('_migration_completed_v1') == true;
  }

  /// Checks if there are any Legacy preferences to migrate
  Future<bool> hasLegacyPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final installedModels = prefs.getStringList('installed_models') ?? [];
    final installedLoras = prefs.getStringList('installed_loras') ?? [];
    final installedEmbedding = prefs.getStringList('installed_embedding_models') ?? [];
    final installedTokenizers = prefs.getStringList('installed_tokenizers') ?? [];

    return installedModels.isNotEmpty ||
        installedLoras.isNotEmpty ||
        installedEmbedding.isNotEmpty ||
        installedTokenizers.isNotEmpty;
  }

  /// Performs the migration
  ///
  /// Returns [MigrationResult] with details about migrated files.
  /// Throws exception if migration fails critically.
  Future<MigrationResult> migrate({bool forceRemigration = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final registry = ServiceRegistry.instance;
      final repository = registry.modelRepository;

      debugPrint('🔄 Starting Legacy preferences migration...');

      // Check if migration already done
      if (!forceRemigration && await isMigrationCompleted()) {
        debugPrint('✅ Migration already completed, skipping');
        return MigrationResult(
          migratedCount: 0,
          skippedCount: 0,
          errors: [],
          alreadyCompleted: true,
        );
      }

      int migratedCount = 0;
      int skippedCount = 0;
      final errors = <String>[];

      // 1. Migrate inference models from 'installed_models'
      final installedModels = prefs.getStringList('installed_models') ?? [];
      for (final filename in installedModels) {
        try {
          await _migrateFile(
            filename: filename,
            prefs: prefs,
            repository: repository,
            type: repo.ModelType.inference,
            hasLoraWeights: false,
          );
          migratedCount++;
          debugPrint('✅ Migrated inference model: $filename');
        } catch (e) {
          errors.add('Failed to migrate inference model $filename: $e');
          skippedCount++;
          debugPrint('⚠️  Failed to migrate $filename: $e');
        }
      }

      // 2. Migrate LoRA weights from 'installed_loras'
      final installedLoras = prefs.getStringList('installed_loras') ?? [];
      for (final filename in installedLoras) {
        try {
          await _migrateFile(
            filename: filename,
            prefs: prefs,
            repository: repository,
            type: repo.ModelType.inference,
            hasLoraWeights: true,
          );
          migratedCount++;
          debugPrint('✅ Migrated LoRA weights: $filename');
        } catch (e) {
          errors.add('Failed to migrate LoRA $filename: $e');
          skippedCount++;
          debugPrint('⚠️  Failed to migrate $filename: $e');
        }
      }

      // 3. Migrate embedding models from 'installed_embedding_models'
      final installedEmbedding = prefs.getStringList('installed_embedding_models') ?? [];
      for (final filename in installedEmbedding) {
        try {
          await _migrateFile(
            filename: filename,
            prefs: prefs,
            repository: repository,
            type: repo.ModelType.embedding,
            hasLoraWeights: false,
          );
          migratedCount++;
          debugPrint('✅ Migrated embedding model: $filename');
        } catch (e) {
          errors.add('Failed to migrate embedding model $filename: $e');
          skippedCount++;
          debugPrint('⚠️  Failed to migrate $filename: $e');
        }
      }

      // 4. Migrate tokenizers from 'installed_tokenizers'
      final installedTokenizers = prefs.getStringList('installed_tokenizers') ?? [];
      for (final filename in installedTokenizers) {
        try {
          await _migrateFile(
            filename: filename,
            prefs: prefs,
            repository: repository,
            type: repo.ModelType.embedding,
            hasLoraWeights: false,
          );
          migratedCount++;
          debugPrint('✅ Migrated tokenizer: $filename');
        } catch (e) {
          errors.add('Failed to migrate tokenizer $filename: $e');
          skippedCount++;
          debugPrint('⚠️  Failed to migrate $filename: $e');
        }
      }

      // 5. Clean up old Legacy keys
      if (migratedCount > 0) {
        await _cleanupLegacyKeys(prefs);
        debugPrint('🧹 Cleaned up old Legacy preference keys');
      }

      // Mark migration as completed
      await prefs.setBool('_migration_completed_v1', true);

      debugPrint('✅ Migration completed! Migrated: $migratedCount, Skipped: $skippedCount');

      return MigrationResult(
        migratedCount: migratedCount,
        skippedCount: skippedCount,
        errors: errors,
        alreadyCompleted: false,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Migration failed critically: $e');
      debugPrint('Stack trace: $stackTrace');
      throw MigrationException('Migration failed: $e', e, stackTrace);
    }
  }

  /// Migrates a single file
  Future<void> _migrateFile({
    required String filename,
    required SharedPreferences prefs,
    required repo.ModelRepository repository,
    required repo.ModelType type,
    required bool hasLoraWeights,
  }) async {
    final bundledPath = prefs.getString('bundled_path_$filename');
    final externalPath = prefs.getString('external_path_$filename');

    final ModelSource source;
    if (bundledPath != null) {
      source = ModelSource.bundled(filename);
    } else if (externalPath != null) {
      source = ModelSource.file(externalPath);
    } else {
      // Regular downloaded file (network source unknown, use generic)
      source = ModelSource.network('https://unknown/$filename');
    }

    // Get file size
    int sizeBytes = 0;
    try {
      final registry = ServiceRegistry.instance;
      final fileSystem = registry.fileSystemService;

      if (bundledPath != null) {
        final file = File(bundledPath);
        if (await file.exists()) {
          sizeBytes = await file.length();
        }
      } else if (externalPath != null) {
        final file = File(externalPath);
        if (await file.exists()) {
          sizeBytes = await file.length();
        }
      } else {
        final path = await fileSystem.getTargetPath(filename);
        final file = File(path);
        if (await file.exists()) {
          sizeBytes = await file.length();
        }
      }
    } catch (e) {
      debugPrint('⚠️  Could not get size for $filename: $e');
      // Continue without size
    }

    final modelInfo = repo.ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: sizeBytes,
      type: type,
      hasLoraWeights: hasLoraWeights,
    );

    await repository.saveModel(modelInfo);
  }

  /// Cleans up old Legacy preference keys
  Future<void> _cleanupLegacyKeys(SharedPreferences prefs) async {
    debugPrint('🧹 Cleaning up old Legacy preference keys...');

    // Remove main lists
    await prefs.remove('installed_models');
    await prefs.remove('installed_loras');
    await prefs.remove('installed_embedding_models');
    await prefs.remove('installed_tokenizers');

    // Remove all bundled_path_* and external_path_* keys
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('bundled_path_') ||
          key.startsWith('external_path_') ||
          key == 'installed_model_file_name' ||
          key == 'embedding_model_file') {
        await prefs.remove(key);
        debugPrint('🧹 Removed old key: $key');
      }
    }
  }
}

/// Result of migration operation
class MigrationResult {
  /// Number of successfully migrated files
  final int migratedCount;

  /// Number of files that were skipped due to errors
  final int skippedCount;

  /// List of error messages for skipped files
  final List<String> errors;

  /// Whether migration was already completed before
  final bool alreadyCompleted;

  MigrationResult({
    required this.migratedCount,
    required this.skippedCount,
    required this.errors,
    required this.alreadyCompleted,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isSuccess => errors.isEmpty;
}

/// Exception thrown during migration
class MigrationException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  MigrationException(this.message, this.cause, this.stackTrace);

  @override
  String toString() => 'MigrationException: $message (caused by: $cause)';
}
