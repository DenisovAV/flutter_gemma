# Background Downloader: Foreground/Background Mode Analysis

## Executive Summary

**Critical Finding:** Foreground mode is the ONLY way to bypass Android's ~9 minute background task timeout. It must be used for large files (>500MB) on Android.

**Key Insight:** Foreground mode does NOT affect retry/resume behavior. It only affects the Android WorkManager execution context (foreground service vs background worker).

---

## 1. How `runInForeground` Works

### Architecture (Android-Specific)

**Android WorkManager Context:**
- **Background Mode (default):** Task runs as `CoroutineWorker` via WorkManager
  - Subject to ~9 minute timeout (varies by Android version and device)
  - Android may kill the worker if system resources are low
  - Task is enqueued with WorkManager's background constraints

- **Foreground Mode:** Task runs as `ForegroundService` via WorkManager's `setForeground()`
  - NOT subject to 9 minute timeout
  - Shows persistent notification (REQUIRED)
  - Cannot be killed by system (except in extreme cases)
  - Uses `FOREGROUND_SERVICE_TYPE_DATA_SYNC` permission (Android 14+)

### Implementation Details

**Configuration Options:**

```dart
// Option 1: Always run in foreground (all tasks)
await FileDownloader().configure(globalConfig: [
  (Config.runInForeground, true),
  // OR
  (Config.runInForeground, Config.always),
]);

// Option 2: Never run in foreground
await FileDownloader().configure(globalConfig: [
  (Config.runInForeground, false),
  // OR
  (Config.runInForeground, Config.never),
]);

// Option 3: Run in foreground if file size exceeds threshold (RECOMMENDED)
await FileDownloader().configure(globalConfig: [
  (Config.runInForegroundIfFileLargerThan, 100), // 100 MB
]);
```

**How Decision is Made:**

From `TaskRunner.kt` lines 852-858:
```kotlin
fun determineRunInForeground(task: Task, contentLength: Long) {
    runInForeground =
        canRunInForeground && contentLength > (runInForegroundFileSize.toLong() shl 20)
    if (runInForeground) {
        Log.i(TAG, "TaskId ${task.taskId} will run in foreground")
    }
}
```

**Pre-requisites for Foreground Mode:**
1. `runInForegroundFileSize >= 0` (config must be set)
2. `notificationConfig?.running != null` (MUST have running notification)
3. `contentLength > runInForegroundFileSize` (file size check)

**Notification Requirement:**
```kotlin
// From TaskRunner.kt line 502-503
canRunInForeground = runInForegroundFileSize >= 0 &&
                    notificationConfig?.running != null // must have notification
```

**Without notification, foreground mode is silently disabled!**

### Notification Behavior

**Persistent Notification:**
- Shown in system notification area
- Cannot be dismissed by user while task is running
- Customizable via `TaskNotificationConfig`
- Progress bar automatically updates
- Supports tokens: `{filename}`, `{progress}`, `{networkSpeed}`, `{timeRemaining}`

**Example Notification Setup:**
```dart
final task = DownloadTask(
  url: 'https://example.com/large-file.bin',
  filename: 'large-file.bin',
);

final notificationConfig = TaskNotificationConfig(
  running: TaskNotification(
    'Downloading {filename}',
    'Progress: {progress} - Speed: {networkSpeed}',
  ),
  complete: TaskNotification(
    'Download Complete',
    '{filename} downloaded successfully',
  ),
  error: TaskNotification(
    'Download Failed',
    '{filename} failed: {error}',
  ),
  progressBar: true,
);

await FileDownloader().configure(globalConfig: [
  (Config.runInForegroundIfFileLargerThan, 100),
]);

await FileDownloader().enqueue(task);
```

---

## 2. Foreground + Network Drop: What Happens?

### Scenario Matrix

| Режим | allowPause | Network Drop | Результат |
|-------|------------|--------------|-----------|
| Background | false | yes | **Task FAILS immediately** - No resume, temp file deleted |
| Background | true | yes | **Task PAUSES** - Can resume if temp file exists + strong ETag |
| Foreground | false | yes | **Task FAILS immediately** - No resume, temp file deleted |
| Foreground | true | yes | **Task PAUSES** - Can resume if temp file exists + strong ETag |

**Key Finding:** Foreground mode does NOT change retry/resume behavior!

### Why Foreground Doesn't Affect Resume

**Foreground mode only affects:**
1. **Execution context** (ForegroundService vs CoroutineWorker)
2. **Timeout immunity** (no 9-minute limit)
3. **Process priority** (cannot be killed)

