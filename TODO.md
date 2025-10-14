# Flutter Gemma - Technical Debt & Improvement Opportunities

**Last Updated:** 2025-10-14
**Status:** All items are **optional improvements** - current code works correctly

---

## 📋 Overview

This document tracks potential improvements and refactoring opportunities identified during code quality reviews. These are **NOT bugs** - the current implementation is stable and functional. These are opportunities to improve code maintainability, consistency, and user experience.

---

## 🔴 Priority: MEDIUM

### 1. Save `contentLength` for Authenticated Web Downloads

**Location:** `lib/core/infrastructure/web_js_interop.dart`, `lib/core/infrastructure/web_download_service.dart`

**Current Behavior:**
- Web authenticated downloads (private HuggingFace models with token) fetch `contentLength` during streaming
- This size information is **discarded** after download completes
- `ModelInfo.sizeBytes` is set to `-1` (unknown)

**Impact:**
- Storage statistics show `0 MB` for all web models
- Users cannot see actual model sizes in web platform
- Inconsistent with mobile platform (which shows real sizes)

**Proposed Solution:**

```dart
// lib/core/infrastructure/web_js_interop.dart:58-73 (MODIFY)
Future<({String blobUrl, int? sizeBytes})> fetchWithAuthAndCreateBlob(
  String url,
  String authToken, {
  required void Function(double progress) onProgress,
}) async {
  try {
    final options = _createFetchOptions(authToken);
    final response = await _fetch(url, options);

    // Check response status
    if (!response.isOk) { /* ... existing error handling ... */ }

    // Get content length for progress AND metadata
    final contentLength = _getContentLength(response);  // ← Already exists!

    // Stream response body
    final chunks = await _streamResponseBody(response, contentLength, onProgress);

    // Create blob from chunks
    final blob = _createBlob(chunks);

    // Create and return blob URL + size
    final blobUrl = _createBlobUrl(blob);

    return (blobUrl: blobUrl, sizeBytes: contentLength);  // ← Return size!

  } catch (e) {
    if (e is JsInteropException) rethrow;
    // ... existing error handling ...
  }
}

// lib/core/infrastructure/web_download_service.dart:106-149 (MODIFY)
Stream<int> _downloadWithAuth(
  String url,
  String targetPath,
  String authToken,
) async* {
  try {
    var lastProgress = 0;
    int? downloadedSizeBytes;  // ← Track size

    final result = await _jsInterop.fetchWithAuthAndCreateBlob(
      url,
      authToken,
      onProgress: (progress) {
        final progressPercent = (progress * 100).clamp(0, 100).toInt();
        lastProgress = progressPercent;
      },
    );

    final blobUrl = result.blobUrl;
    downloadedSizeBytes = result.sizeBytes;  // ← Capture size

    // Yield progress updates
    for (int i = 0; i <= lastProgress; i += 5) {
      yield i;
      await Future.delayed(const Duration(milliseconds: 10));
    }
    yield 100;

    // Register blob URL
    _fileSystem.registerUrl(targetPath, blobUrl);
    _blobUrlManager.track(targetPath, blobUrl);

    // Save metadata with ACTUAL size (not -1)
    final modelInfo = ModelInfo(
      id: path.basename(targetPath),
      source: ModelSource.network(url),
      installedAt: DateTime.now(),
      sizeBytes: downloadedSizeBytes ?? -1,  // ← Use real size or fallback
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await _repository.saveModel(modelInfo);

    debugPrint('WebDownloadService: Completed authenticated download for $targetPath');
    debugPrint('WebDownloadService: Blob URL created: $blobUrl (${downloadedSizeBytes ?? "unknown"} bytes)');

  } on JsInteropException catch (e) {
    // ... existing error handling ...
  }
}
```

**Benefits:**
- ✅ Accurate file sizes for private models
- ✅ Better storage statistics
- ✅ Consistency with mobile platform
- ✅ Zero performance impact (data already available)

**Effort:** ~2 hours
**Risk:** Low (additive change, no breaking changes)
**Testing Required:** Web authenticated downloads with HuggingFace token

---

## 🟡 Priority: LOW

### 2. Extract Duplicated Progress Simulation in Web Handlers

