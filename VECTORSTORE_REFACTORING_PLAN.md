# VectorStore TDD Refactoring Plan

**Version:** 2.0
**Date:** 2025-11-19
**Status:** Draft - Updated with correct testing strategy

---

## Executive Summary

This document provides a **comprehensive, phased TDD plan** to refactor the VectorStore implementation with proper architectural patterns (Repository, ServiceRegistry integration, proper abstractions). The plan follows strict TDD methodology: RED (failing tests) → GREEN (minimal implementation) → REFACTOR (improve design).

### Current State Analysis

**Architectural Issues:**

1. **No Abstraction Layer**
   - Direct Pigeon calls from `FlutterGemmaPlugin.instance`
   - No `VectorStoreRepository` interface
   - No platform-specific implementations (mobile vs web)
   - Violates Dependency Inversion Principle (SOLID)

2. **Missing Functionality**
   - Android `VectorStore.kt` lacks `close()` method (memory leak)
   - No batch operations API (inefficient for bulk adds)
   - Metadata is `String?` instead of typed `Map<String, dynamic>`
   - No race condition protection on Android

3. **ServiceRegistry Integration**
   - VectorStore not registered in ServiceRegistry
   - No lifecycle management
   - No singleton pattern for database instance
   - No platform-aware factory

4. **Web Platform**
   - Completely unimplemented (`throw UnimplementedError`)
   - No IndexedDB backend
   - No cosine similarity implementation

5. **Testing Gaps**
   - No integration tests for end-to-end flows
   - No BLOB format compatibility tests
   - Only manual UI tests exist

### Success Criteria

- ✅ All existing manual tests converted to automated tests
- ✅ 100% backward compatible (no breaking changes)
- ✅ Clean architecture (Repository pattern, ServiceRegistry)
- ✅ Web platform fully implemented
- ✅ BLOB format cross-platform compatible
- ✅ All tests passing on iOS, Android, Web
- ✅ Performance metrics maintained/improved

---

## Architecture Overview

### Target Architecture (After Refactoring)

```
┌─────────────────────────────────────────────────────────────┐
│                    FlutterGemmaPlugin                        │
│              (Public API - no changes)                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                   ServiceRegistry                            │
│   - VectorStoreRepository (abstraction)                      │
│   - Lifecycle management                                     │
│   - Platform-aware factory                                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
┌───────▼──────────┐                 ┌─────────▼────────────┐
│ MobileVectorStore│                 │ WebVectorStoreRepository│
│   Repository     │                 │                      │
│ (Pigeon → native)│                 │ (IndexedDB backend)  │
└───────┬──────────┘                 └─────────┬────────────┘
        │                                       │
┌───────▼──────────┐                 ┌─────────▼────────────┐
│ iOS VectorStore  │                 │  IndexedDB API       │
│   (Swift)        │                 │  + JS Workers        │
└──────────────────┘                 └──────────────────────┘
        │
┌───────▼──────────┐
│Android VectorStore│
│   (Kotlin)       │
└──────────────────┘
```

### Key Design Patterns

1. **Repository Pattern**
   - `VectorStoreRepository` interface
   - Platform-specific implementations
   - Abstracts storage details

2. **Factory Pattern**
   - `ServiceFactory.createVectorStoreRepository()`
   - Platform-aware creation (mobile vs web)

3. **Singleton Pattern**
   - One database instance per application
   - Managed by ServiceRegistry lifecycle

4. **Strategy Pattern**
   - Different storage strategies (SQLite BLOB vs IndexedDB)
   - Same interface, different backends

---

## Testing Strategy: The Flutter Way

### Why No Native Unit Tests for VectorStore?

After analyzing sqflite (the gold standard for Flutter SQLite), we follow **The Flutter Way**:

**3-Level Testing Hierarchy:**

1. **Level 1: Integration Tests** (`example/integration_test/`)
   - E2E tests across Dart → Platform Channel → Native
   - Cross-platform (Android, iOS, Web)
   - Tests public API behavior
   - **This is where VectorStore should be tested**

2. **Level 2: Native Unit Tests** (`ios/Tests/`, `android/src/test/`)
   - ONLY for public, reusable utilities
   - Example: `sqflite/ios/Tests/SqfliteOperationTests.swift` tests `SqfliteOperation` (public utility)
   - **NOT for private implementation details**

3. **Level 3: Dart Unit Tests** (`test/`)
   - Tests Dart-only logic
   - No platform channels involved

### VectorStore Testing Decision

**Integration tests ONLY (Level 1):**

✅ **Why this is correct:**

1. **All VectorStore methods are PRIVATE** (not exposed as public utilities)
   - iOS: `VectorStore.swift` methods are internal to plugin
   - Android: `VectorStore.kt` methods are internal to plugin
   - They exist ONLY to serve the Dart API

2. **VectorUtils is a MATH LIBRARY** (like `Math.sqrt()`)
   - We don't unit test `Math.sqrt()` - we trust it
   - We don't unit test `VectorUtils.normalize()` - it's pure math
   - Integration tests verify math works end-to-end

3. **sqflite Precedent**
   - sqflite has NO tests for `SqfliteCursor`, `SqfliteDatabase` (private implementations)
   - sqflite ONLY tests public utilities like `SqfliteOperation`
   - They rely on integration tests for E2E verification

4. **Avoid Test Duplication**
   - Native unit tests would test same behavior as integration tests
   - Integration tests already verify BLOB encoding, cosine similarity, etc.
   - More tests ≠ better tests (maintenance burden)

❌ **Why native unit tests are WRONG here:**

```swift
// ios/Tests/VectorStoreUtilsTests.swift
// Tests public math library VectorUtils
// This is TESTING A PUBLIC LIBRARY, not VectorStore implementation
func testNormalize() {
    let input = [3.0, 4.0]
    let normalized = VectorUtils.normalize(input)
    // This is like testing Math.sqrt() - it's a math library!
}
```

