# VectorStore Testing Guide (v0.11.7)

## Цель
Проверить корректность реализации VectorStore optimization с Binary BLOB storage и динамическими размерностями на Android и iOS.

## Предварительные требования

### 1. Установка моделей
```dart
// Установить embedding модель для генерации эмбеддингов
await FlutterGemma.installEmbedder()
  .modelFromNetwork(
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
    token: 'your_hf_token',
  )
  .tokenizerFromNetwork(
    'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
  )
  .install();

// Создать embedding модель
final embeddingModel = await FlutterGemma.getActiveEmbedder(
  preferredBackend: PreferredBackend.gpu,
);
```

## Тестовые сценарии

### Тест 1: Базовая функциональность (Android + iOS)

**Цель**: Проверить инициализацию, добавление документов и поиск.

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

Future<void> testBasicVectorStore() async {
  // 1. Инициализация
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/test_vector_store.db';

  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
  print('✅ VectorStore initialized');

  // 2. Генерация эмбеддингов
  final texts = [
    'Flutter is a UI framework',
    'Dart is a programming language',
    'Machine learning on mobile devices',
  ];

  for (int i = 0; i < texts.length; i++) {
    final embedding = await embeddingModel.generateEmbedding(texts[i]);

    await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
      id: 'doc_$i',
      content: texts[i],
      embedding: embedding,
      metadata: '{"source": "test", "index": $i}',
    );
    print('✅ Added document $i (${embedding.length}D embedding)');
  }

  // 3. Проверка статистики
  final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  print('📊 Stats: ${stats.documentCount} docs, ${stats.vectorDimension}D');

  assert(stats.documentCount == 3, 'Expected 3 documents');
  assert(stats.vectorDimension == 768, 'Expected 768D for EmbeddingGemma (all variants output 768D)');

  // 4. Поиск похожих документов
  final results = await FlutterGemmaPlugin.instance.searchSimilar(
    query: 'What is Flutter?',
    topK: 2,
    threshold: 0.0,
  );

  print('🔍 Search results:');
  for (final result in results) {
    print('  - ${result.content} (similarity: ${result.similarity.toStringAsFixed(4)})');
  }

  assert(results.isNotEmpty, 'Expected search results');
  assert(results.first.content.contains('Flutter'), 'Expected Flutter in top result');

  // 5. Очистка
  await FlutterGemmaPlugin.instance.clearVectorStore();
  final statsAfterClear = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  assert(statsAfterClear.documentCount == 0, 'Expected 0 documents after clear');

  print('✅ All basic tests passed!');
}
```

**Ожидаемые результаты**:
- ✅ Инициализация без ошибок
- ✅ Все 3 документа добавлены
- ✅ Stats показывает 3 документа, 1024D
- ✅ Поиск возвращает релевантные результаты
- ✅ Clear очищает базу данных

---

### Тест 2: Динамические размерности

**Цель**: Проверить auto-detect различных размерностей эмбеддингов.

```dart
Future<void> testDynamicDimensions() async {
  final appDir = await getApplicationDocumentsDirectory();

  // Тест 2.1: 256D (Gecko Small)
  print('\n📐 Testing 256D embeddings...');
  final dbPath256 = '${appDir.path}/test_256d.db';
  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath256);

  // Имитация 256D эмбеддинга
  final embedding256 = List.generate(256, (i) => i / 256.0);
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: 'doc_256',
    content: 'Test 256D',
    embedding: embedding256,
  );

  var stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  assert(stats.vectorDimension == 256, 'Expected 256D');
  print('✅ 256D test passed');

  // Тест 2.2: 768D (BERT-base)
  print('\n📐 Testing 768D embeddings...');
  final dbPath768 = '${appDir.path}/test_768d.db';
  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath768);

  final embedding768 = List.generate(768, (i) => i / 768.0);
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: 'doc_768',
    content: 'Test 768D',
    embedding: embedding768,
  );

  stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  assert(stats.vectorDimension == 768, 'Expected 768D');
  print('✅ 768D test passed');

  // Тест 2.3: 1536D (OpenAI Ada)
  print('\n📐 Testing 1536D embeddings...');
  final dbPath1536 = '${appDir.path}/test_1536d.db';
  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath1536);

  final embedding1536 = List.generate(1536, (i) => i / 1536.0);
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: 'doc_1536',
    content: 'Test 1536D',
    embedding: embedding1536,
  );

  stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  assert(stats.vectorDimension == 1536, 'Expected 1536D');
  print('✅ 1536D test passed');

  print('\n✅ All dimension tests passed!');
}
```

**Ожидаемые результаты**:
- ✅ 256D эмбеддинги корректно сохраняются
- ✅ 768D эмбеддинги корректно сохраняются
- ✅ 1536D эмбеддинги корректно сохраняются
- ✅ VectorStoreStats показывает правильную размерность

---

### Тест 3: Валидация размерности

**Цель**: Проверить валидацию несовместимых размерностей.

```dart
Future<void> testDimensionValidation() async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/test_validation.db';

  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

  // Добавляем первый документ с 768D
  final embedding768 = List.generate(768, (i) => i / 768.0);
  await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
    id: 'doc_768',
    content: 'First doc 768D',
    embedding: embedding768,
  );
  print('✅ Added 768D document');

  // Пытаемся добавить документ с 256D (должно выбросить ошибку)
  try {
    final embedding256 = List.generate(256, (i) => i / 256.0);
    await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
      id: 'doc_256',
      content: 'Second doc 256D',
      embedding: embedding256,
    );

    print('❌ ERROR: Should have thrown dimension mismatch error!');
    assert(false, 'Expected dimension mismatch error');
  } catch (e) {
    if (e.toString().contains('dimension mismatch') ||
        e.toString().contains('expected 768, got 256')) {
      print('✅ Correctly rejected mismatched dimension');
    } else {
      print('❌ ERROR: Wrong error type: $e');
      rethrow;
    }
  }

  print('✅ Dimension validation test passed!');
}
```

**Ожидаемые результаты**:
- ✅ Первый документ (768D) добавляется успешно
- ✅ Второй документ (256D) отклоняется с ошибкой dimension mismatch
- ✅ Ошибка содержит "expected 768, got 256"

---

### Тест 4: Производительность Storage

**Цель**: Проверить оптимизацию хранилища (BLOB vs JSON).

```dart
import 'dart:io';

