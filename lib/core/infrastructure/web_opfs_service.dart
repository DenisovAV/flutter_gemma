/// Dart service wrapper for OPFS (Origin Private File System)
///
/// Provides high-level API for managing large model files in OPFS,
/// bypassing ArrayBuffer memory limits for models >2GB.
///
/// Platform: Web only
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/infrastructure/web_opfs_interop.dart';

/// Service for OPFS file management
///
/// Features:
/// - Download large files (>2GB) directly to OPFS
/// - Check cache status
/// - Get stream readers for MediaPipe
/// - Storage quota management
class WebOPFSService {
  final OPFSInterop _opfs;

  WebOPFSService(this._opfs);

  /// Factory constructor using global window.flutterGemmaOPFS
  factory WebOPFSService.fromWindow() {
    return WebOPFSService(opfsInterop);
  }

  /// Check if a model is cached in OPFS
  ///
  /// Returns true if the file exists in OPFS.
  Future<bool> isModelCached(String filename) async {
    try {
      final result = await _opfs.isModelCached(filename.toJS).toDart;
      return result.toDart;
    } catch (e) {
      debugPrint('[WebOPFSService] Error checking cache for $filename: $e');
      return false;
    }
  }

  /// Get the size of a cached model file
  ///
  /// Returns null if file not found.
  Future<int?> getCachedModelSize(String filename) async {
    try {
      final result = await _opfs.getCachedModelSize(filename.toJS).toDart;
      if (result == null) return null;
      return result.toDartInt;
    } catch (e) {
      debugPrint('[WebOPFSService] Error getting size for $filename: $e');
      return null;
    }
  }

  /// Download a model to OPFS with progress tracking and cancellation support
  ///
  /// Parameters:
  /// - [url]: Download URL (HTTP/HTTPS)
  /// - [filename]: Filename to save in OPFS (used as cache key)
  /// - [authToken]: Optional authentication token (HuggingFace, etc.)
  /// - [onProgress]: Progress callback (receives percentage 0-100)
  /// - [abortSignal]: Optional JS AbortSignal for cancellation
  ///
  /// Throws:
  /// - [Exception] on download failure
  /// - [Exception] if storage quota exceeded
  /// - [Exception] if download is aborted
  Future<void> downloadToOPFS(
    String url,
    String filename, {
    String? authToken,
    required void Function(int percentage) onProgress,
    JSAny? abortSignal,
  }) async {
    try {
      debugPrint('[WebOPFSService] Starting download: $filename');

      // Create JS callback for progress
      final jsProgressCallback = (JSNumber percentJs) {
        final percent = percentJs.toDartInt;
        onProgress(percent);
      }.toJS;

      // Call OPFS download with abort signal
      final result = await _opfs
          .downloadToOPFS(
            url.toJS,
            filename.toJS,
            authToken?.toJS,
            jsProgressCallback,
            abortSignal,
          )
          .toDart;

      if (!result.toDart) {
        throw Exception('OPFS download returned false');
      }

      debugPrint('[WebOPFSService] Download complete: $filename');
    } catch (e, stackTrace) {
      debugPrint('[WebOPFSService] Download failed: $e');
      debugPrint('[WebOPFSService] Stack trace: $stackTrace');
      throw Exception('Failed to download to OPFS: $e');
    }
  }

  /// Get a ReadableStreamDefaultReader for streaming a model file
  ///
  /// This is passed to MediaPipe's modelAssetBuffer parameter for
  /// memory-efficient streaming.
  ///
  /// Parameters:
  /// - [filename]: Model filename in OPFS
  ///
  /// Returns: JSAny (ReadableStreamDefaultReader)
  ///
  /// Throws:
  /// - [Exception] if file not found in OPFS
  Future<JSAny> getStreamReader(String filename) async {
    try {
      debugPrint('[WebOPFSService] Getting stream reader for: $filename');
      final reader = await _opfs.getStreamReader(filename.toJS).toDart;
      debugPrint('[WebOPFSService] Stream reader created');
      return reader;
    } catch (e, stackTrace) {
      debugPrint('[WebOPFSService] Failed to get stream reader: $e');
      debugPrint('[WebOPFSService] Stack trace: $stackTrace');
      throw Exception('Model not found in OPFS: $filename');
    }
  }

  /// Delete a model from OPFS
  ///
  /// Parameters:
  /// - [filename]: Model filename to delete
  ///
  /// Throws:
  /// - [Exception] on deletion failure
  Future<void> deleteModel(String filename) async {
    try {
      await _opfs.deleteModel(filename.toJS).toDart;
      debugPrint('[WebOPFSService] Deleted: $filename');
    } catch (e) {
      debugPrint('[WebOPFSService] Failed to delete $filename: $e');
      throw Exception('Failed to delete from OPFS: $e');
    }
  }

  /// Get current storage statistics
  ///
  /// Returns:
  /// - Map with 'usage' and 'quota' keys (bytes)
  Future<Map<String, int>> getStorageStats() async {
    try {
      final stats = await _opfs.getStorageStats().toDart as StorageStats;
      return {
        'usage': stats.usage.toDartInt,
        'quota': stats.quota.toDartInt,
      };
    } catch (e) {
      debugPrint('[WebOPFSService] Failed to get storage stats: $e');
      return {'usage': 0, 'quota': 0};
    }
  }

  /// Clear all models from OPFS (for testing/development)
  ///
  /// Returns: Number of files deleted
  Future<int> clearAll() async {
    try {
      final count = await _opfs.clearAll().toDart;
      final deletedCount = count.toDartInt;
      debugPrint('[WebOPFSService] Cleared $deletedCount files from OPFS');
      return deletedCount;
    } catch (e) {
      debugPrint('[WebOPFSService] Failed to clear OPFS: $e');
      throw Exception('Failed to clear OPFS: $e');
    }
  }
}