**Resume/pause logic is independent:**
- Controlled by `allowPause` flag
- Requires server support (Accept-Ranges, ETag)
- Depends on temp file preservation
- Handled by `ResumeData` mechanism

**From source code analysis:**
```kotlin
// Foreground mode is set AFTER connection is established
// Resume logic is handled BEFORE connection (via ResumeData)

// TaskRunner.kt line 243 - Foreground decision
determineRunInForeground(task, contentLength) // sets 'runInForeground'

// DownloadTaskRunner.kt - Resume logic (separate)
if (taskResumeData != null) {
    connection.setRequestProperty("Range", "bytes=${taskResumeData.requiredStartByte}-")
    if (taskResumeData.eTag != null) {
        connection.setRequestProperty("If-Range", taskResumeData.eTag)
    }
}
```

---

## 3. Retry Behavior and Foreground Mode

### Critical: `retries` Does NOT Work Automatically

**From previous analysis:**
- `retries` field in `DownloadTask` is stored but NOT used by background_downloader
- No automatic retry loop on network errors
- Application must implement retry logic manually

**Foreground mode does NOT change this:**
```dart
// This does NOT work automatically (foreground or background)
final task = DownloadTask(
  url: 'https://example.com/file.bin',
  filename: 'file.bin',
  retries: 3, // ❌ NOT USED by background_downloader!
);
```

**Manual retry required:**
```dart
int maxRetries = 3;
int attempt = 0;

while (attempt < maxRetries) {
  final result = await FileDownloader().download(task);

  if (result.status == TaskStatus.complete) {
    break; // Success
  }

  if (result.status == TaskStatus.failed) {
    attempt++;
    if (attempt < maxRetries) {
      await Future.delayed(Duration(seconds: math.pow(2, attempt).toInt()));
      continue; // Retry
    }
  }

  break; // Give up
}
```

---

## 4. Complete Scenario Matrix

### Large File (>500MB) from HuggingFace

| Config | allowPause | Network Drop | Time | Результат |
|--------|------------|--------------|------|-----------|
| Background only | false | yes | any | ❌ FAIL - Android kills after ~9 min |
| Background only | true | yes | <9 min | ⚠️ PAUSE - May lose temp file if killed |
| Background only | true | yes | >9 min | ❌ FAIL - Android kills, temp file lost |
| **Foreground (100MB+)** | false | yes | any | ❌ FAIL - No resume, but no timeout |
| **Foreground (100MB+)** | true | yes | any | ✅ PAUSE - Can resume, no timeout |

**Recommended for HuggingFace (>500MB):**
```dart
await FileDownloader().configure(globalConfig: [
  (Config.runInForegroundIfFileLargerThan, 100), // 100 MB threshold
]);

final task = DownloadTask(
  url: huggingFaceUrl,
  filename: modelFileName,
  allowPause: true, // Enable resume capability
);

// Must also configure notification!
final notificationConfig = TaskNotificationConfig(
  running: TaskNotification(
    'Downloading {filename}',
    'Progress: {progress}',
  ),
  progressBar: true,
);
```

### Small File (<100MB) from GCS

| Config | allowPause | Network Drop | Результат |
|--------|------------|--------------|-----------|
| Background only | false | yes | ❌ FAIL immediately |
| Background only | true | yes | ✅ PAUSE - Resume works (strong ETag) |
| Foreground | false | yes | ❌ FAIL immediately (overkill) |
| Foreground | true | yes | ✅ PAUSE - Resume works (overkill) |

**Recommended for GCS (<100MB):**
```dart
// No foreground needed for small files
final task = DownloadTask(
  url: gcsUrl,
  filename: modelFileName,
  allowPause: true, // Enable resume (works with GCS)
);
```

---

## 5. File Size Threshold Strategy

### Recommended Thresholds

**For Flutter Gemma Use Case:**

| File Size | Threshold | Rationale |
|-----------|-----------|-----------|
| <100 MB | Background only | Likely completes in <9 min, no foreground overhead |
| 100-500 MB | `runInForegroundIfFileLargerThan: 100` | May exceed 9 min on slow networks |
| >500 MB | `runInForegroundIfFileLargerThan: 100` | MUST use foreground to avoid timeout |

**Why 100 MB threshold?**
- **9 minute timeout:**
  - 100 MB / 9 min = ~185 KB/s average
  - Below typical mobile network speeds (~500 KB/s)
  - Safe margin for network fluctuations