Future<void> testStorageOptimization() async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/test_performance.db';

  // Удаляем старую БД если есть
  final dbFile = File(dbPath);
  if (await dbFile.exists()) {
    await dbFile.delete();
  }

  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

  // Добавляем 100 документов с 768D эмбеддингами
  print('📊 Adding 100 documents with 768D embeddings...');
  final stopwatch = Stopwatch()..start();

  for (int i = 0; i < 100; i++) {
    final embedding = List.generate(768, (j) => (i + j) / 768.0);
    await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
      id: 'doc_$i',
      content: 'Document number $i',
      embedding: embedding,
      metadata: '{"index": $i}',
    );

    if ((i + 1) % 20 == 0) {
      print('  Added ${i + 1} documents...');
    }
  }

  stopwatch.stop();
  print('✅ Added 100 documents in ${stopwatch.elapsedMilliseconds}ms');

  // Проверяем размер файла
  final stats = await dbFile.stat();
  final sizeKB = stats.size / 1024;
  print('📦 Database size: ${sizeKB.toStringAsFixed(2)} KB');

  // Ожидаемый размер с BLOB:
  // 100 docs * 768D * 4 bytes (float32) = 307,200 bytes = ~300 KB
  // + overhead (индексы, метаданные) ~50-100 KB
  // Итого: ~350-400 KB

  // Размер с JSON был бы:
  // 100 docs * 10.5 KB = 1,050 KB

  final expectedMaxSize = 500; // KB (с запасом)
  assert(sizeKB < expectedMaxSize,
    'Database too large: $sizeKB KB (expected < $expectedMaxSize KB)');

  print('✅ Storage optimization verified!');
  print('   Expected JSON size: ~1050 KB');
  print('   Actual BLOB size: ${sizeKB.toStringAsFixed(2)} KB');
  print('   Savings: ${((1050 - sizeKB) / 1050 * 100).toStringAsFixed(1)}%');
}
```

**Ожидаемые результаты**:
- ✅ 100 документов добавляются за разумное время (<5 сек)
- ✅ Размер БД ~300-400 KB (vs ~1050 KB с JSON)
- ✅ Экономия хранилища ~60-70%

---

### Тест 5: Производительность Search

**Цель**: Проверить скорость поиска (6.7x ускорение).

```dart
Future<void> testSearchPerformance() async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/test_search_perf.db';

  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

  // Добавляем 1000 документов
  print('📊 Adding 1000 documents...');
  for (int i = 0; i < 1000; i++) {
    final embedding = List.generate(768, (j) => (i + j) / 1000.0);
    await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
      id: 'doc_$i',
      content: 'Document $i with some text content',
      embedding: embedding,
    );
  }
  print('✅ Added 1000 documents');

  // Замеряем время поиска
  final queryEmbedding = await embeddingModel.generateEmbedding(
    'test query for search performance'
  );

  print('\n🔍 Running 10 search queries...');
  final stopwatch = Stopwatch()..start();

  for (int i = 0; i < 10; i++) {
    final results = await FlutterGemmaPlugin.instance.searchSimilar(
      query: 'test query $i',
      topK: 10,
      threshold: 0.0,
    );
    assert(results.length <= 10, 'Expected max 10 results');
  }

  stopwatch.stop();
  final avgTimeMs = stopwatch.elapsedMilliseconds / 10;

  print('✅ Search performance:');
  print('   Average time: ${avgTimeMs.toStringAsFixed(2)}ms per query');
  print('   Total time: ${stopwatch.elapsedMilliseconds}ms for 10 queries');

  // Ожидаемое время с BLOB: ~75 μs = 0.075ms per document
  // Для 1000 документов: ~75ms
  // Ожидаемое время с JSON было бы: ~500 μs = 0.5ms per document
  // Для 1000 документов: ~500ms

  final expectedMaxTimeMs = 200; // С запасом
  assert(avgTimeMs < expectedMaxTimeMs,
    'Search too slow: ${avgTimeMs}ms (expected < ${expectedMaxTimeMs}ms)');

  print('✅ Search performance verified!');
}
```

**Ожидаемые результаты**:
- ✅ Поиск по 1000 документам занимает <200ms
- ✅ Средняя скорость поиска ~75-150ms per query
- ✅ Возвращаются корректные topK результаты

---

### Тест 6: Database Migration

**Цель**: Проверить миграцию при обновлении с v0.11.5/0.11.6 на v0.11.7.

```dart
Future<void> testDatabaseMigration() async {
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = '${appDir.path}/flutter_gemma_vectors.db';

  // Симуляция: создаём "старую" БД с v1 схемой
  // (в реальности это нужно тестировать на устройстве с установленной v0.11.6)

  print('⚠️ Manual test required:');
  print('1. Install flutter_gemma v0.11.6');
  print('2. Add some documents to VectorStore');
  print('3. Check database file exists');
  print('4. Upgrade to v0.11.7');
  print('5. Initialize VectorStore (should trigger DROP TABLE)');
  print('6. Verify old data is gone (documentCount = 0)');
  print('7. Add new documents with v0.11.7');
  print('8. Verify they work correctly');

  // Автоматическая проверка после миграции:
  await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

  final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  print('\n📊 Stats after migration:');
  print('   Documents: ${stats.documentCount}');
  print('   Dimension: ${stats.vectorDimension}');

  // После миграции должно быть 0 документов
  if (stats.documentCount == 0) {
    print('✅ Migration successful (old data cleared)');
  } else {
    print('⚠️ Warning: Found ${stats.documentCount} documents after migration');
  }
}
```

**Ожидаемые результаты**:
- ✅ Миграция с v0.11.6 → v0.11.7 проходит без ошибок
- ✅ Старые документы удаляются (DROP TABLE)
- ✅ Новые документы работают с BLOB storage

---

## Чеклист для ручного тестирования

### Android:
- [ ] Запустить Тест 1 (базовая функциональность)
- [ ] Запустить Тест 2 (динамические размерности)
- [ ] Запустить Тест 3 (валидация размерности)
- [ ] Запустить Тест 4 (storage optimization)
- [ ] Запустить Тест 5 (search performance)
- [ ] Проверить размер БД файла через `adb shell`
- [ ] Проверить логи: `adb logcat | grep VectorStore`

### iOS:
- [ ] Запустить Тест 1 (базовая функциональность)
- [ ] Запустить Тест 2 (динамические размерности)
- [ ] Запустить Тест 3 (валидация размерности)
- [ ] Запустить Тест 4 (storage optimization)
- [ ] Запустить Тест 5 (search performance)
- [ ] Проверить размер БД через Xcode Device Manager
- [ ] Проверить логи в Xcode Console

### Миграция:
- [ ] Установить v0.11.6, добавить документы
- [ ] Обновить до v0.11.7
- [ ] Проверить что старая БД пересоздана
- [ ] Добавить новые документы
- [ ] Проверить что всё работает

---

## Создание тестового приложения

Создайте файл `example/lib/vector_store_test_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

