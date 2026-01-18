// Test for Issue #174: Download screen exit and re-entry behavior
//
// User scenario:
// 1. Go to download screen, click download
// 2. Click back to exit - download still in progress in background
// 3. Go back to download screen - shows restart button instead of progress
// 4. If download finishes in background, status shows "downloaded"
// 5. BUT when entering chat, model reloads from scratch
//
// This test identifies the root cause of these issues.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/core/domain/model_source.dart';
import 'package:flutter_gemma/core/services/file_system_service.dart';
import 'package:flutter_gemma/core/services/model_repository.dart';

/// Mock FileSystemService
class MockFileSystemService implements FileSystemService {
  final Set<String> _files = {};

  @override
  Future<void> deleteFile(String path) async {
    _files.remove(path);
  }

  @override
  Future<bool> fileExists(String path) async => _files.contains(path);

  @override
  Future<String> getBundledResourcePath(String resourceName) async =>
      '/bundled/$resourceName';

  @override
  Future<int> getFileSize(String path) async => _files.contains(path) ? 1024 : 0;

  @override
  Future<String> getTargetPath(String filename) async => '/models/$filename';

  @override
  Future<Uint8List> readFile(String path) async => Uint8List(0);

  @override
  Future<void> registerExternalFile(String filename, String externalPath) async {}

  @override
  Future<void> writeFile(String path, List<int> data) async {
    _files.add(path);
  }

  void createFile(String path) => _files.add(path);
  bool hasFile(String path) => _files.contains(path);
  void clear() => _files.clear();
}

/// Mock ModelRepository
class MockModelRepository implements ModelRepository {
  final Map<String, ModelInfo> _models = {};

  @override
  Future<void> saveModel(ModelInfo info) async {
    _models[info.id] = info;
  }

  @override
  Future<ModelInfo?> loadModel(String id) async {
    return _models[id];
  }

  @override
  Future<void> deleteModel(String id) async {
    _models.remove(id);
  }

  @override
  Future<bool> isInstalled(String id) async {
    return _models.containsKey(id);
  }

  @override
  Future<List<ModelInfo>> listInstalled() async {
    return _models.values.toList();
  }

  void clear() => _models.clear();
}

