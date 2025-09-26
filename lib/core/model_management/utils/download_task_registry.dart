part of '../../../mobile/flutter_gemma_mobile.dart';

/// Registry to track background_downloader tasks by filename
///
/// This class maintains the mapping between our model filenames and
/// the internal taskIds used by background_downloader package.
/// This enables proper resume detection and cleanup.
class DownloadTaskRegistry {
  static const String _prefsKey = 'flutter_gemma_download_tasks';
  static final _prefs = SharedPreferences.getInstance();

  /// Register a download task for a specific filename
  ///
  /// [filename] - The model filename (e.g., 'gemma-2b-it.bin')
  /// [taskId] - The background_downloader taskId
  static Future<void> registerTask(String filename, String taskId) async {
    try {
      final prefs = await _prefs;
      final existingMap = await getAllRegisteredTasks();

      existingMap[filename] = taskId;

      final jsonString = jsonEncode(existingMap);
      await prefs.setString(_prefsKey, jsonString);

      debugPrint('TaskRegistry: Registered $filename -> $taskId');
    } catch (e) {
      debugPrint('TaskRegistry: Failed to register task for $filename: $e');
    }
  }

  /// Get the taskId for a specific filename
  ///
  /// Returns null if no task is registered for this filename
  static Future<String?> getTaskId(String filename) async {
    try {
      final registeredTasks = await getAllRegisteredTasks();
      return registeredTasks[filename];
    } catch (e) {
      debugPrint('TaskRegistry: Failed to get taskId for $filename: $e');
      return null;
    }
  }

  /// Unregister a task when download completes or fails permanently
  ///
  /// [filename] - The model filename to unregister
  static Future<void> unregisterTask(String filename) async {
    try {
      final prefs = await _prefs;
      final existingMap = await getAllRegisteredTasks();

      if (existingMap.remove(filename) != null) {
        final jsonString = jsonEncode(existingMap);
        await prefs.setString(_prefsKey, jsonString);
        debugPrint('TaskRegistry: Unregistered $filename');
      }
    } catch (e) {
      debugPrint('TaskRegistry: Failed to unregister task for $filename: $e');
    }
  }

  /// Get all registered filename -> taskId mappings
  ///
  /// Returns empty map if no tasks are registered
  static Future<Map<String, String>> getAllRegisteredTasks() async {
    try {
      final prefs = await _prefs;
      final jsonString = prefs.getString(_prefsKey);

      if (jsonString == null || jsonString.isEmpty) {
        return <String, String>{};
      }

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return decoded.cast<String, String>();
    } catch (e) {
      debugPrint('TaskRegistry: Failed to get all registered tasks: $e');
      return <String, String>{};
    }
  }

  /// Clear all registered tasks (for cleanup/reset)
  static Future<void> clearAll() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(_prefsKey);
      debugPrint('TaskRegistry: Cleared all registered tasks');
    } catch (e) {
      debugPrint('TaskRegistry: Failed to clear all tasks: $e');
    }
  }

  /// Get statistics about registered tasks
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final allTasks = await getAllRegisteredTasks();
      return {
        'totalRegistered': allTasks.length,
        'registeredFiles': allTasks.keys.toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('TaskRegistry: Failed to get stats: $e');
      return {
        'totalRegistered': 0,
        'registeredFiles': <String>[],
        'error': e.toString(),
      };
    }
  }

  /// Check if a filename is currently registered
  static Future<bool> isRegistered(String filename) async {
    final taskId = await getTaskId(filename);
    return taskId != null;
  }

  /// Bulk register multiple tasks
  static Future<void> registerTasks(Map<String, String> tasks) async {
    try {
      final prefs = await _prefs;
      final existingMap = await getAllRegisteredTasks();

      existingMap.addAll(tasks);

      final jsonString = jsonEncode(existingMap);
      await prefs.setString(_prefsKey, jsonString);

      debugPrint('TaskRegistry: Bulk registered ${tasks.length} tasks');
    } catch (e) {
      debugPrint('TaskRegistry: Failed to bulk register tasks: $e');
    }
  }

  /// Bulk unregister multiple tasks
  static Future<void> unregisterTasks(List<String> filenames) async {
    try {
      final prefs = await _prefs;
      final existingMap = await getAllRegisteredTasks();

      int removedCount = 0;
      for (final filename in filenames) {
        if (existingMap.remove(filename) != null) {
          removedCount++;
        }
      }

      if (removedCount > 0) {
        final jsonString = jsonEncode(existingMap);
        await prefs.setString(_prefsKey, jsonString);
        debugPrint('TaskRegistry: Bulk unregistered $removedCount tasks');
      }
    } catch (e) {
      debugPrint('TaskRegistry: Failed to bulk unregister tasks: $e');
    }
  }
}