```kotlin
// android/src/test/kotlin/.../VectorStoreUtilsTest.kt
// Tests PRIVATE methods (cosineSimilarity, normalizeVector)
// This is WRONG - private methods should be tested via public API
@Test
fun testCosineSimilarity() {
    val result = cosineSimilarity(listOf(1.0, 0.0), listOf(1.0, 0.0))
    // This is a PRIVATE method - should be tested via integration tests!
}
```

### Lessons Learned

**When to create native unit tests:**

✅ **DO** create native tests for:
- Public reusable utilities (like `sqflite/SqfliteOperation`)
- Complex algorithms that need fast iteration (TDD red-green-refactor)
- Platform-specific edge cases (device-specific bugs)

❌ **DON'T** create native tests for:
- Private implementation details (test via public API)
- Math libraries (trust the implementation, verify via integration)
- Simple CRUD operations (covered by integration tests)

**The Flutter Way:**
- Start with integration tests (E2E verification)
- Add native tests ONLY if you need faster iteration on complex logic
- Trust math libraries (don't test `Math.sqrt()`)
- Follow precedents (sqflite, path_provider, etc.)

---

## Phase 0: Regression Tests (RED Phase)

**Goal:** Lock down current behavior before refactoring

**Duration:** 1-2 days
**Risk:** Low (only adding tests, no code changes)
**Rollback:** Just delete test files

### Testing Approach

**ONLY Level 1 tests (integration tests)** because:
- All VectorStore methods are private (internal to plugin)
- VectorUtils is a trusted math library (like `Math.sqrt()`)
- Integration tests verify end-to-end behavior across platforms
- Follows sqflite precedent (no tests for private implementations)

### 0.1: Dart Integration Tests

**File to create:** `example/integration_test/vector_store_test.dart`

**Test Cases (10 tests):**

```dart
// example/integration_test/vector_store_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Skip on web platform (not implemented yet)
  final isWeb = !Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS;

  group('VectorStore Integration Tests', skip: isWeb, () {
    late String testDBPath;

    setUp(() async {
      final tempDir = await getTemporaryDirectory();
      testDBPath = '${tempDir.path}/test_${DateTime.now().millisecondsSinceEpoch}.db';
    });

    tearDown(() async {
      // Clean up test database
      final dbFile = File(testDBPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    });

    // ========================================================================
    // REGRESSION TESTS - Lock down current behavior
    // ========================================================================

    testWidgets('Test 1: Initialize and get stats from empty database', (tester) async {
      // Given: Initialize VectorStore
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      // When: Get stats from empty database
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      // Then: Should return 0 documents, 0 dimension
      expect(stats.documentCount, equals(0));
      expect(stats.vectorDimension, equals(0));
    });

    testWidgets('Test 2: Add document with 768D embedding', (tester) async {
      // Given: Initialized database
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      // When: Add document with 768D embedding
      final embedding = List.generate(768, (i) => i / 768.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Test document',
        embedding: embedding,
        metadata: '{"source": "test"}',
      );

      // Then: Stats should reflect the addition
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, equals(1));
      expect(stats.vectorDimension, equals(768));
    });

    testWidgets('Test 3: Auto-detect dimension from first document', (tester) async {
      // Given: Initialized database
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      // When: Add document with 256D embedding
      final embedding256 = List.generate(256, (i) => i / 256.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'First doc',
        embedding: embedding256,
      );

      // Then: Dimension should be auto-detected as 256
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.vectorDimension, equals(256));
    });

    testWidgets('Test 4: Dimension validation rejects mismatched dimensions', (tester) async {
      // Given: Database with 768D document
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final embedding768 = List.generate(768, (i) => i / 768.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'First doc',
        embedding: embedding768,
      );

      // When: Try to add 256D document
      final embedding256 = List.generate(256, (i) => i / 256.0);

      // Then: Should throw error with dimension mismatch message
      expect(
        () => FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: 'doc2',
          content: 'Second doc',
          embedding: embedding256,
        ),
        throwsA(
          predicate((e) =>
            e.toString().toLowerCase().contains('dimension') &&
            (e.toString().contains('768') || e.toString().contains('256'))
          ),
        ),
      );
    });

    testWidgets('Test 5: Cosine similarity search returns correct order', (tester) async {
      // Given: Database with 3 documents
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      // Documents with known similarity relationships
      final docs = [
        ('doc1', 'Apple fruit', [1.0, 0.0, 0.0]),
        ('doc2', 'Apple company', [0.9, 0.1, 0.0]),
        ('doc3', 'Orange fruit', [0.0, 1.0, 0.0]),
      ];

      for (final (id, content, embedding) in docs) {
        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: id,
          content: content,
          embedding: embedding,
        );
      }

      // When: Search with query embedding similar to "apple" vectors
      final queryEmbedding = [0.95, 0.05, 0.0];
      final results = await FlutterGemmaPlugin.instance.searchSimilarWithEmbedding(
        queryEmbedding: queryEmbedding,
        topK: 2,
        threshold: 0.0,
      );

      // Then: Should return doc2 first (highest similarity), doc1 second
      expect(results.length, equals(2));
      expect(results[0].id, equals('doc2'));
      expect(results[0].similarity, greaterThan(0.99)); // Very high similarity
      expect(results[1].id, equals('doc1'));
    });

    testWidgets('Test 6: Clear database removes all documents', (tester) async {
      // Given: Database with multiple documents
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final embedding = List.generate(768, (i) => i / 768.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Test 1',
        embedding: embedding,
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Test 2',
        embedding: embedding,
      );

      // When: Clear database
      await FlutterGemmaPlugin.instance.clearVectorStore();

      // Then: Should have 0 documents
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, equals(0));
    });

    testWidgets('Test 7: BLOB format maintains precision', (tester) async {
      // Given: Document with specific floating-point values
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final embedding = [1.0, 2.5, -0.5, 3.14159];
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Test',
        embedding: embedding,
      );

      // When: Search with identical embedding
      final results = await FlutterGemmaPlugin.instance.searchSimilarWithEmbedding(
        queryEmbedding: embedding,
        topK: 1,
        threshold: 0.0,
      );

      // Then: Should have perfect similarity (1.0) - verifies BLOB encoding/decoding
      expect(results.length, equals(1));
      expect(results[0].similarity, closeTo(1.0, 0.001));
    });

    testWidgets('Test 8: Metadata preservation', (tester) async {
      // Given: Document with JSON metadata
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final embedding = List.generate(768, (i) => i / 768.0);
      final metadata = '{"source": "test", "author": "claude", "version": 2}';

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Test document',
        embedding: embedding,
        metadata: metadata,
      );

      // When: Search for document
      final results = await FlutterGemmaPlugin.instance.searchSimilarWithEmbedding(
        queryEmbedding: embedding,
        topK: 1,
        threshold: 0.0,
      );

      // Then: Metadata should be preserved exactly
      expect(results.length, equals(1));
      expect(results[0].metadata, equals(metadata));
    });

    testWidgets('Test 9: Threshold filtering', (tester) async {
      // Given: Documents with different similarities
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Apple',
        embedding: [1.0, 0.0, 0.0],
      );
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc2',
        content: 'Orange',
        embedding: [0.0, 1.0, 0.0],
      );

      // When: Search with high threshold (0.9)
      final results = await FlutterGemmaPlugin.instance.searchSimilarWithEmbedding(
        queryEmbedding: [0.95, 0.05, 0.0],
        topK: 10,
        threshold: 0.9,
      );

      // Then: Should only return doc1 (high similarity), doc2 filtered out
      expect(results.length, equals(1));
      expect(results[0].id, equals('doc1'));
      expect(results[0].similarity, greaterThan(0.9));
    });

    testWidgets('Test 10: Multiple initializations reuse same database', (tester) async {
      // Given: Initialize and add document
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final embedding = List.generate(768, (i) => i / 768.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc1',
        content: 'Persistent doc',
        embedding: embedding,
      );

      // When: Re-initialize with same path (simulates app restart)
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      // Then: Document should still be there (database persisted)
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      expect(stats.documentCount, equals(1));
    });
  });
}
```

**Run tests:**

```bash
# iOS
flutter test integration_test/vector_store_test.dart --platform ios

# Android
flutter test integration_test/vector_store_test.dart --platform android

# All platforms
flutter test integration_test/
```

**Success criteria:**
- ✅ All 10 tests pass on iOS
- ✅ All 10 tests pass on Android
- ✅ Tests skip gracefully on web (not implemented yet)
- ✅ No flaky tests (run 10 times, all pass)
- ✅ Tests run in <10 seconds total

### 0.2: Phase 0 Completion Checklist

- [ ] Integration tests created and passing (10 tests)
- [ ] Tests run on iOS simulator
- [ ] Tests run on Android emulator
- [ ] Tests skip gracefully on web
- [ ] All tests documented with clear Given/When/Then
- [ ] No failing tests
- [ ] Tests are deterministic (same results every run)

**Deliverables:**

1. Test file:
   - `example/integration_test/vector_store_test.dart` (10 tests)

2. Test documentation:
   - `VECTORSTORE_TESTING_GUIDE.md` (how to run tests)
   - Updated `README.md` with testing instructions

3. Baseline metrics:
   - Test execution time (<10 seconds)
   - Platform coverage (iOS ✅, Android ✅, Web ⏸️)

**Estimated time:** 1-2 days (writing tests + debugging + documentation)

**Why only 10 tests instead of 29?**

- ❌ Removed iOS unit tests (10 tests) - private implementation details
- ❌ Removed Android unit tests (11 tests) - private implementation details
- ❌ Removed BLOB compatibility tests (2 tests) - covered by integration tests
- ❌ Removed duplicate Dart tests (6 tests) - merged into integration tests
- ✅ Kept 10 comprehensive E2E integration tests

The 10 integration tests cover:
1. Empty database behavior
2. Document addition
3. Dimension auto-detection
4. Dimension validation
5. Cosine similarity correctness
6. Clear operation
7. BLOB encoding/decoding precision
8. Metadata preservation
9. Threshold filtering
10. Database persistence

This is **100% sufficient** because:
- Tests real user flows (Dart → Platform Channel → Native)
- Verifies cross-platform compatibility
- Catches integration bugs (the most common type)
- Follows Flutter best practices (sqflite precedent)
- Low maintenance burden

---

## Phase 1: Refactoring Mobile Architecture (GREEN Phase)

**Goal:** Fix architecture without changing behavior (all Phase 0 tests stay green)

**Duration:** 5-7 days
**Risk:** Medium (code changes, but tests protect us)
**Rollback:** Git revert to Phase 0 tag

### 1.1: Create VectorStoreRepository Abstraction

**File to create:** `lib/core/services/vector_store_repository.dart`

```dart
// lib/core/services/vector_store_repository.dart

/// Abstract repository for vector store operations
///
/// Platform-specific implementations:
/// - Mobile: MobileVectorStoreRepository (via Pigeon)
/// - Web: WebVectorStoreRepository (IndexedDB)
abstract class VectorStoreRepository {
  /// Initialize vector store at given path
  ///
  /// - Mobile: Creates/opens SQLite database
  /// - Web: Opens IndexedDB database
  Future<void> initialize(String databasePath);

  /// Add document with embedding to vector store
  ///
  /// Throws [ArgumentError] if embedding dimension doesn't match existing documents
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata, // Changed from String?
  });

  /// Add multiple documents in batch (more efficient)
  ///
  /// Returns number of documents successfully added
  Future<int> addDocuments(List<VectorDocument> documents);

  /// Search for similar documents using cosine similarity
  ///
  /// Returns top [topK] results with similarity >= [threshold]
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  });

  /// Get vector store statistics
  Future<VectorStoreStats> getStats();

  /// Clear all documents from vector store
  Future<void> clear();

  /// Close vector store and release resources
  Future<void> close();

  /// Check if vector store is initialized
  bool get isInitialized;
}

/// Document to add to vector store
class VectorDocument {
  final String id;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;

  const VectorDocument({
    required this.id,
    required this.content,
    required this.embedding,
    this.metadata,
  });
}
```

**TDD Workflow:**

1. **RED**: Run Phase 0 tests - all should still pass
2. **GREEN**: Implement abstract interface only
3. **REFACTOR**: Add documentation and validation

**Success Criteria:**
- ✅ Interface compiles
- ✅ All Phase 0 tests still pass (no code changes yet)
- ✅ Documentation clear and complete

### 1.2: Implement MobileVectorStoreRepository

**File to create:** `lib/core/infrastructure/mobile_vector_store_repository.dart`

```dart
// lib/core/infrastructure/mobile_vector_store_repository.dart
import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'dart:convert';

/// Mobile implementation of VectorStoreRepository using Pigeon
///
/// Delegates to native iOS/Android VectorStore classes via Pigeon
class MobileVectorStoreRepository implements VectorStoreRepository {
  final PlatformService _platformService;
  bool _isInitialized = false;

  MobileVectorStoreRepository({
    PlatformService? platformService,
  }) : _platformService = platformService ?? PlatformService();

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    await _platformService.initializeVectorStore(databasePath);
    _isInitialized = true;
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    // Convert metadata to JSON string (backward compatible with Pigeon)
    final metadataJson = metadata != null ? jsonEncode(metadata) : null;

    await _platformService.addDocument(
      id: id,
      content: content,
      embedding: embedding,
      metadata: metadataJson,
    );
  }

  @override
  Future<int> addDocuments(List<VectorDocument> documents) async {
    // For now, add one by one (TODO: implement batch Pigeon method)
    int successCount = 0;
    for (final doc in documents) {
      try {
        await addDocument(
          id: doc.id,
          content: doc.content,
          embedding: doc.embedding,
          metadata: doc.metadata,
        );
        successCount++;
      } catch (e) {
        // Log error but continue
        print('Failed to add document ${doc.id}: $e');
      }
    }
    return successCount;
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    return await _platformService.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: topK,
      threshold: threshold,
    );
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    return await _platformService.getVectorStoreStats();
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized. Call initialize() first.');
    }

    await _platformService.clearVectorStore();
  }

  @override
  Future<void> close() async {
    if (!_isInitialized) {
      return; // Already closed
    }

    // TODO: Add Pigeon method to close native VectorStore
    // For now, just mark as uninitialized
    _isInitialized = false;
  }
}
```

**TDD Workflow:**

1. **RED**: All Phase 0 tests should still pass (implementation is wrapper)
2. **GREEN**: Ensure all methods delegate correctly
3. **REFACTOR**: Add error handling and logging

**Success Criteria:**
- ✅ All Phase 0 tests still pass
- ✅ No behavioral changes
- ✅ Clean delegation to Pigeon

### 1.3: Integrate with ServiceRegistry

**File to modify:** `lib/core/di/service_registry.dart`

Add VectorStoreRepository to ServiceRegistry:

```dart
// lib/core/di/service_registry.dart

class ServiceRegistry {
  // ... existing services

  late final VectorStoreRepository _vectorStoreRepository;

  Future<void> initialize({
    // ... existing parameters
    VectorStoreRepository? vectorStoreRepository,
  }) async {
    // ... existing initialization

    // Initialize VectorStoreRepository
    _vectorStoreRepository = vectorStoreRepository ??
      (kIsWeb
        ? WebVectorStoreRepository() // TODO: implement in Phase 2
        : MobileVectorStoreRepository());
  }

  VectorStoreRepository get vectorStoreRepository => _vectorStoreRepository;

  Future<void> dispose() async {
    // ... existing disposal

    await _vectorStoreRepository.close();
  }
}
```

**TDD Workflow:**

1. **RED**: Run Phase 0 tests - should fail (missing WebVectorStoreRepository)
2. **GREEN**: Add stub WebVectorStoreRepository
3. **REFACTOR**: Update FlutterGemmaPlugin to use repository

**Success Criteria:**
- ✅ All Phase 0 tests pass
- ✅ VectorStore accessed via ServiceRegistry
- ✅ Singleton pattern enforced

### 1.4: Add Android close() Method

**File to modify:** `android/src/main/kotlin/dev/flutterberlin/flutter_gemma/VectorStore.kt`

Add close() method to prevent memory leaks:

```kotlin
// android/src/main/kotlin/dev/flutterberlin/flutter_gemma/VectorStore.kt

class VectorStore(private val context: Context) {
    private var database: SQLiteDatabase? = null

    // ... existing methods

    fun close() {
        database?.close()
        database = null
    }
}
```

Update Pigeon API:

```dart
// pigeons/messages.dart

@HostApi()
abstract class PlatformService {
  // ... existing methods

  @async
  void closeVectorStore();
}
```

Regenerate Pigeon:

```bash
flutter pub run pigeon --input pigeons/messages.dart
```

**TDD Workflow:**

1. **RED**: Add test for close() method
2. **GREEN**: Implement close()
3. **REFACTOR**: Ensure all resources released

**Success Criteria:**
- ✅ close() method implemented
- ✅ No database leaks (verify with Android Studio Profiler)
- ✅ All Phase 0 tests still pass

### 1.5: Phase 1 Completion Checklist

- [ ] VectorStoreRepository interface created
- [ ] MobileVectorStoreRepository implemented
- [ ] ServiceRegistry integration complete
- [ ] Android close() method added
- [ ] All Phase 0 tests still pass (GREEN!)
- [ ] No behavioral changes (100% backward compatible)
- [ ] Code coverage maintained/improved
- [ ] Documentation updated

**Estimated time:** 5-7 days

---

## Phase 2: Web Platform Implementation (RED → GREEN)

**Goal:** Implement VectorStore for web platform

**Duration:** 7-10 days
**Risk:** High (new platform, complex IndexedDB)
**Rollback:** Git revert to Phase 1 tag

### 2.1: IndexedDB Schema Design

**Database Schema:**

```javascript
// web/vector_store_db.js

const DB_NAME = 'flutter_gemma_vector_store';
const DB_VERSION = 1;
const STORE_NAME = 'documents';
const INDEX_NAME = 'by_id';

const schema = {
  documents: {
    keyPath: 'id',
    indexes: [
      { name: 'by_id', keyPath: 'id', unique: true }
    ],
    fields: {
      id: 'string',
      content: 'string',
      embedding: 'Float32Array', // Binary storage for efficiency
      metadata: 'object | null',
      createdAt: 'number' // timestamp
    }
  },
  metadata: {
    keyPath: 'key',
    fields: {
      key: 'string',
      value: 'any'
    }
  }
};

// Store dimension in metadata store
// Key: 'vector_dimension', Value: number
```

**Why IndexedDB?**
- Native browser storage (no external dependencies)
- Supports binary data (Float32Array for embeddings)
- Asynchronous API (non-blocking)
- Good performance for vector operations

### 2.2: Implement WebVectorStoreRepository

**File to create:** `lib/web/infrastructure/web_vector_store_repository.dart`

```dart
// lib/web/infrastructure/web_vector_store_repository.dart

import 'package:flutter_gemma/core/services/vector_store_repository.dart';
import 'package:flutter_gemma/web/vector_store_js.dart';
import 'dart:js_util' as js_util;

/// Web implementation of VectorStoreRepository using IndexedDB
class WebVectorStoreRepository implements VectorStoreRepository {
  bool _isInitialized = false;
  String? _databasePath;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize(String databasePath) async {
    _databasePath = databasePath;

    // Initialize IndexedDB
    await js_util.promiseToFuture(
      js_util.callMethod(
        window,
        'initializeVectorStore',
        [databasePath],
      ),
    );

    _isInitialized = true;
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized');
    }

    // Convert to Float32Array for efficient storage
    final embeddingArray = js_util.newObject();
    js_util.setProperty(embeddingArray, 'type', 'Float32Array');
    js_util.setProperty(embeddingArray, 'data', embedding);

    await js_util.promiseToFuture(
      js_util.callMethod(
        window,
        'addDocument',
        [id, content, embeddingArray, metadata],
      ),
    );
  }

  @override
  Future<List<RetrievalResult>> searchSimilar({
    required List<double> queryEmbedding,
    required int topK,
    double threshold = 0.0,
  }) async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized');
    }

    // Call JS method to perform search
    final results = await js_util.promiseToFuture(
      js_util.callMethod(
        window,
        'searchSimilar',
        [queryEmbedding, topK, threshold],
      ),
    );

    // Convert JS results to Dart objects
    return _parseResults(results);
  }

  @override
  Future<VectorStoreStats> getStats() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized');
    }

    final stats = await js_util.promiseToFuture(
      js_util.callMethod(window, 'getVectorStoreStats', []),
    );

    return VectorStoreStats(
      documentCount: js_util.getProperty(stats, 'documentCount'),
      vectorDimension: js_util.getProperty(stats, 'vectorDimension'),
    );
  }

  @override
  Future<void> clear() async {
    if (!_isInitialized) {
      throw StateError('VectorStore not initialized');
    }

    await js_util.promiseToFuture(
      js_util.callMethod(window, 'clearVectorStore', []),
    );
  }

  @override
  Future<void> close() async {
    if (!_isInitialized) {
      return;
    }

    await js_util.promiseToFuture(
      js_util.callMethod(window, 'closeVectorStore', []),
    );

    _isInitialized = false;
  }

  @override
  Future<int> addDocuments(List<VectorDocument> documents) async {
    int successCount = 0;
    for (final doc in documents) {
      try {
        await addDocument(
          id: doc.id,
          content: doc.content,
          embedding: doc.embedding,
          metadata: doc.metadata,
        );
        successCount++;
      } catch (e) {
        print('Failed to add document ${doc.id}: $e');
      }
    }
    return successCount;
  }

  List<RetrievalResult> _parseResults(dynamic jsResults) {
    final results = <RetrievalResult>[];
    final length = js_util.getProperty(jsResults, 'length') as int;

    for (int i = 0; i < length; i++) {
      final jsResult = js_util.getProperty(jsResults, i.toString());
      results.add(
        RetrievalResult(
          id: js_util.getProperty(jsResult, 'id'),
          content: js_util.getProperty(jsResult, 'content'),
          similarity: js_util.getProperty(jsResult, 'similarity'),
          metadata: js_util.getProperty(jsResult, 'metadata'),
        ),
      );
    }

    return results;
  }
}
```

### 2.3: JavaScript IndexedDB Implementation

**File to create:** `web/vector_store_js.js`

```javascript
// web/vector_store_js.js

const DB_NAME = 'flutter_gemma_vector_store';
const DB_VERSION = 1;
const DOCUMENTS_STORE = 'documents';
const METADATA_STORE = 'metadata';

let db = null;
let vectorDimension = 0;

// Initialize IndexedDB
window.initializeVectorStore = async function(databasePath) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME + '_' + databasePath, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      db = request.result;
      loadMetadata().then(resolve).catch(reject);
    };

    request.onupgradeneeded = (event) => {
      const db = event.target.result;

      // Documents store
      if (!db.objectStoreNames.contains(DOCUMENTS_STORE)) {
        const store = db.createObjectStore(DOCUMENTS_STORE, { keyPath: 'id' });
        store.createIndex('by_id', 'id', { unique: true });
      }

      // Metadata store
      if (!db.objectStoreNames.contains(METADATA_STORE)) {
        db.createObjectStore(METADATA_STORE, { keyPath: 'key' });
      }
    };
  });
};

// Load metadata (dimension)
async function loadMetadata() {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([METADATA_STORE], 'readonly');
    const store = transaction.objectStore(METADATA_STORE);
    const request = store.get('vector_dimension');

    request.onsuccess = () => {
      vectorDimension = request.result?.value || 0;
      resolve();
    };
    request.onerror = () => reject(request.error);
  });
}

// Save metadata (dimension)
async function saveMetadata(dimension) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([METADATA_STORE], 'readwrite');
    const store = transaction.objectStore(METADATA_STORE);
    const request = store.put({ key: 'vector_dimension', value: dimension });

    request.onsuccess = () => {
      vectorDimension = dimension;
      resolve();
    };
    request.onerror = () => reject(request.error);
  });
}

// Add document
window.addDocument = async function(id, content, embedding, metadata) {
  // Validate dimension
  const embeddingArray = new Float32Array(embedding.data);
  const dimension = embeddingArray.length;

  if (vectorDimension === 0) {
    await saveMetadata(dimension);
  } else if (vectorDimension !== dimension) {
    throw new Error(
      `Dimension mismatch: expected ${vectorDimension}, got ${dimension}`
    );
  }

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([DOCUMENTS_STORE], 'readwrite');
    const store = transaction.objectStore(DOCUMENTS_STORE);

    const document = {
      id,
      content,
      embedding: embeddingArray,
      metadata: metadata || null,
      createdAt: Date.now()
    };

    const request = store.put(document);
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};

// Cosine similarity
function cosineSimilarity(a, b) {
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}

// Search similar documents
window.searchSimilar = async function(queryEmbedding, topK, threshold) {
  const query = new Float32Array(queryEmbedding);

  return new Promise((resolve, reject) => {
    const transaction = db.transaction([DOCUMENTS_STORE], 'readonly');
    const store = transaction.objectStore(DOCUMENTS_STORE);
    const request = store.getAll();

    request.onsuccess = () => {
      const documents = request.result;

      // Calculate similarities
      const results = documents.map(doc => ({
        id: doc.id,
        content: doc.content,
        metadata: doc.metadata,
        similarity: cosineSimilarity(query, doc.embedding)
      }));

      // Filter by threshold
      const filtered = results.filter(r => r.similarity >= threshold);

      // Sort by similarity (descending) and take topK
      const sorted = filtered
        .sort((a, b) => b.similarity - a.similarity)
        .slice(0, topK);

      resolve(sorted);
    };

    request.onerror = () => reject(request.error);
  });
};

// Get stats
window.getVectorStoreStats = async function() {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([DOCUMENTS_STORE], 'readonly');
    const store = transaction.objectStore(DOCUMENTS_STORE);
    const request = store.count();

    request.onsuccess = () => {
      resolve({
        documentCount: request.result,
        vectorDimension: vectorDimension
      });
    };

    request.onerror = () => reject(request.error);
  });
};

// Clear all documents
window.clearVectorStore = async function() {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction([DOCUMENTS_STORE], 'readwrite');
    const store = transaction.objectStore(DOCUMENTS_STORE);
    const request = store.clear();

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
};

// Close database
window.closeVectorStore = async function() {
  if (db) {
    db.close();
    db = null;
  }
  vectorDimension = 0;
};
```

### 2.4: Update index.html

**File to modify:** `example/web/index.html`

```html
<!-- example/web/index.html -->
<!DOCTYPE html>
<html>
<head>
  <!-- ... existing head content ... -->

  <!-- VectorStore IndexedDB API -->
  <script src="vector_store_js.js" defer></script>
</head>
<body>
  <!-- ... existing body content ... -->
</body>
</html>
```

### 2.5: Enable Web Tests

Update Phase 0 tests to run on web:

```dart
// example/integration_test/vector_store_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ✅ NOW RUNS ON WEB TOO!
  group('VectorStore Integration Tests', () {
    // ... same tests as before
  });
}
```

**Run web tests:**

```bash
flutter test integration_test/vector_store_test.dart -d chrome
```

### 2.6: Phase 2 Completion Checklist

- [ ] IndexedDB schema designed
- [ ] WebVectorStoreRepository implemented
- [ ] JavaScript IndexedDB implementation complete
- [ ] All Phase 0 tests pass on web
- [ ] Performance acceptable (vs mobile)
- [ ] Memory usage verified (Chrome DevTools)
- [ ] Cross-browser testing (Chrome, Firefox, Safari)
- [ ] Documentation updated

**Estimated time:** 7-10 days

---

## Phase 3: Advanced Features (REFACTOR Phase)

**Goal:** Add batch operations, improved metadata, race condition protection

**Duration:** 5-7 days
**Risk:** Low (optional improvements)
**Rollback:** Git revert to Phase 2 tag

### 3.1: Batch Operations

Add batch insert API for efficiency:

**Pigeon API update:**

```dart
// pigeons/messages.dart

@HostApi()
abstract class PlatformService {
  // ... existing methods

  @async
  int addDocumentsBatch(List<VectorDocument> documents);
}
```

**Native implementations:**

iOS (Swift):
```swift
// ios/Classes/VectorStore.swift

func addDocumentsBatch(_ documents: [VectorDocument]) throws -> Int {
    var successCount = 0

    try db.transaction {
        for document in documents {
            do {
                try addDocument(
                    id: document.id,
                    content: document.content,
                    embedding: document.embedding,
                    metadata: document.metadata
                )
                successCount += 1
            } catch {
                // Log error but continue
                print("Failed to add document \(document.id): \(error)")
            }
        }
    }

    return successCount
}
```

Android (Kotlin):
```kotlin
// android/src/main/kotlin/.../VectorStore.kt

fun addDocumentsBatch(documents: List<VectorDocument>): Int {
    var successCount = 0

    database?.beginTransaction()
    try {
        for (document in documents) {
            try {
                addDocument(
                    id = document.id,
                    content = document.content,
                    embedding = document.embedding,
                    metadata = document.metadata
                )
                successCount++
            } catch (e: Exception) {
                // Log error but continue
                Log.e(TAG, "Failed to add document ${document.id}", e)
            }
        }
        database?.setTransactionSuccessful()
    } finally {
        database?.endTransaction()
    }

    return successCount
}
```

Web (JavaScript):
```javascript
// web/vector_store_js.js

window.addDocumentsBatch = async function(documents) {
  let successCount = 0;

  const transaction = db.transaction([DOCUMENTS_STORE], 'readwrite');
  const store = transaction.objectStore(DOCUMENTS_STORE);

  for (const doc of documents) {
    try {
      const embeddingArray = new Float32Array(doc.embedding.data);

      await new Promise((resolve, reject) => {
        const request = store.put({
          id: doc.id,
          content: doc.content,
          embedding: embeddingArray,
          metadata: doc.metadata || null,
          createdAt: Date.now()
        });

        request.onsuccess = () => {
          successCount++;
          resolve();
        };
        request.onerror = () => reject(request.error);
      });
    } catch (e) {
      console.error(`Failed to add document ${doc.id}:`, e);
    }
  }

  return successCount;
};
```

**Add test:**

```dart
// example/integration_test/vector_store_test.dart

testWidgets('Test 11: Batch add documents', (tester) async {
  await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

  // Given: 100 documents
  final documents = List.generate(100, (i) {
    final embedding = List.generate(768, (j) => (i + j) / 768.0);
    return VectorDocument(
      id: 'doc_$i',
      content: 'Document $i',
      embedding: embedding,
    );
  });

  // When: Add in batch
  final startTime = DateTime.now();
  final successCount = await FlutterGemmaPlugin.instance.addDocumentsBatch(documents);
  final duration = DateTime.now().difference(startTime);

  // Then: All should succeed
  expect(successCount, equals(100));

  final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  expect(stats.documentCount, equals(100));

  // Should be faster than individual adds
  print('Batch add duration: ${duration.inMilliseconds}ms');
});
```

### 3.2: Typed Metadata

Change metadata from `String?` to `Map<String, dynamic>?`:

**Pigeon API update:**

```dart
// pigeons/messages.dart

class VectorDocument {
  final String id;
  final String content;
  final List<double> embedding;
  final Map<String, Object?>? metadata; // Changed from String?
}
```

**Migration strategy:**

1. Add new methods with typed metadata
2. Deprecate old methods with String metadata
3. Keep backward compatibility for 2 releases
4. Remove deprecated methods in v0.13.0

### 3.3: Race Condition Protection

Add mutex/lock for Android database access:

```kotlin
// android/src/main/kotlin/.../VectorStore.kt

import java.util.concurrent.locks.ReentrantReadWriteLock

class VectorStore(private val context: Context) {
    private var database: SQLiteDatabase? = null
    private val lock = ReentrantReadWriteLock()

    fun addDocument(...) {
        lock.writeLock().lock()
        try {
            // ... existing code
        } finally {
            lock.writeLock().unlock()
        }
    }

    fun searchSimilar(...): List<RetrievalResult> {
        lock.readLock().lock()
        try {
            // ... existing code
        } finally {
            lock.readLock().unlock()
        }
    }
}
```

**Add concurrency test:**

```dart
// example/integration_test/vector_store_test.dart

testWidgets('Test 12: Concurrent access safety', (tester) async {
  await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

  // Given: 10 concurrent operations
  final futures = <Future>[];

  for (int i = 0; i < 10; i++) {
    futures.add(
      FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_$i',
        content: 'Document $i',
        embedding: List.generate(768, (j) => (i + j) / 768.0),
      )
    );
  }

  // When: Execute all at once
  await Future.wait(futures);

  // Then: All should succeed without database corruption
  final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
  expect(stats.documentCount, equals(10));
});
```

### 3.4: Phase 3 Completion Checklist

- [ ] Batch operations implemented (all platforms)
- [ ] Typed metadata API added
- [ ] Race condition protection added (Android)
- [ ] All Phase 0-2 tests still pass
- [ ] New tests for Phase 3 features pass
- [ ] Performance improvements verified
- [ ] Documentation updated

**Estimated time:** 5-7 days

---

## Phase 4: Performance Optimization (REFACTOR Phase)

**Goal:** Optimize performance for production use

**Duration:** 3-5 days
**Risk:** Low (only optimizations)
**Rollback:** Git revert to Phase 3 tag

### 4.1: Web Worker for Search

Move search computation to Web Worker (non-blocking UI):

**File to create:** `web/vector_search_worker.js`

```javascript
// web/vector_search_worker.js

self.addEventListener('message', function(e) {
  const { type, data } = e.data;

  if (type === 'search') {
    const results = performSearch(data.documents, data.query, data.topK, data.threshold);
    self.postMessage({ type: 'results', data: results });
  }
});

function performSearch(documents, queryEmbedding, topK, threshold) {
  const query = new Float32Array(queryEmbedding);

  // Calculate similarities
  const results = documents.map(doc => ({
    id: doc.id,
    content: doc.content,
    metadata: doc.metadata,
    similarity: cosineSimilarity(query, new Float32Array(doc.embedding))
  }));

  // Filter and sort
  return results
    .filter(r => r.similarity >= threshold)
    .sort((a, b) => b.similarity - a.similarity)
    .slice(0, topK);
}

function cosineSimilarity(a, b) {
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;

  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}
```

**Update vector_store_js.js:**

```javascript
// web/vector_store_js.js

let searchWorker = null;

function initializeWorker() {
  searchWorker = new Worker('vector_search_worker.js');
}

window.searchSimilar = async function(queryEmbedding, topK, threshold) {
  if (!searchWorker) initializeWorker();

  // Load all documents
  const documents = await new Promise((resolve, reject) => {
    const transaction = db.transaction([DOCUMENTS_STORE], 'readonly');
    const store = transaction.objectStore(DOCUMENTS_STORE);
    const request = store.getAll();

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  // Offload search to worker
  return new Promise((resolve, reject) => {
    searchWorker.onmessage = function(e) {
      if (e.data.type === 'results') {
        resolve(e.data.data);
      }
    };

    searchWorker.postMessage({
      type: 'search',
      data: { documents, query: queryEmbedding, topK, threshold }
    });
  });
};
```

### 4.2: iOS/Android Indexing

Add B-tree index for faster lookups:

**iOS:**
```swift
// ios/Classes/VectorStore.swift

func createIndices() throws {
    // Index on document ID for fast lookups
    try db.run("""
        CREATE INDEX IF NOT EXISTS idx_documents_id ON documents(id)
    """)
}
```

**Android:**
```kotlin
// android/src/main/kotlin/.../VectorStore.kt

private fun createIndices() {
    database?.execSQL(
        "CREATE INDEX IF NOT EXISTS idx_documents_id ON documents(id)"
    )
}
```

### 4.3: Benchmark Tests

Add performance benchmarks:

```dart
// example/integration_test/vector_store_benchmark_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('VectorStore Benchmarks', () {
    testWidgets('Benchmark: Add 1000 documents', (tester) async {
      await FlutterGemmaPlugin.instance.initializeVectorStore(testDBPath);

      final documents = List.generate(1000, (i) {
        return VectorDocument(
          id: 'doc_$i',
          content: 'Document $i',
          embedding: List.generate(768, (j) => (i + j) / 768.0),
        );
      });

      final startTime = DateTime.now();
      await FlutterGemmaPlugin.instance.addDocumentsBatch(documents);
      final duration = DateTime.now().difference(startTime);

      print('Add 1000 documents: ${duration.inMilliseconds}ms');
      expect(duration.inMilliseconds, lessThan(5000)); // <5s
    });

    testWidgets('Benchmark: Search in 10K documents', (tester) async {
      // Add 10K documents
      // ...

      final queryEmbedding = List.generate(768, (i) => i / 768.0);

      final startTime = DateTime.now();
      final results = await FlutterGemmaPlugin.instance.searchSimilarWithEmbedding(
        queryEmbedding: queryEmbedding,
        topK: 10,
        threshold: 0.0,
      );
      final duration = DateTime.now().difference(startTime);

      print('Search 10K documents: ${duration.inMilliseconds}ms');
      expect(duration.inMilliseconds, lessThan(1000)); // <1s
    });
  });
}
```

### 4.4: Phase 4 Completion Checklist

- [ ] Web Worker implemented
- [ ] Database indices added
- [ ] Benchmark tests added
- [ ] Performance targets met
- [ ] All previous tests still pass
- [ ] Documentation updated with benchmarks

**Estimated time:** 3-5 days

---

## Overall Timeline

| Phase | Duration | Risk | Dependencies |
|-------|----------|------|--------------|
| Phase 0: Regression Tests | 1-2 days | Low | None |
| Phase 1: Mobile Refactoring | 5-7 days | Medium | Phase 0 |
| Phase 2: Web Implementation | 7-10 days | High | Phase 1 |
| Phase 3: Advanced Features | 5-7 days | Low | Phase 2 |
| Phase 4: Optimization | 3-5 days | Low | Phase 3 |

**Total: 21-31 days (4-6 weeks)**

---

## Success Metrics

### Code Quality
- ✅ All tests passing (10 integration tests + future additions)
- ✅ Code coverage >80%
- ✅ No breaking changes (100% backward compatible)
- ✅ Clean architecture (SOLID principles)

### Performance
- ✅ Add 1000 documents in <5 seconds
- ✅ Search 10K documents in <1 second
- ✅ Memory usage <100MB (10K documents)

### Platform Coverage
- ✅ iOS: Full support
- ✅ Android: Full support
- ✅ Web: Full support

---

## Risk Mitigation

### High-Risk Areas

1. **Web IndexedDB complexity**
   - **Mitigation:** Start with simple schema, iterate
   - **Fallback:** Use localStorage for small datasets

2. **BLOB format compatibility**
   - **Mitigation:** Integration tests verify cross-platform
   - **Fallback:** Document format spec for debugging

3. **Performance at scale**
   - **Mitigation:** Benchmark tests catch regressions
   - **Fallback:** Warn users about large dataset limits

### Rollback Strategy

Each phase is git-tagged:
- `vectorstore-phase-0` - Regression tests
- `vectorstore-phase-1` - Mobile refactoring
- `vectorstore-phase-2` - Web implementation
- `vectorstore-phase-3` - Advanced features
- `vectorstore-phase-4` - Optimization

Rollback:
```bash
git revert --no-commit <phase-tag>..HEAD
git commit -m "Rollback to Phase N"
```

---

## Next Steps

1. **Approval**: Review this plan with team
2. **Phase 0**: Start with regression tests (1-2 days)
3. **Iterate**: Complete each phase, validate with tests
4. **Monitor**: Track metrics and adjust timeline
5. **Document**: Update CLAUDE.md with decisions

---

## Appendix A: File Structure After Refactoring

```
flutter_gemma/
├── lib/
│   ├── core/
│   │   ├── services/
│   │   │   └── vector_store_repository.dart (new)
│   │   └── infrastructure/
│   │       └── mobile_vector_store_repository.dart (new)
│   ├── web/
│   │   └── infrastructure/
│   │       └── web_vector_store_repository.dart (new)
│   └── flutter_gemma.dart
├── web/
│   ├── vector_store_js.js (new)
│   └── vector_search_worker.js (new)
├── example/
│   └── integration_test/
│       ├── vector_store_test.dart (new - 10+ tests)
│       └── vector_store_benchmark_test.dart (new)
├── ios/
│   └── Classes/
│       └── VectorStore.swift (modified - add close())
├── android/
│   └── src/
│       └── main/
│           └── kotlin/
│               └── VectorStore.kt (modified - add close(), locks)
└── VECTORSTORE_TESTING_GUIDE.md (new)
```

---

## Appendix B: Resources

### Flutter Testing Best Practices
- [Flutter Integration Tests](https://docs.flutter.dev/testing/integration-tests)
- [sqflite Testing Strategy](https://github.com/tekartik/sqflite/tree/master/sqflite/test)

### IndexedDB Resources
- [MDN IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)
- [IndexedDB Best Practices](https://web.dev/indexeddb-best-practices/)

### Architecture Patterns
- [Repository Pattern in Flutter](https://medium.com/flutter-community/repository-design-pattern-in-flutter-2c0e2a1b9b0e)
- [Clean Architecture in Flutter](https://resocoder.com/2019/08/27/flutter-tdd-clean-architecture-course-1-explanation-project-structure/)

---

**End of Document**