**Location:**
- `lib/core/handlers/web_asset_source_handler.dart:77-80`
- `lib/core/handlers/web_bundled_source_handler.dart:74-77`
- `lib/core/handlers/web_file_source_handler.dart:78-81`

**Current Behavior:**
- Three web handlers have **identical** progress simulation code:
  ```dart
  yield 0;
  await Future.delayed(const Duration(milliseconds: 50));
  yield 50;
  await Future.delayed(const Duration(milliseconds: 50));
  // ... register URL ...
  yield 100;
  ```
- This pattern is repeated 3 times (24 lines total)

**Impact:**
- 🟡 Maintainability: Changes must be made in 3 places
- 🟡 Code duplication: Same logic in multiple files
- ✅ Functionality: Works correctly as-is

**Note:** `WebDownloadService` uses a **different** simulation (20 steps) which is correct - network downloads should feel slower than instant registrations.

**Proposed Solution - Option A: Extract Helper Function**

```dart
// lib/core/handlers/web_progress_helpers.dart (NEW FILE)
/// Helper utilities for web platform progress simulation
library;

/// Simulates instant progress for operations that complete immediately
///
/// Web handlers use this for Asset/Bundled/File registration which is instant.
/// The simulation provides UX consistency with mobile platform.
///
/// Progress pattern:
/// - 0% → 50ms delay → 50% → 50ms delay → [action] → 100%
/// - Total duration: ~100ms
///
/// Example:
/// ```dart
/// Stream<int> installWithProgress(ModelSource source) async* {
///   yield* simulateInstantProgress(() async {
///     fileSystem.registerUrl(filename, url);
///     await repository.saveModel(modelInfo);
///   });
/// }
/// ```
Stream<int> simulateInstantProgress(Future<void> Function() action) async* {
  yield 0;
  await Future.delayed(const Duration(milliseconds: 50));
  yield 50;
  await Future.delayed(const Duration(milliseconds: 50));

  // Perform the actual action
  await action();

  yield 100;
}

// Usage in web_asset_source_handler.dart:67-98 (MODIFY)
import 'package:flutter_gemma/core/handlers/web_progress_helpers.dart';

@override
Stream<int> installWithProgress(ModelSource source) async* {
  if (source is! AssetSource) {
    throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
  }

  final filename = path.basename(source.path);

  yield* simulateInstantProgress(() async {
    // Register asset URL with WebFileSystemService
    fileSystem.registerUrl(filename, source.normalizedPath);

    // Save metadata to repository
    final modelInfo = ModelInfo(
      id: filename,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web assets
      type: ModelType.inference,
      hasLoraWeights: false,
    );

    await repository.saveModel(modelInfo);
  });
}

// Apply same pattern to:
// - web_bundled_source_handler.dart:67-98
// - web_file_source_handler.dart:72-105
```

**Proposed Solution - Option B: Abstract Base Class**

```dart
// lib/core/handlers/web_instant_handler_base.dart (NEW FILE)
/// Base class for web handlers that perform instant operations
///
/// Handles:
/// - Progress simulation (0% → 50% → 100%)
/// - Source validation
/// - Common error handling
///
/// Subclasses implement:
/// - Source type checking
/// - URL construction/validation
/// - ModelInfo creation
abstract class WebInstantHandler implements SourceHandler {
  final WebFileSystemService fileSystem;
  final ModelRepository repository;

  WebInstantHandler({
    required this.fileSystem,
    required this.repository,
  });

  /// Validates that the source is supported by this handler
  /// Throws ArgumentError if not supported
  void validateSource(ModelSource source);

  /// Extracts the unique identifier from the source (usually filename)
  String extractId(ModelSource source);

  /// Constructs the URL to register with WebFileSystemService
  String constructUrl(ModelSource source);

  /// Creates ModelInfo for the installed model
  ModelInfo createModelInfo(String id, ModelSource source);

  @override
  Future<void> install(ModelSource source) async {
    validateSource(source);

    final id = extractId(source);
    final url = constructUrl(source);

    fileSystem.registerUrl(id, url);

    final modelInfo = createModelInfo(id, source);
    await repository.saveModel(modelInfo);
  }

