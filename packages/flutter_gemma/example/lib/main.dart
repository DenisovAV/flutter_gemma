import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_example/home_screen.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flutter Gemma.
  //
  // `WebStorageMode.streaming` (OPFS-backed) is required for `.litertlm`
  // web models in 0.16.2+ — the @litert-lm/core engine consumes a
  // ReadableStream from OPFS, avoiding Chrome's ~2 GB blob-fetch limit
  // that bites the cacheApi path on Gemma 4 E2B/E4B web variants.
  // MediaPipe `.task` models also work fine under streaming mode.
  await FlutterGemma.initialize(
    webStorageMode: WebStorageMode.streaming,
    inferenceEngines: const [LiteRtLmEngine()],
    embeddingBackends: const [LiteRtEmbeddingBackend()],
    // RAG is opt-in as of 1.0. The example demoes the sqlite store; pick the
    // platform impl (web uses wa-sqlite, native uses sqlite3).
    vectorStore: kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore(),
  );

  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Gemma Example',
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const SafeArea(child: HomeScreen()),
    );
  }
}
