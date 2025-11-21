import 'dart:js_interop';
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
    final jsStats = await getStats().toDart as JSObject;

    return VectorStoreStats(
      documentCount: getProperty<JSNumber>(jsStats, 'documentCount').toDartInt,
      vectorDimension: getProperty<JSNumber>(jsStats, 'vectorDimension').toDartInt,
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
    return RetrievalResult(
      id: getProperty<JSString>(jsObj, 'id').toDart,
      content: getProperty<JSString>(jsObj, 'content').toDart,
      similarity: getProperty<JSNumber>(jsObj, 'similarity').toDartDouble,
      metadata: _getOptionalString(jsObj, 'metadata'),
    );
  }

  /// Safely get optional string from JS object
  ///
  /// Returns null if key doesn't exist or value is null/undefined
  static String? _getOptionalString(JSObject jsObj, String key) {
    final jsValue = getPropertyOrNull(jsObj, key);
    if (jsValue == null) {
      return null;
    }
    final jsString = jsValue as JSString?;
    return jsString?.toDart;
  }
}

/// Helper functions for JS property access
T getProperty<T extends JSAny>(JSObject obj, String key) {
  return (obj as JSAny).getProperty(key.toJS) as T;
}

JSAny? getPropertyOrNull(JSObject obj, String key) {
  return (obj as JSAny).getProperty(key.toJS);
}

extension JSAnyExtension on JSAny {
  external JSAny? getProperty(JSString property);
}
