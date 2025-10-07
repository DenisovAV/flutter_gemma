2 Available Drinks# 📊 Сравнение Modern API и Legacy API

## **Inference Models (установка моделей для инференса)**

| Задача | Modern API | Legacy API | Вызывает `setActiveModel()`? |
|--------|-----------|------------|-------------------------------|
| **Скачать с сети** | `FlutterGemma.installModel()`<br/>`.fromNetwork(url, token: token)`<br/>`.withProgress((p) => ...)`<br/>`.install()` | `manager.downloadModelWithProgress(`<br/>`  spec, token: token)`<br/>`// ИЛИ`<br/>`manager.downloadModel(`<br/>`  spec, token: token)` | ✅ Modern (строка 145)<br/>❌ Legacy |
| **Из assets** | `FlutterGemma.installModel()`<br/>`.fromAsset('path')`<br/>`.install()` | `manager.ensureModelReadyFromSpec(`<br/>`  InferenceModelSpec.fromLegacyUrl(`<br/>`    modelUrl: 'asset://...')` | ✅ Оба |
| **Bundled (нативные ресурсы)** | `FlutterGemma.installModel()`<br/>`.fromBundled('resource')`<br/>`.install()` | `manager.ensureModelReadyFromSpec(`<br/>`  createBundledInferenceSpec(`<br/>`    resourceName: '...')` | ✅ Оба |
| **Внешний файл** | `FlutterGemma.installModel()`<br/>`.fromFile('/path')`<br/>`.install()` | `manager.setModelPath('/path')` | ✅ Оба |

## **Embedding Models (установка моделей эмбеддингов)**

| Задача | Modern API | Legacy API | Вызывает `setActiveModel()`? |
|--------|-----------|------------|-------------------------------|
| **Скачать с сети** | `FlutterGemma.installEmbeddingModel()`<br/>`.modelFromNetwork(url, token: token)`<br/>`.tokenizerFromNetwork(url, token: token)`<br/>`.withModelProgress((p) => ...)`<br/>`.withTokenizerProgress((p) => ...)`<br/>`.install()` | `manager.downloadModelWithProgress(`<br/>`  EmbeddingModelSpec.fromLegacyUrl(`<br/>`    modelUrl: '...',`<br/>`    tokenizerUrl: '...'),`<br/>`  token: token)` | ✅ Modern (строка 146)<br/>❌ Legacy |
| **Из assets** | `FlutterGemma.installEmbeddingModel()`<br/>`.modelFromAsset('path1')`<br/>`.tokenizerFromAsset('path2')`<br/>`.install()` | `manager.ensureModelReadyFromSpec(`<br/>`  createEmbeddingSpec(`<br/>`    modelUrl: 'asset://...',`<br/>`    tokenizerUrl: 'asset://...')` | ✅ Оба |
| **Bundled** | `FlutterGemma.installEmbeddingModel()`<br/>`.modelFromBundled('resource1')`<br/>`.tokenizerFromBundled('resource2')`<br/>`.install()` | `manager.ensureModelReadyFromSpec(`<br/>`  createBundledEmbeddingSpec(`<br/>`    modelResourceName: '...',`<br/>`    tokenizerResourceName: '...')` | ✅ Оба |

---

## 🔍 Детали реализации

### **Modern API (Билдеры)**

**InferenceInstallationBuilder:**
```dart
// lib/core/api/inference_installation_builder.dart - строка 143-145
// AUTO-SET as active inference model
final manager = FlutterGemmaPlugin.instance.modelManager;
manager.setActiveModel(spec);  // ✅ ВЫЗЫВАЕТ!
```

**EmbeddingInstallationBuilder:**
```dart
// lib/core/api/embedding_installation_builder.dart - строка 144-146
// AUTO-SET as active embedding model
final manager = FlutterGemmaPlugin.instance.modelManager;
manager.setActiveModel(spec);  // ✅ ВЫЗЫВАЕТ!
```

**Что делают билдеры:**
1. Вызывают handlers напрямую через ServiceRegistry
2. После успешной установки → `setActiveModel(spec)` ✅
3. Возвращают результат с деталями

---

### **Legacy API (MobileModelManager методы)**

**✅ Методы которые ВЫЗЫВАЮТ `setActiveModel()`:**

```dart
// lib/core/model_management/managers/unified_model_manager.dart

// Строка 186-193
Future<void> ensureModelReadyFromSpec(ModelSpec spec) async {
  await _ensureModelReadySpec(spec);

  // Set as active model (automatically routes by type)
  setActiveModel(spec);  // ✅ ВЫЗЫВАЕТ!
}

// Строка 195-207
Future<void> ensureModelReady(String filename, String url) async {
  final spec = InferenceModelSpec.fromLegacyUrl(...);
  await _ensureModelReadySpec(spec);
  // Set as active inference model after ensuring it's ready
  setActiveModel(spec);  // ✅ ВЫЗЫВАЕТ!
}

// Строка 672-684
Future<void> setModelPath(String path, {String? loraPath}) async {
  final spec = InferenceModelSpec.fromLegacyUrl(...);
  await _ensureModelReadySpec(spec);
  setActiveModel(spec);  // ✅ ВЫЗЫВАЕТ!
}
```