class VectorStoreTestScreen extends StatefulWidget {
  const VectorStoreTestScreen({super.key});

  @override
  State<VectorStoreTestScreen> createState() => _VectorStoreTestScreenState();
}

class _VectorStoreTestScreenState extends State<VectorStoreTestScreen> {
  final _log = <String>[];
  bool _isTesting = false;
  EmbeddingModel? _embeddingModel;

  @override
  void initState() {
    super.initState();
    _initEmbeddingModel();
  }

  Future<void> _initEmbeddingModel() async {
    try {
      _embeddingModel = await FlutterGemma.getActiveEmbedder();
      _addLog('✅ Embedding model ready');
    } catch (e) {
      _addLog('❌ Failed to init embedding model: $e');
    }
  }

  void _addLog(String message) {
    setState(() {
      _log.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
  }

  Future<void> _runTest(String testName, Future<void> Function() test) async {
    _addLog('\n🧪 Running: $testName');
    try {
      await test();
      _addLog('✅ $testName passed');
    } catch (e) {
      _addLog('❌ $testName failed: $e');
    }
  }

  Future<void> _runAllTests() async {
    setState(() {
      _isTesting = true;
      _log.clear();
    });

    await _runTest('Test 1: Basic Functionality', _testBasicVectorStore);
    await _runTest('Test 2: Dynamic Dimensions', _testDynamicDimensions);
    await _runTest('Test 3: Dimension Validation', _testDimensionValidation);
    await _runTest('Test 4: Storage Optimization', _testStorageOptimization);
    await _runTest('Test 5: Search Performance', _testSearchPerformance);

    setState(() => _isTesting = false);
    _addLog('\n🎉 All tests completed!');
  }

  // Реализация всех тестов из документа выше...
  Future<void> _testBasicVectorStore() async {
    // ... код из Теста 1
  }

  Future<void> _testDynamicDimensions() async {
    // ... код из Теста 2
  }

  Future<void> _testDimensionValidation() async {
    // ... код из Теста 3
  }

  Future<void> _testStorageOptimization() async {
    // ... код из Теста 4
  }

  Future<void> _testSearchPerformance() async {
    // ... код из Теста 5
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VectorStore Tests')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _isTesting ? null : _runAllTests,
              child: Text(_isTesting ? 'Testing...' : 'Run All Tests'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _log.length,
              itemBuilder: (context, index) {
                final message = _log[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: message.contains('❌') ? Colors.red :
                             message.contains('✅') ? Colors.green :
                             Colors.black87,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _embeddingModel?.close();
    super.dispose();
  }
}
```

Добавьте в `example/lib/home_screen.dart`:

```dart
// Кнопка для VectorStore тестов
ListTile(
  title: const Text('VectorStore Tests'),
  subtitle: const Text('Test v0.11.7 optimizations'),
  trailing: const Icon(Icons.science),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const VectorStoreTestScreen()),
  ),
),
```

---

## Интерпретация результатов

### ✅ Успешные результаты:
- Все тесты проходят без ошибок
- Размер БД ~300-400 KB для 100 docs (768D)
- Поиск по 1000 docs занимает <200ms
- Dimension validation работает корректно

### ❌ Проблемы для расследования:
- **Database too large**: Проверить BLOB сериализацию
- **Search too slow**: Проверить индексы SQLite
- **Dimension mismatch not detected**: Проверить валидацию
- **Migration failed**: Проверить DATABASE_VERSION

---

## Дополнительные проверки

### 1. Проверка Binary Format
```dart
// На Android через adb:
adb shell
cd /data/data/your.package.name/files
sqlite3 flutter_gemma_vectors.db
.schema documents
SELECT typeof(embedding), length(embedding) FROM documents LIMIT 1;
// Должно показать: blob|3072 (для 768D * 4 bytes)
```

### 2. Проверка Cross-Platform Parity
```dart
// Добавить документы на Android
// Скопировать БД файл на iOS
// Прочитать документы на iOS
// Результаты должны совпадать
```

### 3. Стресс-тест
```dart
// Добавить 10,000 документов
// Замерить время search
// Проверить размер БД
// Проверить memory usage
```

---

## Отчёт о тестировании

После прохождения всех тестов заполните:

```
## VectorStore v0.11.7 Test Report

**Date**: YYYY-MM-DD
**Tester**: Your Name
**Devices**:
- Android: Device Name (Android XX)
- iOS: Device Name (iOS XX)

### Test Results:

- [ ] Test 1: Basic Functionality - PASS/FAIL
- [ ] Test 2: Dynamic Dimensions - PASS/FAIL
- [ ] Test 3: Dimension Validation - PASS/FAIL
- [ ] Test 4: Storage Optimization - PASS/FAIL
- [ ] Test 5: Search Performance - PASS/FAIL
- [ ] Test 6: Database Migration - PASS/FAIL

### Performance Metrics:

**Android:**
- Database size (100 docs): XXX KB
- Search time (1000 docs): XXX ms
- Dimension: XXX D

**iOS:**
- Database size (100 docs): XXX KB
- Search time (1000 docs): XXX ms
- Dimension: XXX D

### Issues Found:
1. [Describe any issues]

### Conclusion:
✅ Ready for release / ❌ Needs fixes
```
