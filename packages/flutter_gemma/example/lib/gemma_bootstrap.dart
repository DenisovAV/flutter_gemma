import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_rag_sqlite/flutter_gemma_rag_sqlite.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

/// The opt-in inference engines the example registers. Single source of truth —
/// used by [bootstrapGemma] and by the diagnostics screen so the two never
/// drift. The example ships both formats (`.litertlm` + `.task`). The element
/// type (`InferenceEngineProvider`) is inferred from the concrete engines, so
/// the example needn't import the internal provider interface.
const kExampleInferenceEngines = [
  LiteRtLmEngine(),
  MediaPipeEngine(),
  BuiltInAiEngine(),
];

/// The opt-in embedding backends the example registers. Single source of truth.
const kExampleEmbeddingBackends = [LiteRtEmbeddingBackend()];

/// The opt-in STT backends the example registers. Single source of truth.
const kExampleSttBackends = [LiteRtSttBackend()];

/// The agentic skill executors the example registers (text / JS / native
/// intent). Registered through `FlutterGemma.initialize(skillExecutors: …)` —
/// the recommended global path — so any [AgentSession.fromModel] built without
/// an explicit `executors:` list picks them up from the core registry. The JS
/// executor resolves each bundled skill's HTML via [AssetSkillSource]; MCP is
/// omitted (no server configured in the demo). The demo screen shows the
/// alternative explicit-list path in a comment.
final kExampleSkillExecutors = <SkillExecutor>[
  TextSkillExecutor(),
  JsSkillExecutor(sourceFor: AssetSkillSource().jsSkillSourceFor),
  NativeIntentExecutor(),
];

/// The RAG vector-store backends the example can switch between.
enum RagBackend {
  sqlite('SQLite'),
  qdrant('Qdrant');

  const RagBackend(this.label);
  final String label;

  /// Qdrant is native-only (no web build). Sqlite runs everywhere.
  bool get isSupportedOnThisPlatform => this == RagBackend.sqlite || !kIsWeb;

  /// Storage path passed to `initializeVectorStore`. Sqlite expects a `.db`
  /// FILE; qdrant-edge treats the path as a shard DIRECTORY (it creates a
  /// subdir there and `clear()` recursively deletes it), so each backend gets
  /// its own path shape — they never collide on disk.
  String get storageName => switch (this) {
    RagBackend.sqlite => 'rag_demo.db',
    RagBackend.qdrant => 'rag_demo_qdrant',
  };
}

/// Builds the VectorStoreRepository for [backend] on the current platform.
VectorStoreRepository vectorStoreFor(RagBackend backend) {
  switch (backend) {
    case RagBackend.sqlite:
      return kIsWeb ? WebSqliteVectorStore() : SqliteVectorStore();
    case RagBackend.qdrant:
      // Native-only; callers must guard with isSupportedOnThisPlatform on web.
      return QdrantVectorStore();
  }
}

/// Single source of truth for FlutterGemma.initialize. Called at app startup
/// (main.dart) AND when the RAG demo switches the vector store backend
/// (after FlutterGemma.reset()). Keeps the engine/backend lists DRY.
///
/// `WebStorageMode.streaming` (OPFS-backed) is required for `.litertlm`
/// web models in 0.16.2+ — the @litert-lm/core engine consumes a
/// ReadableStream from OPFS, avoiding Chrome's ~2 GB blob-fetch limit
/// that bites the cacheApi path on Gemma 4 E2B/E4B web variants.
/// MediaPipe `.task` models also work fine under streaming mode.
Future<void> bootstrapGemma({required RagBackend ragBackend}) {
  return FlutterGemma.initialize(
    webStorageMode: WebStorageMode.streaming,
    inferenceEngines: kExampleInferenceEngines,
    embeddingBackends: kExampleEmbeddingBackends,
    sttBackends: kExampleSttBackends,
    skillExecutors: kExampleSkillExecutors,
    vectorStore: vectorStoreFor(ragBackend),
  );
}
