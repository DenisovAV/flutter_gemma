# Smart Resume Detection Plan for Flutter Gemma

## Problem Analysis

### Current Issue
- Background_downloader creates resume data for tasks, but our system doesn't know the connection between:
  - **Our files**: `gemma-2b-it.bin`, `embedding_model.tflite`
  - **Background_downloader tasks**: internal taskIds (random UUIDs)
- Result: Downloads restart from 0% instead of proper resume

### Current Architecture Flow
1. **UnifiedDownloadEngine** uses group `'flutter_gemma_downloads'`
2. **Each file** downloads as separate `DownloadTask` with `allowPause: true`
3. **On failure** tries `taskCanResume()` and `resume()`
4. **Cleanup** only works at filesystem level, unaware of background_downloader

## Smart Solution Plan

### Phase 1: Task Tracking Integration
**Goal: Connect our files with background_downloader tasks**

#### 1.1. Create TaskRegistry
- Mapping `filename -> taskId`
- Save in SharedPreferences
- Clear when tasks complete

#### 1.2. Modify _downloadSingleFileWithProgress
- Save taskId for each file
- Register in TaskRegistry before start
- Clear from registry on success

### Phase 2: Smart Resume Detection
**Goal: Check if specific files can be resumed**

#### 2.1. Create ResumeChecker
- Check: `file exists` + `has taskId` + `taskCanResume()`
- Return: `CanResume | CannotResume | NoTask`

#### 2.2. Integrate into ensureModelReady
- Before downloading, check each file
- If can resume - continue
- If cannot - delete partial file

### Phase 3: Comprehensive Cleanup
**Goal: Smart cleanup at all levels**

#### 3.1. Cleanup Strategy
- **Level 1**: FileSystem cleanup (current)
- **Level 2**: TaskRegistry cleanup (new)
- **Level 3**: Background_downloader cleanup (new)

#### 3.2. Integrated Cleanup Flow
- Collect all registered files
- Check each for resume possibility
- Remove invalid/expired resume data
- Clean orphaned files

### Phase 4: Enhanced Download Flow
**Goal: Prevent future issues**

#### 4.1. Pre-download Check
- Check existing partial files
- Resume validation before start
- Cleanup invalid state

#### 4.2. Robust Error Handling
- Graceful fallback on resume errors
- Automatic cleanup on critical errors
- Better logging for debugging

## Implementation Details

### New Components

#### 1. TaskRegistry Class
```dart
class DownloadTaskRegistry {
  // Save: filename -> taskId
  static Future<void> registerTask(String filename, String taskId)

  // Get: taskId for file
  static Future<String?> getTaskId(String filename)

  // Clear: on task completion
  static Future<void> unregisterTask(String filename)

  // Get all: for cleanup
  static Future<Map<String, String>> getAllRegisteredTasks()
}
```

#### 2. ResumeChecker Class
```dart
class ResumeChecker {
  // Check resume possibility for file
  static Future<ResumeStatus> checkResumeStatus(String filename)

  // Bulk check for model
  static Future<Map<String, ResumeStatus>> checkModelResume(ModelSpec spec)
}

enum ResumeStatus {
  canResume,    // File + taskId + server supports
  cannotResume, // File exists, but resume impossible
  noTask,       // No task for file
  fileComplete  // File already complete
}
```

#### 3. Enhanced Cleanup
```dart
// In UnifiedDownloadEngine.performCleanup()
static Future<void> performCleanup() async {
  // 1. Traditional file cleanup
  await _cleanupOrphanedFiles();

  // 2. Task registry cleanup
  await _cleanupTaskRegistry();

  // 3. Background_downloader cleanup
  await _cleanupBackgroundDownloaderResources();
}
```

### Modifications to Existing Components

#### In _downloadSingleFileWithProgress:
```dart
// BEFORE downloading:
final taskId = generateTaskId();
await TaskRegistry.registerTask(filename, taskId);

// Task with known taskId:
final task = DownloadTask(
  taskId: taskId,  // Explicit taskId
  // ... other parameters
);

// AFTER success:
await TaskRegistry.unregisterTask(filename);
```

#### In ensureModelReady:
```dart
// BEFORE downloadModel:
final resumeStatuses = await ResumeChecker.checkModelResume(spec);

for (final file in spec.files) {
  switch (resumeStatuses[file.filename]) {
    case ResumeStatus.canResume:
      // Try to resume
      break;
    case ResumeStatus.cannotResume:
      // Delete partial file + registry
      break;
    case ResumeStatus.fileComplete:
      // Skip download
      break;
  }
}
```

## Benefits

1. ✅ **Full Control** - know exactly which tasks belong to which files
2. ✅ **Smart Resume** - check real possibility to continue
3. ✅ **Safe Cleanup** - don't touch active downloads
4. ✅ **Issue Prevention** - checks before downloading
5. ✅ **Backward Compatible** - doesn't break existing code
6. ✅ **Debug Friendly** - detailed logs and statuses

## Implementation Steps

1. Create TaskRegistry class
2. Create ResumeChecker class
3. Modify download engine to use registry
4. Add pre-download resume checks
5. Enhance cleanup system
6. Add comprehensive testing
7. Add logging and monitoring

This plan solves the root problem: lack of connection between our files and background_downloader tasks, which leads to "restart from 0%" instead of proper resume.