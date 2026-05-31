/// SQLite + HNSW on-device RAG vector store for flutter_gemma.
///
/// Opt-in package. Add it to pubspec.yaml and pass an instance to
/// `FlutterGemma.initialize(vectorStore: ...)`:
///
/// ```dart
/// import 'package:flutter_gemma/flutter_gemma.dart';
/// import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
///
/// await FlutterGemma.initialize(
///   vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
/// );
/// ```
library flutter_gemma_rag_sqlite;

// Exports are added in Tasks 3 (native) and 4 (web). Kept empty here so the
// package compiles standalone before the impls land.
