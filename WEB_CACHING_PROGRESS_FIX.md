# Web Download Progress: "Stuck at 99%" Issue

## Problem Description

При скачивании больших моделей на web (например, 2.9GB Gemma 3n), прогресс застревает на 99% на длительное время без какого-либо feedback.

**Лог:**
```
🌊 Starting stream: contentLength=3038117888
Warning: Large file detected (2897.375MB). May encounter memory limits on some browsers.
```

После этого UI показывает 99% и "зависает" на несколько минут.

## Root Cause Analysis

### Поток данных на Web:

```
Download (streaming)              Cache Write (blocking)
0% ────────────────────► 99%     99% ──────────────► 100%
Progress updates every chunk     NO PROGRESS FEEDBACK
~ несколько минут                ~ долго для 3GB файла
```

### Код проблемы:

**`lib/core/infrastructure/web_cache_service.dart`** (строки 388-465):

```dart
Stream<int> getOrCacheAndRegisterWithProgress(...) async* {
  // ...

  // Loader reports progress, capped at 99%
  loader((progress) {
    final percent = (progress * 100).clamp(0, 99).toInt();  // <-- max 99%
    controller.add(percent);
  });

  // After download completes...

  // 3. Cache the data (BLOCKING, NO PROGRESS!)
  if (enableCache) {
    await cacheModel(cacheKey, loadedData!);  // <-- Stuck here for large files

    // 4. Create blob URL from cache
    final blobUrl = await getCachedBlobUrl(cacheKey);
    // ...
  }

  yield 100; // <-- Only after caching completes
}
```

**`cachePut` в `web/cache_api.js`:**
```javascript
window.cachePut = async function(cacheName, url, data) {
  const cache = await caches.open(cacheName);
  const response = new Response(data, {...});
  await cache.put(url, response);  // <-- BLOCKING for 3GB!
};
```

### Почему это только Web:

- **Mobile**: Файлы пишутся на диск во время streaming download → прогресс реальный
- **Web**: Download в память (0-99%) → запись в Cache API (blocking) → 100%

## Solution Options

---

### Option 1: Breaking Change (Clean API)

**Изменения:**

1. Создать новый тип для прогресса:
```dart
enum InstallPhase {
  downloading,  // Fetching data from source
  caching,      // Writing to Cache API (web only)
  complete,     // Installation finished
}

class InstallProgress {
  final int percentage; // 0-100
  final InstallPhase phase;

  const InstallProgress(this.percentage, this.phase);

  const InstallProgress.downloading(int percent)
    : percentage = percent, phase = InstallPhase.downloading;

  const InstallProgress.caching()
    : percentage = 99, phase = InstallPhase.caching;

  const InstallProgress.complete()
    : percentage = 100, phase = InstallPhase.complete;
}
```

2. Изменить интерфейс handler'а:
```dart
// Было:
Stream<int> installWithProgress(ModelSource source, ...);

// Станет:
Stream<InstallProgress> installWithProgress(ModelSource source, ...);
```

3. Добавить `phase` в `DownloadProgress`:
```dart
class DownloadProgress {
  final int currentFileIndex;
  final int totalFiles;
  final int currentFileProgress;
  final String currentFileName;
  final InstallPhase phase; // NEW
  ...
}
```

**Затронутые файлы:**
- `lib/core/handlers/source_handler.dart` - интерфейс
- `lib/core/handlers/web_network_source_handler.dart`
- `lib/core/handlers/web_asset_source_handler.dart`
- `lib/core/handlers/web_bundled_source_handler.dart`
- `lib/core/handlers/mobile_network_source_handler.dart`
- `lib/core/handlers/mobile_asset_source_handler.dart`
- `lib/core/handlers/mobile_bundled_source_handler.dart`
- `lib/core/handlers/mobile_file_source_handler.dart`
- `lib/core/infrastructure/web_cache_service.dart`
- `lib/core/infrastructure/web_download_service.dart`
- `lib/core/model_management/managers/web_model_manager.dart`
- `lib/core/model_management/managers/mobile_model_manager.dart`
- `lib/core/model_management/types/model_spec.dart` (DownloadProgress)

**Плюсы:**
- ✅ Чистый API
- ✅ Type-safe
- ✅ Extensible (можно добавить новые фазы)

**Минусы:**
- ❌ Breaking change
- ❌ Много файлов для изменения

---

### Option 2: Non-Breaking with Internal Convention (Recommended)

**Идея:** Добавить optional поле `phase` с default значением. Внутри использовать `-1` как сигнал между компонентами.

**Изменения:**