  @override
  Stream<int> installWithProgress(ModelSource source) async* {
    validateSource(source);

    // Simulate progress for UX consistency
    yield 0;
    await Future.delayed(const Duration(milliseconds: 50));
    yield 50;
    await Future.delayed(const Duration(milliseconds: 50));

    // Perform installation
    await install(source);

    yield 100;
  }

  @override
  bool supportsResume(ModelSource source) => false;
}

// Example implementation:
class WebAssetSourceHandler extends WebInstantHandler {
  WebAssetSourceHandler({
    required super.fileSystem,
    required super.repository,
  });

  @override
  bool supports(ModelSource source) => source is AssetSource;

  @override
  void validateSource(ModelSource source) {
    if (source is! AssetSource) {
      throw ArgumentError('WebAssetSourceHandler only supports AssetSource');
    }
  }

  @override
  String extractId(ModelSource source) {
    final assetSource = source as AssetSource;
    return path.basename(assetSource.path);
  }

  @override
  String constructUrl(ModelSource source) {
    final assetSource = source as AssetSource;
    return assetSource.normalizedPath;
  }

  @override
  ModelInfo createModelInfo(String id, ModelSource source) {
    return ModelInfo(
      id: id,
      source: source,
      installedAt: DateTime.now(),
      sizeBytes: -1, // Unknown for web assets
      type: ModelType.inference,
      hasLoraWeights: false,
    );
  }
}
```

**Comparison:**

| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| **Option A: Helper** | Simple, minimal changes, easy to understand | Still some duplication in setup code | ✅ **Recommended** |
| **Option B: Base Class** | Maximum DRY, enforces consistency | More abstraction, harder to understand | Alternative |
| **Option C: Do Nothing** | Zero effort, zero risk | Duplication remains | Acceptable |

**Benefits (Option A):**
- ✅ Single source of truth for progress simulation
- ✅ Easy to modify timing/behavior in one place
- ✅ Reduced code duplication (24 lines → 8 lines)
- ✅ Clear documentation of simulation purpose

**Effort:** ~1 hour
**Risk:** Very Low (refactoring only, no logic changes)
**Testing Required:** Web asset/bundled/file installations

---

## 🔵 Priority: OPTIONAL

### 3. Add HTTP HEAD Support for Public URL File Sizes

**Location:** `lib/core/infrastructure/web_download_service.dart`

**Current Behavior:**
- Public URLs (no authentication) are registered directly without downloading
- `ModelInfo.sizeBytes` is set to `-1` (unknown)
- Fast "installation" (~1 second simulation)

**Impact:**
- Storage statistics show `0 MB` for public models
- Users cannot estimate storage requirements

**Proposed Solution:**

```dart
// lib/core/infrastructure/web_download_service.dart:60-104 (MODIFY)
@override
Stream<int> downloadWithProgress(
  String url,
  String targetPath, {
  String? token,
  int maxRetries = 10,
}) async* {
  if (token == null) {
    // PUBLIC PATH: Direct URL registration
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (!uri.isScheme('HTTP') && !uri.isScheme('HTTPS'))) {
        throw ArgumentError('Invalid URL: $url. Must be HTTP or HTTPS.');
      }

      debugPrint('WebDownloadService: Registering public URL for $targetPath');

      // Register direct URL
      _fileSystem.registerUrl(targetPath, url);

      // Try to get content-length via HEAD request (non-blocking, optional)
      int? contentLength;
      try {
        contentLength = await _tryGetContentLengthViaHead(url);
        if (contentLength != null) {
          debugPrint('WebDownloadService: Detected size: ${contentLength ~/ 1024 / 1024} MB');
        }
      } catch (e) {
        debugPrint('WebDownloadService: Could not fetch content-length (non-fatal): $e');
        // Continue without size - not critical
      }

      // Simulate progress
      const totalSteps = 20;
      const stepDelay = Duration(milliseconds: 50);

      for (int i = 0; i <= totalSteps; i++) {
        final progress = (i * 100 ~/ totalSteps).clamp(0, 100);
        yield progress;

        if (i < totalSteps) {
          await Future.delayed(stepDelay);
        }
      }

      // Save metadata with size (if available)
      final modelInfo = ModelInfo(
        id: path.basename(targetPath),
        source: ModelSource.network(url),
        installedAt: DateTime.now(),
        sizeBytes: contentLength ?? -1,  // Use size from HEAD or fallback
        type: ModelType.inference,
        hasLoraWeights: false,
      );

      await _repository.saveModel(modelInfo);

      debugPrint('WebDownloadService: Completed registration for $targetPath');

    } catch (e) {
      // ... existing error handling ...
    }
  } else {
    // PRIVATE PATH: Fetch with auth (unchanged)
    yield* _downloadWithAuth(url, targetPath, token);
  }
}

