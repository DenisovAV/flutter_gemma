import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_gemma/pigeon.g.dart';

/// JS Interop for SQLiteVectorStore (wa-sqlite WASM)
///
/// **Architecture**:
/// ```
/// WebVectorStoreRepository (Dart)
///         ↓
/// vector_store_web.dart (JS interop)
///         ↓
/// sqlite_vector_store.js (wa-sqlite)
///         ↓
/// SQLite WASM + OPFS
/// ```
///
/// **Type Safety**:
/// - Extension types for zero-cost JS interop (Dart 3.3+)
/// - Automatic type conversion between Dart ↔ JS
/// - Promise → Future conversion via .toDart
///
/// **Error Handling**:
/// - JS errors propagate as Dart exceptions
/// - No silent failures
@JS('SQLiteVectorStore')
extension type SQLiteVectorStore._(JSObject _) implements JSObject {
  /// Create new SQLiteVectorStore instance
  ///
  /// Parameters:
  /// - [dimension]: Optional fixed dimension (null = auto-detect)
  external SQLiteVectorStore(JSNumber? dimension);

  // ========================================================================
  // Raw JS Methods (external declarations)
  // ========================================================================

  external JSPromise<JSAny?> initialize(String databasePath);

  external JSPromise<JSAny?> addDocument(
    String id,
    String content,
    JSArray<JSNumber> embedding,
    String? metadata,
  );

  external JSPromise<JSArray<JSObject>> searchSimilar(
    JSArray<JSNumber> queryEmbedding,
    JSNumber topK,
    JSNumber threshold,
  );

  external JSPromise<JSAny?> getStats();

  external JSPromise<JSAny?> clear();

  external JSPromise<JSAny?> close();

  // ========================================================================
  // Dart Helper Methods (type conversion wrappers)
  // ========================================================================

  /// Add document with embedding (Dart-friendly API)
  ///
  /// Type conversions:
  /// - Dart List<double> → JS Array<JSNumber>
  /// - Dart String? → JS String | null
  ///
  /// Throws:
  /// - Dimension mismatch
  /// - Database not initialized
  Future<void> addDocumentDart(
    String id,
    String content,
    List<double> embedding,
    String? metadata,
  ) async {
    final jsEmbedding = embedding.map((e) => e.toJS).toList().toJS;
    await addDocument(id, content, jsEmbedding, metadata).toDart;
  }

  /// Search for similar documents (Dart-friendly API)
  ///
  /// Type conversions:
  /// - Dart List<double> → JS Array<JSNumber>
  /// - Dart int → JS Number
  /// - Dart double → JS Number
  /// - JS Array<JSObject> → Dart List<RetrievalResult>
  ///
  /// Returns:
  /// - List sorted by similarity (descending)
  /// - Limited to topK results
  Future<List<RetrievalResult>> searchSimilarDart(
    List<double> queryEmbedding,
    int topK,
    double threshold,
  ) async {
    final jsQuery = queryEmbedding.map((e) => e.toJS).toList().toJS;
    final jsResults = await searchSimilar(
      jsQuery,
      topK.toJS,
      threshold.toJS,
    ).toDart;

    return jsResults.toDart
        .map((jsObj) => _parseRetrievalResult(jsObj))
        .toList();
  }

  /// Get vector store statistics (Dart-friendly API)
  ///
  /// Returns:
  /// - documentCount: Total documents
  /// - vectorDimension: Detected dimension (0 if empty)
  Future<VectorStoreStats> getStatsDart() async {
    final jsStats = await getStats().toDart;

    // Use js_interop_unsafe for property access
    final statsObj = jsStats as JSObject;
    final docCount = statsObj['documentCount'];
    final vecDim = statsObj['vectorDimension'];

    return VectorStoreStats(
      documentCount: (docCount as JSNumber).toDartInt,
      vectorDimension: (vecDim as JSNumber).toDartInt,
    );
  }

  // ========================================================================
  // Private Helpers
  // ========================================================================

  /// Parse JS object to RetrievalResult
  ///
  /// JS object structure:
  /// ```javascript
  /// {
  ///   id: string,
  ///   content: string,
  ///   similarity: number,
  ///   metadata: string | null
  /// }
  /// ```
  static RetrievalResult _parseRetrievalResult(JSObject jsObj) {
    final metadata = jsObj['metadata'];
    return RetrievalResult(
      id: (jsObj['id'] as JSString).toDart,
      content: (jsObj['content'] as JSString).toDart,
      similarity: (jsObj['similarity'] as JSNumber).toDartDouble,
      metadata: metadata.isNull ? null : (metadata as JSString).toDart,
    );
  }

}