- **Network speed assumptions:**
  - 3G: ~500 KB/s → 100 MB in ~3 min (safe)
  - 4G: ~5 MB/s → 100 MB in ~20 sec (very safe)
  - Slow WiFi: ~1 MB/s → 100 MB in ~1.5 min (safe)

### Dynamic Decision Before Download

**Problem:** File size not known until `Content-Length` header received.

**Solution:** Foreground decision is made AFTER receiving `Content-Length`:
```kotlin
// From DownloadTaskRunner.kt line 243
val contentLength = connection.contentLength.toLong()
BDPlugin.remainingBytesToDownload[task.taskId] = contentLength
determineRunInForeground(task, contentLength) // ✅ Decision happens here
```

**Workflow:**
1. Task enqueued in background mode
2. Connection established
3. `Content-Length` header received
4. `determineRunInForeground()` checks file size
5. If `size > threshold`, switches to foreground service
6. Notification shown automatically
7. Download proceeds in foreground

**No pre-download size check needed!**

---

## 6. Configuration Best Practices

### Flutter Gemma Recommended Config

```dart
// Initialize at app startup
Future<void> initializeDownloader() async {
  await FileDownloader().configure(
    globalConfig: [
      // Foreground for large files (>100 MB)
      (Config.runInForegroundIfFileLargerThan, 100),

      // Request timeout (connection establishment)
      (Config.requestTimeout, Duration(seconds: 30)),

      // Check available space (ensure 500 MB free)
      (Config.checkAvailableSpace, 500),
    ],
    androidConfig: [
      // Use cache dir when possible (for resume support)
      (Config.useCacheDir, Config.whenAble),
    ],
  );

  // Register notification config for all downloads
  FileDownloader().registerCallbacks(
    taskNotificationConfig: TaskNotificationConfig(
      running: TaskNotification(
        'Downloading AI Model',
        '{filename} - {progress}% - {networkSpeed}',
      ),
      complete: TaskNotification(
        'Download Complete',
        '{filename} is ready',
      ),
      error: TaskNotification(
        'Download Failed',
        '{filename} - {error}',
      ),
      progressBar: true,
      tapOpensFile: false, // Don't open .bin files
    ),
  );
}

// Download model (automatically uses foreground if >100 MB)
Future<void> downloadModel(String url, String filename) async {
  final task = DownloadTask(
    url: url,
    filename: filename,
    allowPause: true, // Enable resume on network drop
    updates: Updates.statusAndProgress,
  );

  await FileDownloader().enqueue(task);
}
```

### Source-Specific Strategies

**HuggingFace (weak ETag, no resume):**
```dart
// Config remains the same
// allowPause: true helps with pause/manual resume but not automatic
// Foreground prevents timeout (most important)

final task = DownloadTask(
  url: huggingFaceUrl,
  filename: modelFileName,
  allowPause: true,
  // Manual retry on failure (automatic resume won't work)
);
```

**GCS (strong ETag, resume works):**
```dart
// Foreground still beneficial for large files
// allowPause enables automatic resume

final task = DownloadTask(
  url: gcsUrl,
  filename: modelFileName,
  allowPause: true, // ✅ Resume works automatically
);
```

**Custom Server (varies):**
```dart
// Test server capabilities first
// Use conservative approach (foreground + allowPause)

final task = DownloadTask(
  url: customServerUrl,
  filename: modelFileName,
  allowPause: true, // Safe default
);
```

---

## 7. Android Manifest Requirements

### Required Permissions (Android 14+)

```xml
<!-- AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Required for foreground service (Android 14+) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />

    <!-- Required for network access -->
    <uses-permission android:name="android.permission.INTERNET" />

    <!-- Required for notifications -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application>
        <!-- Required service declaration for foreground mode -->
        <service
            android:name="androidx.work.impl.foreground.SystemForegroundService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />

        <!-- Your other app components -->
    </application>
</manifest>
```

**Without these, foreground mode will fail silently:**
- `ForegroundServiceStartNotAllowedException` logged (line 899-901 in Notifications.kt)
- Task falls back to background mode
- Subject to 9-minute timeout again

---

## 8. Testing Scenarios

### Test Matrix