**❌ Методы которые НЕ ВЫЗЫВАЮТ `setActiveModel()`:**

```dart
// lib/core/model_management/managers/unified_model_manager.dart

// Строка 210-223
Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
  await _ensureInitialized();

  debugPrint('UnifiedModelManager: Starting download with progress - ${spec.name}');

  try {
    yield* _downloadModelWithProgress(spec, token: token);
    debugPrint('UnifiedModelManager: Download completed - ${spec.name}');
    // ❌ НЕ ВЫЗЫВАЕТ setActiveModel()!
  } catch (e) {
    debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
    rethrow;
  }
}

// Строка 321-336
Future<void> downloadModel(ModelSpec spec, {String? token}) async {
  await _ensureInitialized();

  debugPrint('UnifiedModelManager: Starting download - ${spec.name}');

  try {
    await for (final _ in _downloadModelWithProgress(spec, token: token)) {
      // Just consume the stream without emitting progress
    }
    debugPrint('UnifiedModelManager: Download completed - ${spec.name}');
    // ❌ НЕ ВЫЗЫВАЕТ setActiveModel()!
  } catch (e) {
    debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
    rethrow;
  }
}
```

---

## 🐛 Проблема в тестах

**Тест `_testInferenceDownloadLegacy()`:**

```dart
// example/lib/integration_test_screen.dart - строка 1370-1378
await for (final progress in manager.downloadModelWithProgress(
  spec,
  token: token.isEmpty ? null : token,
)) {
  // progress tracking...
}

_log('✅ [LEGACY] Inference model downloaded successfully');
setState(() => _inferenceModelReady = true);
// ❌ НЕТ setActiveModel() - потому что downloadModelWithProgress() не делает этого!
```

После этого тест пытается запустить:
```dart
await _runInferenceTest();  // Использует Modern API createModel()
```

Modern API `createModel()` проверяет:
```dart
// lib/mobile/flutter_gemma_mobile.dart - строка 234
final activeModel = manager.activeInferenceModel;

// No active inference model - user must set one first
if (activeModel == null) {
  completer.completeError(
    Exception('No active inference model set. Use `FlutterGemma.installInferenceModel()` or `modelManager.setActiveModel()` to set a model first'),
  );
}
```

💥 **ОШИБКА!** Модель скачана, но не установлена как активная.

---

## ✅ Решение

Добавить `setActiveModel(spec)` в конце двух методов в `unified_model_manager.dart`:

1. **`downloadModelWithProgress()`** - после успешной загрузки (строка 221)
2. **`downloadModel()`** - после успешной загрузки (строка 331)

**Код изменения:**

```dart
// Строка 210-223
@override
Stream<DownloadProgress> downloadModelWithProgress(ModelSpec spec, {String? token}) async* {
  await _ensureInitialized();

  debugPrint('UnifiedModelManager: Starting download with progress - ${spec.name}');

  try {
    yield* _downloadModelWithProgress(spec, token: token);
    debugPrint('UnifiedModelManager: Download completed - ${spec.name}');

    // ✅ ДОБАВИТЬ: Set as active model after successful download
    setActiveModel(spec);
  } catch (e) {
    debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
    rethrow;
  }
}

// Строка 321-336
@override
Future<void> downloadModel(ModelSpec spec, {String? token}) async {
  await _ensureInitialized();

  debugPrint('UnifiedModelManager: Starting download - ${spec.name}');

  try {
    await for (final _ in _downloadModelWithProgress(spec, token: token)) {
      // Just consume the stream without emitting progress
    }
    debugPrint('UnifiedModelManager: Download completed - ${spec.name}');

    // ✅ ДОБАВИТЬ: Set as active model after successful download
    setActiveModel(spec);
  } catch (e) {
    debugPrint('UnifiedModelManager: Download failed - ${spec.name}: $e');
    rethrow;
  }
}
```

Тогда Legacy API будет работать так же как Modern API - **автоматически устанавливать модель как активную** после успешной установки.

---

## 📝 Итоговое правило

**Все методы установки модели (Legacy и Modern) должны вызывать `setActiveModel(spec)` после успешной установки:**

| Метод | Текущее состояние | Должно быть |
|-------|-------------------|-------------|
| Modern Builder `.install()` | ✅ Вызывает | ✅ Вызывает |
| `ensureModelReadyFromSpec()` | ✅ Вызывает | ✅ Вызывает |
| `ensureModelReady()` | ✅ Вызывает | ✅ Вызывает |
| `setModelPath()` | ✅ Вызывает | ✅ Вызывает |
| `downloadModelWithProgress()` | ❌ Не вызывает | ✅ Должен вызывать |
| `downloadModel()` | ❌ Не вызывает | ✅ Должен вызывать |

После исправления все методы будут единообразно работать, и тесты не будут нуждаться в ручном `setActiveModel()`.