1. Добавить enum и optional поле в `DownloadProgress`:
```dart
enum InstallPhase {
  downloading,
  caching,
  complete,
}

class DownloadProgress {
  final int currentFileIndex;
  final int totalFiles;
  final int currentFileProgress;
  final String currentFileName;
  final InstallPhase phase; // NEW - default value for backward compat

  const DownloadProgress({
    required this.currentFileIndex,
    required this.totalFiles,
    required this.currentFileProgress,
    required this.currentFileName,
    this.phase = InstallPhase.downloading, // Default = backward compatible
  });
}
```

2. В `WebCacheService` yield `-1` перед кешированием:
```dart
// Before cacheModel:
debugPrint('💾 [WebCacheService] Saving to cache...');
yield -1;  // Internal signal: caching phase

await cacheModel(cacheKey, loadedData!);
// ...
yield 100;
```

3. В `WebModelManager` интерпретировать `-1`:
```dart
await for (final progress in handler.installWithProgress(sourceToInstall)) {
  if (progress == -1) {
    // Caching phase
    yield DownloadProgress(
      currentFileIndex: i,
      totalFiles: totalFiles,
      currentFileProgress: 99,
      currentFileName: file.filename,
      phase: InstallPhase.caching,  // NEW
    );
  } else {
    yield DownloadProgress(
      currentFileIndex: i,
      totalFiles: totalFiles,
      currentFileProgress: progress,
      currentFileName: file.filename,
      phase: InstallPhase.downloading,
    );
  }
}
```

**Затронутые файлы:**
- `lib/core/model_management/types/model_spec.dart` - DownloadProgress + enum
- `lib/core/infrastructure/web_cache_service.dart` - yield -1
- `lib/core/model_management/managers/web_model_manager.dart` - interpret -1

**Плюсы:**
- ✅ Non-breaking (default value)
- ✅ Старый код работает без изменений
- ✅ Чистый внешний API (enum phase)
- ✅ Меньше файлов для изменения
- ✅ Mobile не затронут

**Минусы:**
- ⚠️ `-1` как внутренняя конвенция (но не exposed в API)

---

### Option 3: Quick Hack (Not Recommended for API)

**Варианты:**

A. **Использовать `currentFileName` для статуса:**
```dart
// During caching:
yield DownloadProgress(
  ...
  currentFileProgress: 99,
  currentFileName: '💾 Saving to cache...',  // Hijack field
);
```

B. **Специальное значение progress (exposed):**
```dart
// In docs: 101 = caching, 102 = validating, etc.
yield 101;  // Caching
```

C. **Только debug logging:**
```dart
debugPrint('💾 Saving to cache...');
// No UI change, just console
```

**Плюсы:**
- ✅ Минимальные изменения

**Минусы:**
- ❌ Костыльно
- ❌ Плохой API design
- ❌ Confusing для пользователей библиотеки

---

## Additional Fixes Needed

### Error Handling

Также нужно улучшить error handling в caching:

```dart
// В web_cache_service.dart:
if (enableCache) {
  try {
    await cacheModel(cacheKey, loadedData!);
  } catch (e, stackTrace) {
    debugPrint('❌ [WebCacheService] Cache write failed: $e');
    debugPrint('Stack trace: $stackTrace');

    // Fallback: create blob URL without caching
    debugPrint('⚠️ [WebCacheService] Falling back to uncached blob URL');
    final blobUrl = _cacheInterop.createBlobUrl(loadedData!);
    _fileSystem.registerUrl(targetPath, blobUrl);
    yield 100;
    return;
  }
  // ... rest
}
```

### Large File Warning

Для очень больших файлов (>1GB) можно:
1. Показать предупреждение в UI
2. Предложить отключить кеширование
3. Или автоматически отключить кеширование

---

## Recommendation

**Option 2 (Non-Breaking with Internal Convention)** - лучший баланс между:
- Чистым API для пользователей
- Обратной совместимостью
- Минимальными изменениями

---

## UI Example (After Fix)

```dart
await for (final progress in downloadModelWithProgress(spec)) {
  switch (progress.phase) {
    case InstallPhase.downloading:
      showProgress('Downloading: ${progress.currentFileProgress}%');
    case InstallPhase.caching:
      showProgress('Saving to cache...');
    case InstallPhase.complete:
      showProgress('Complete!');
  }
}
```

---

## Files Summary

### Option 2 Changes:

| File | Change |
|------|--------|
| `lib/core/model_management/types/model_spec.dart` | Add `InstallPhase` enum, add `phase` field to `DownloadProgress` |
| `lib/core/infrastructure/web_cache_service.dart` | Yield `-1` before caching, add error handling |
| `lib/core/model_management/managers/web_model_manager.dart` | Interpret `-1` as caching phase |

---

## Related Issues

- Large file memory limits on web browsers
- Cache API quota exceeded errors
- Hot restart blob URL loss (separate issue, already fixed)