| Test | Config | File Size | Expected Behavior |
|------|--------|-----------|-------------------|
| Small file background | No foreground | 10 MB | ✅ Background mode, completes fast |
| Large file foreground | `runInForegroundIfFileLargerThan: 100` | 500 MB | ✅ Foreground mode, shows notification |
| Network drop + resume | Foreground + allowPause | 500 MB | ✅ Pauses, resumes when network returns (if strong ETag) |
| No notification config | `runInForeground: true` | 500 MB | ⚠️ Falls back to background (no notification) |
| Manual retry | Foreground + allowPause | 500 MB | ✅ Can pause/resume + manual retry on failure |

### Test Commands

```bash
# Test network drop simulation
adb shell svc wifi disable
sleep 30
adb shell svc wifi enable

# Monitor WorkManager tasks
adb shell dumpsys jobscheduler | grep background_downloader

# Check foreground service
adb shell dumpsys activity services | grep SystemForegroundService

# View logs
adb logcat -s BackgroundDownloader:*
```

---

## 9. Key Takeaways

### Critical Points

1. **Foreground mode is ESSENTIAL for large files (>100 MB) on Android**
   - Bypasses 9-minute timeout
   - Prevents system killing the download
   - REQUIRES persistent notification

2. **Foreground mode does NOT affect resume/retry behavior**
   - Resume still requires `allowPause: true`
   - Resume still requires server support (strong ETag)
   - Retry still requires manual implementation

3. **File size threshold decision happens automatically**
   - No need to check size before download
   - Decision made after `Content-Length` received
   - Switches to foreground mid-flight if needed

4. **Notification is MANDATORY for foreground mode**
   - Without notification, foreground mode disabled
   - Falls back to background silently
   - Must configure `TaskNotificationConfig`

5. **Configuration persists across app restarts**
   - Stored in Android SharedPreferences
   - Must explicitly set `(Config.runInForeground, false)` to disable
   - Test devices may retain old configs

### Recommended Flutter Gemma Strategy

```dart
// One-time initialization
await FileDownloader().configure(globalConfig: [
  (Config.runInForegroundIfFileLargerThan, 100), // 100 MB threshold
  (Config.requestTimeout, Duration(seconds: 30)),
  (Config.checkAvailableSpace, 500), // 500 MB free space required
]);

// Always use this task configuration
final task = DownloadTask(
  url: modelUrl,
  filename: modelFileName,
  allowPause: true, // Enable resume capability
  updates: Updates.statusAndProgress,
);

// Let background_downloader decide foreground mode automatically
// Files >100 MB will run in foreground with notification
// Files <100 MB will run in background
await FileDownloader().enqueue(task);
```

---

## 10. Source Code References

### Key Files Analyzed

1. **`native_downloader.dart`** (lines 566-582)
   - Configuration API implementation
   - `Config.runInForeground` and `Config.runInForegroundIfFileLargerThan`

2. **`TaskRunner.kt`** (lines 447-451, 502-503, 852-858)
   - Foreground decision logic
   - `determineRunInForeground()` implementation
   - Pre-requisites check (notification + file size)

3. **`DownloadTaskRunner.kt`** (line 243)
   - Where foreground decision is triggered
   - After `Content-Length` received

4. **`Notifications.kt`** (lines 890-908)
   - Foreground service activation
   - `setForegroundNotification()` call
   - Fallback on `ForegroundServiceStartNotAllowedException`

5. **`BDPlugin.kt`** (lines 84-85, 157-160)
   - Foreground file size config storage
   - `keyConfigForegroundFileSize` in SharedPreferences

6. **`CONFIG.md`** (lines 35-45)
   - Official documentation
   - Configuration examples
   - Android manifest requirements

### Testing Evidence

- **Package version:** background_downloader 9.5.2
- **Last updated:** 2025-01-21
- **Source:** /Users/sashadenisov/.pub-cache/hosted/pub.dev/background_downloader-9.5.2/

---

## Conclusion

**For Flutter Gemma's use case (downloading 100MB-2GB AI models):**

✅ **MUST use:**
- `Config.runInForegroundIfFileLargerThan: 100` (bypass timeout)
- `allowPause: true` (enable resume if supported)
- `TaskNotificationConfig` (required for foreground)

✅ **SHOULD implement:**
- Manual retry logic with exponential backoff
- Progress tracking with `Updates.statusAndProgress`
- Error handling for all failure modes

❌ **DON'T expect:**
- Automatic retry on network errors (not implemented)
- Resume to work with HuggingFace weak ETags
- Foreground mode to magically fix resume issues

**The combination of foreground mode + allowPause + manual retry provides the best reliability for large file downloads on Android.**