/// Attempts to get file size via HTTP HEAD request
///
/// Returns null if:
/// - Server doesn't support HEAD
/// - No Content-Length header
/// - Request fails (CORS, network, etc.)
///
/// This is best-effort only - failures are non-fatal.
Future<int?> _tryGetContentLengthViaHead(String url) async {
  try {
    final options = _createHeadRequestOptions();
    final response = await _fetch(url, options);

    if (!response.isOk) {
      return null;
    }

    final contentLengthStr = response.headers.getHeader('content-length');
    if (contentLengthStr == null || contentLengthStr.isEmpty) {
      return null;
    }

    return int.tryParse(contentLengthStr);
  } catch (e) {
    // Silently fail - size is optional
    return null;
  }
}

JSAny _createHeadRequestOptions() {
  final optionsMap = {
    'method': 'HEAD',
    'mode': 'cors',  // Allow cross-origin HEAD requests
  };
  return optionsMap.jsify()!;
}
```

**Benefits:**
- ✅ Better UX: Users see real model sizes
- ✅ Storage planning: Can estimate disk usage
- ✅ Consistency: Similar to mobile platform
- ✅ Non-blocking: Failures don't prevent installation

**Drawbacks:**
- ⚠️ Extra HTTP request (adds ~100-500ms latency)
- ⚠️ CORS issues: Some servers block HEAD requests
- ⚠️ Not all servers return Content-Length
- ⚠️ More complex code

**Effort:** ~3 hours
**Risk:** Medium (HTTP failures must be handled gracefully)
**Testing Required:**
- Public URLs with/without Content-Length header
- CORS-restricted servers
- Network failures during HEAD request

---

## 📝 Notes

### Why `-1` for Web File Sizes is Acceptable

**Context:**
- Web platform has no local file system
- Assets/Bundled resources are served by web server
- Public URLs are registered (not downloaded)
- Only authenticated downloads use blob URLs

**Current Web Behavior:**
```dart
// web_model_manager.dart:285-289
return {
  'protectedFiles': installedCount,
  'totalSizeBytes': 0, // Unknown for web URLs (no local file system)
  'totalSizeMB': 0,
  'inferenceModels': inferenceCount,
  'embeddingModels': embeddingCount,
};
```

**Why it's OK:**
- ✅ Web doesn't use size validation (no file integrity checks needed)
- ✅ Storage stats correctly show 0 (web = no local storage)
- ✅ Browser manages caching automatically
- ✅ Users understand web models don't consume local disk

**When it matters:**
- 🟡 UX: Users want to know model sizes before download
- 🟡 Metrics: Analytics on model size distribution
- 🟡 Documentation: Accurate size information in docs

---

## 🚀 Implementation Plan

**If choosing to implement improvements:**

### Phase 1: Quick Wins (2-3 hours)
1. ✅ Extract progress simulation helper (Issue #2)
2. ✅ Save contentLength for authenticated downloads (Issue #1 - HIGH VALUE)

### Phase 2: Optional Enhancements (3-4 hours)
3. 🔵 Add HTTP HEAD support for public URLs (Issue #3)

### Phase 3: Do Nothing
- Current code works correctly
- All improvements are optional
- Revisit based on user feedback

---

## 📚 Related Documentation

- **Architecture:** `lib/core/handlers/README.md` (if exists)
- **Web Download Flow:** `lib/core/infrastructure/web_download_service.dart`
- **Blob Management:** `lib/core/infrastructure/blob_url_manager.dart`
- **Progress Simulation Rationale:** See `WebDownloadService` line 24 comments

---

## 🏷️ Tags

`#technical-debt` `#code-quality` `#refactoring` `#web-platform` `#optional` `#maintainability`