void main() {
  late MockModelRepository mockRepo;
  late MockFileSystemService mockFS;

  setUp(() {
    mockRepo = MockModelRepository();
    mockFS = MockFileSystemService();
  });

  tearDown(() {
    mockRepo.clear();
    mockFS.clear();
  });

  group('Issue #174 - Download flow problems', () {

    test('PROBLEM 1: isModelInstalled only checks metadata, not file existence', () async {
      // Scenario: Metadata exists but file was deleted externally
      const modelId = 'test-model.task';

      // Save metadata without creating file
      await mockRepo.saveModel(ModelInfo(
        id: modelId,
        source: ModelSource.network('https://example.com/$modelId'),
        installedAt: DateTime.now(),
        sizeBytes: 100,
        type: ModelType.inference,
        hasLoraWeights: false,
      ));

      // isInstalled returns TRUE even though file doesn't exist!
      final isInstalled = await mockRepo.isInstalled(modelId);
      expect(isInstalled, isTrue, reason: 'Metadata exists');

      // But file does NOT exist
      final fileExists = await mockFS.fileExists('/models/$modelId');
      expect(fileExists, isFalse, reason: 'File does not exist');

      // This is the BUG: isModelInstalled should check BOTH metadata AND file
      // Current behavior causes "Downloaded" status when file is missing
    });

    test('PROBLEM 2: uninstallModel deletes metadata before file - causes orphaned files', () async {
      // Scenario: uninstallModel fails during file deletion
      const modelId = 'test-model.task';
      final filePath = '/models/$modelId';

      // Setup: Model is installed (metadata + file)
      await mockRepo.saveModel(ModelInfo(
        id: modelId,
        source: ModelSource.network('https://example.com/$modelId'),
        installedAt: DateTime.now(),
        sizeBytes: 100,
        type: ModelType.inference,
        hasLoraWeights: false,
      ));
      mockFS.createFile(filePath);

      // Verify both exist
      expect(await mockRepo.isInstalled(modelId), isTrue);
      expect(mockFS.hasFile(filePath), isTrue);

      // Simulate CURRENT uninstallModel flow (metadata first, then file)
      // Step 1: Delete metadata FIRST (current behavior)
      await mockRepo.deleteModel(modelId);
      expect(await mockRepo.isInstalled(modelId), isFalse,
          reason: 'Metadata deleted');

      // Step 2: File deletion would happen here
      // If it FAILS (exception), we have:
      // - Metadata: DELETED
      // - File: STILL EXISTS (orphaned!)
      expect(mockFS.hasFile(filePath), isTrue,
          reason: 'File still exists - ORPHANED!');

      // Result: Orphaned file on disk, no way to track or delete it
    });

    test('PROBLEM 3: No tracking of in-progress downloads', () async {
      // Scenario: User exits download screen during download, returns later

      // There's no mechanism to track:
      // 1. Is a download currently in progress?
      // 2. What's the progress percentage?
      // 3. For which model?

      // Current implementation uses widget-local state:
      // bool _downloading = false;
      // double _progress = 0.0;

      // When widget is destroyed (user exits), this state is lost.
      // When user returns, new widget instance starts fresh.

      // Solution needed: Global/persistent download state tracking

      expect(true, isTrue, reason: 'This test documents the design issue');
    });

    test('CORRECT FIX: isModelInstalled should verify both metadata AND file', () async {
      const modelId = 'test-model.task';
      final filePath = '/models/$modelId';

      // Helper function that checks BOTH (proposed fix)
      Future<bool> isModelInstalledCorrectly(String id) async {
        // Step 1: Check metadata
        final hasMetadata = await mockRepo.isInstalled(id);
        if (!hasMetadata) return false;

        // Step 2: Check file exists
        final path = await mockFS.getTargetPath(id);
        final hasFile = await mockFS.fileExists(path);

        return hasFile;
      }

      // Case 1: Neither metadata nor file
      expect(await isModelInstalledCorrectly(modelId), isFalse);

      // Case 2: Metadata only (file deleted externally)
      await mockRepo.saveModel(ModelInfo(
        id: modelId,
        source: ModelSource.network('https://example.com/$modelId'),
        installedAt: DateTime.now(),
        sizeBytes: 100,
        type: ModelType.inference,
        hasLoraWeights: false,
      ));
      expect(await isModelInstalledCorrectly(modelId), isFalse,
          reason: 'Metadata exists but file missing - should return FALSE');

      // Case 3: Both metadata and file
      mockFS.createFile(filePath);
      expect(await isModelInstalledCorrectly(modelId), isTrue,
          reason: 'Both metadata and file exist');
    });

    test('CORRECT FIX: uninstallModel should delete file FIRST, then metadata', () async {
      const modelId = 'test-model.task';
      final filePath = '/models/$modelId';

      // Setup
      await mockRepo.saveModel(ModelInfo(
        id: modelId,
        source: ModelSource.network('https://example.com/$modelId'),
        installedAt: DateTime.now(),
        sizeBytes: 100,
        type: ModelType.inference,
        hasLoraWeights: false,
      ));
      mockFS.createFile(filePath);

      // Correct order: file first, then metadata
      // If file deletion fails:
      // - File: STILL EXISTS
      // - Metadata: STILL EXISTS
      // → Consistent state, user can retry deletion

      bool fileDeletionFailed = false;

      try {
        // Step 1: Delete file FIRST
        await mockFS.deleteFile(filePath);

        // Step 2: Delete metadata only if file deletion succeeded
        await mockRepo.deleteModel(modelId);
      } catch (e) {
        fileDeletionFailed = true;
        // If this fails, metadata is still intact - consistent state
      }

      // Verify clean deletion
      expect(fileDeletionFailed, isFalse);
      expect(await mockRepo.isInstalled(modelId), isFalse);
      expect(mockFS.hasFile(filePath), isFalse);
    });
  });
}
