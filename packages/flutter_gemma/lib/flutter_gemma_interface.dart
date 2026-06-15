import 'dart:async';

import 'package:flutter_gemma/core/lifecycle/close_notifier.dart';
import 'package:flutter_gemma/core/tool.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/services/vector_store_filter.dart';
import 'package:flutter_gemma/model_file_manager_interface.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Conditional default instance: the mobile/desktop default pulls dart:io;
// the web variant is a throwing stub (FlutterGemmaWeb registers itself at
// runtime). This keeps dart:io off the web/wasm import graph.
import 'flutter_gemma_default.dart'
    if (dart.library.js_interop) 'flutter_gemma_default_web.dart';

const supportedLoraRanks = [4, 8, 16];

/// Interface for the FlutterGemma plugin.
abstract class FlutterGemmaPlugin extends PlatformInterface {
  FlutterGemmaPlugin() : super(token: _token);

  static final Object _token = Object();
  static FlutterGemmaPlugin _instance = defaultFlutterGemmaInstance();

  static FlutterGemmaPlugin get instance => _instance;

  static set instance(FlutterGemmaPlugin instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  ModelFileManager get modelManager;

  InferenceModel? get initializedModel;

  EmbeddingModel? get initializedEmbeddingModel;

  /// Creates and returns a new [InferenceModel] instance.
  ///
  /// [modelType] — model type to create.
  /// [maxTokens] — maximum context length for the model.
  /// [preferredBackend] — backend preference (e.g., CPU, GPU).
  /// [loraRanks] — optional supported LoRA ranks.
  /// [maxNumImages] — maximum number of images (for multimodal models).
  /// [supportImage] — whether the model supports images.
  /// [supportAudio] — whether the model supports audio (Gemma 3n E4B only).
  /// [enableSpeculativeDecoding] — Multi-Token Prediction toggle for Gemma 4
  /// E2B/E4B (LiteRT-LM v0.11.0+). `null` honors the model's default;
  /// `true`/`false` forces on/off. Older `.litertlm` files without an MTP
  /// drafter ignore this flag at the SDK level.
  /// [maxConcurrentSessions] — optional cap on the number of sessions open
  /// at once via [InferenceModel.openSession]. `null` (default) = no cap,
  /// backward-compatible. When set, the (cap+1)-th [InferenceModel.openSession]
  /// throws [StateError]. Use this on mobile with large models to guard
  /// against OOM from multiple concurrent KV caches.
  Future<InferenceModel> createModel({
    required ModelType modelType,
    ModelFileType fileType = ModelFileType.task,
    int maxTokens = 1024,
    PreferredBackend? preferredBackend,
    List<int>? loraRanks,
    int? maxNumImages, // Add image support
    bool supportImage = false, // Add image support flag
    bool supportAudio = false, // Add audio support flag (Gemma 3n E4B)
    bool? enableSpeculativeDecoding,
    int? maxConcurrentSessions,
  });

  /// Creates and returns a new [EmbeddingModel] instance.
  ///
  /// Modern API: If paths are not provided, uses the active embedding model set via
  /// `FlutterGemma.installEmbedder()` or `modelManager.setActiveModel()`.
  ///
  /// Legacy API: Provide explicit paths for backward compatibility.
  ///
  /// [modelPath] — path to the embedding model file (optional if active model set).
  /// [tokenizerPath] — path to the tokenizer file (optional if active model set).
  /// [preferredBackend] — backend preference (e.g., CPU, GPU).
  Future<EmbeddingModel> createEmbeddingModel({
    String? modelPath,
    String? tokenizerPath,
    PreferredBackend? preferredBackend,
  });

  /// === RAG functionality ===

  /// Initialize vector store database.
  Future<void> initializeVectorStore(String databasePath);

  /// Add document to vector store with pre-computed embedding.
  Future<void> addDocumentWithEmbedding({
    required String id,
    required String content,
    required List<double> embedding,
    String? metadata,
  });

  /// Add document to vector store (will compute embedding automatically).
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  });

  /// Search for similar documents.
  ///
  /// [filter] is an optional payload predicate. Honored on every native
  /// platform (qdrant-edge backend). Silently ignored on Web (the wa-sqlite
  /// store has no payload filtering); passing a non-empty filter on Web
  /// returns the same hits as `filter: null` and never throws.
  Future<List<RetrievalResult>> searchSimilar({
    required String query,
    int topK = 5,
    double threshold = 0.0,
    Filter? filter,
  });

  /// Get vector store statistics.
  Future<VectorStoreStats> getVectorStoreStats();

  /// Clear all documents from vector store.
  Future<void> clearVectorStore();

  /// Whether HNSW indexing is enabled for vector store.
  ///
  /// When true, search uses O(log n) HNSW algorithm for large datasets.
  /// When false, always uses O(n) brute-force search.
  ///
  /// Can be toggled at runtime for performance testing.
  bool get enableHnsw;
  set enableHnsw(bool value);
}

/// Represents an LLM model instance.
abstract class InferenceModel {
  /// The single session created via [createSession]. Singleton lane —
  /// each [createSession] call overwrites this field with a new session
  /// and closes the previous one.
  ///
  /// For concurrent dialogues on a single loaded model use [openSession]
  /// instead — it returns detached sessions that don't touch this field.
  /// Read [sessions] to enumerate all live sessions (legacy + open).
  InferenceModelSession? get session;

  InferenceChat? chat;

  int get maxTokens;

  ModelFileType get fileType;

  /// Backend that the runtime initialized for this model, when known.
  ///
  /// This value is set after runtime creation and must reflect any fallback the
  /// plugin performed internally. FFI runtimes may fall back silently from a
  /// requested accelerator to another backend, so callers should check this
  /// value when the exact backend matters. It is null when the platform runtime
  /// does not expose a final backend.
  PreferredBackend? get activeBackend;

  /// Creates a new [InferenceModelSession] for generation.
  ///
  /// [temperature], [randomSeed], [topK], [topP] — parameters for sampling.
  /// [loraPath] — optional path to LoRA model.
  /// [enableVisionModality] — enable vision modality for multimodal models.
  /// [enableAudioModality] — enable audio modality for Gemma 3n E4B models.
  Future<InferenceModelSession> createSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality, // Add vision modality support
    bool? enableAudioModality, // Add audio modality support (Gemma 3n E4B)
    String? systemInstruction,
    bool enableThinking =
        false, // Enable thinking mode (Gemma 4 via extraContext)
    List<Tool> tools =
        const [], // Native tool calling (Gemma 4 → SDK tools_json)
  });

  /// Opens a new session detached from [session]. Each call returns a
  /// fresh independent session sharing the loaded model weights but with
  /// isolated context (history / KV cache). Use this for concurrent
  /// dialogues on a single loaded model.
  ///
  /// **Why:** the (expensive) model weights are loaded once and shared across
  /// every session; each session only adds its own lightweight context. This
  /// lets one loaded model back several independent conversations — e.g. a
  /// tabbed chat UI, two different system instructions / roles side by side,
  /// or background summarization alongside an active chat — without reloading
  /// the weights or clearing+rebuilding a single session's history on every
  /// switch. If you only ever have one conversation at a time, use
  /// [createSession] / [createChat] instead.
  ///
  /// Unlike [createSession], this does NOT modify the legacy [session]
  /// field. Concurrent sessions are tracked separately and surface via
  /// [sessions].
  ///
  /// **Concurrent contexts, serialized inference.** The sessions are
  /// logically independent — each keeps its own conversation — but
  /// generation is *serialized*: only one session runs inference at a time.
  /// Calling `getResponse()` / `getResponseAsync()` on a second session
  /// while another is still generating blocks until the first finishes; the
  /// calls do NOT run in parallel. This is intentional (parallel on-device
  /// inference would contend for the accelerator and risk OOM) and is the
  /// same on every backend:
  /// - `.litertlm` (FFI, all native): the engine allows one live
  ///   conversation at a time, so sessions multiplex — the active session's
  ///   history is replayed into the single conversation on switch.
  /// - `.litertlm` (web, `@litert-lm/core`): separate conversations, but
  ///   generation is still serialized.
  /// - `.task` (MediaPipe, Android/iOS): N real `LlmInferenceSession` live
  ///   at once (each with its own KV cache), generation serialized by a
  ///   mutex.
  ///
  /// **Memory caveat**: each concurrent session holds its own context
  /// (~100-500 MB depending on model + maxTokens). On mobile with large
  /// models (Gemma 4 E2B+), several concurrent sessions can OOM the process.
  /// Multi-session is most reliable on desktop and on high-end mobile with
  /// small models (Gemma 3 1B / 270M). For larger models on phones the safer
  /// pattern is still close+recreate with [InferenceChat]'s built-in history
  /// replay. Use [maxConcurrentSessions] on `createModel` to cap the count.
  ///
  /// Not yet available on the MediaPipe **web** `.task` path — throws
  /// [UnsupportedError] there.
  ///
  /// Throws [StateError] if `maxConcurrentSessions` (set on
  /// [FlutterGemmaPlugin.createModel]) is exceeded — close an existing
  /// session before opening a new one.
  Future<InferenceModelSession> openSession({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    String? loraPath,
    bool? enableVisionModality,
    bool? enableAudioModality,
    String? systemInstruction,
    bool enableThinking = false,
    List<Tool> tools = const [],
  }) async {
    throw UnsupportedError(
      'openSession() is not supported for $runtimeType. '
      'Concurrent sessions are available on `.litertlm` (FFI native + web) '
      'and `.task` (MediaPipe Android/iOS); the MediaPipe Web `.task` path '
      'does not support concurrent sessions.',
    );
  }

  /// Live sessions owned by this model — union of the legacy [session]
  /// (if any) and every active [openSession] result. Returns an
  /// unmodifiable view; mutate via [openSession], `session.close()`, or
  /// [close].
  List<InferenceModelSession> get sessions {
    final legacy = session;
    return List.unmodifiable([if (legacy != null) legacy]);
  }

  Future<InferenceChat> createChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false, // Add isThinking parameter
    ModelType? modelType, // Add modelType parameter
    ToolChoice toolChoice = ToolChoice.auto, // Tool calling mode
    int? maxFunctionBufferLength,
    String? systemInstruction,
  }) async {
    chat = InferenceChat(
      sessionCreator: () => createSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? false,
        enableAudioModality: supportAudio ?? false,
        systemInstruction: systemInstruction,
        enableThinking: isThinking,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false,
      supportAudio: supportAudio ?? false,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
      maxFunctionBufferLength:
          maxFunctionBufferLength ?? defaultMaxFunctionBufferLength,
      tools: tools,
      isThinking: isThinking,
      modelType: modelType ?? ModelType.gemmaIt,
      fileType: fileType,
      toolChoice: toolChoice,
      systemInstruction: systemInstruction,
    );
    await chat!.initSession();
    return chat!;
  }

  /// Same as [createChat], but uses [openSession] internally so the
  /// resulting chat owns an independent session that does not touch the
  /// legacy [session] field or other open chats. Use this when you need
  /// concurrent chats on a single loaded model.
  ///
  /// Each chat's own context-overflow rotation
  /// (`_recreateSessionWithReducedChunks`) creates a fresh sibling
  /// session via [openSession], so peer chats are unaffected.
  ///
  /// See [openSession] for the memory caveat. The returned chat is NOT
  /// stored in [chat] — that field tracks only the legacy [createChat]
  /// singleton. Hold the returned chat reference yourself and close it
  /// when done.
  Future<InferenceChat> openChat({
    double temperature = .8,
    int randomSeed = 1,
    int topK = 1,
    double? topP,
    int tokenBuffer = 256,
    String? loraPath,
    bool? supportImage,
    bool? supportAudio,
    List<Tool> tools = const [],
    bool? supportsFunctionCalls,
    bool isThinking = false,
    ModelType? modelType,
    ToolChoice toolChoice = ToolChoice.auto,
    int? maxFunctionBufferLength,
    String? systemInstruction,
  }) async {
    final independentChat = InferenceChat(
      sessionCreator: () => openSession(
        temperature: temperature,
        randomSeed: randomSeed,
        topK: topK,
        topP: topP,
        loraPath: loraPath,
        enableVisionModality: supportImage ?? false,
        enableAudioModality: supportAudio ?? false,
        systemInstruction: systemInstruction,
        enableThinking: isThinking,
        tools: tools,
      ),
      maxTokens: maxTokens,
      tokenBuffer: tokenBuffer,
      supportImage: supportImage ?? false,
      supportAudio: supportAudio ?? false,
      supportsFunctionCalls: supportsFunctionCalls ?? false,
      maxFunctionBufferLength:
          maxFunctionBufferLength ?? defaultMaxFunctionBufferLength,
      tools: tools,
      isThinking: isThinking,
      modelType: modelType ?? ModelType.gemmaIt,
      fileType: fileType,
      toolChoice: toolChoice,
      systemInstruction: systemInstruction,
    );
    await independentChat.initSession();
    return independentChat;
  }

  /// Register a callback fired once when this model is closed. The lifecycle
  /// OWNER (core) uses this to reset its singleton bookkeeping for models built
  /// by an engine package. Concrete models satisfy this via [CloseNotifier].
  void addCloseListener(void Function() listener);

  Future<void> close();
}

/// Session metrics containing token usage and performance statistics.
class SessionMetrics {
  SessionMetrics({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.timeToFirstTokenMs,
    this.tokensPerSecond,
    this.initTimeMs,
  });

  /// Number of input tokens (prompt tokens).
  final int inputTokens;

  /// Number of output tokens (generated tokens).
  final int outputTokens;

  /// Total tokens (input + output).
  final int totalTokens;

  /// Time to first token in milliseconds (if available).
  final double? timeToFirstTokenMs;

  /// Average tokens per second generation speed (if available).
  final double? tokensPerSecond;

  /// Session initialization time in milliseconds (if available).
  final double? initTimeMs;

  @override
  String toString() {
    return 'SessionMetrics(inputTokens: $inputTokens, outputTokens: $outputTokens, '
        'totalTokens: $totalTokens, ttft: ${timeToFirstTokenMs?.toStringAsFixed(2)}ms, '
        'tps: ${tokensPerSecond?.toStringAsFixed(2)})';
  }
}

/// Session managing response generation from the model.
abstract class InferenceModelSession {
  Future<String> getResponse();

  Stream<String> getResponseAsync();

  Future<int> sizeInTokens(String text);

  Future<void> addQueryChunk(Message message);

  Future<void> stopGeneration();

  /// Get session metrics including token usage and performance stats.
  ///
  /// **FFI (LiteRT-LM)**: Returns accurate token counts from benchmark info.
  /// **MediaPipe (Mobile)**: Returns estimated counts (uses internal metrics if available).
  ///
  /// Call this after [getResponse] or [getResponseAsync] completes for accurate results.
  SessionMetrics getSessionMetrics();

  Future<void> close();
}

/// Mixin for sessions that surface the SDK's structured raw JSON response
/// (LiteRT-LM Gemma 4 path with `tool_calls`). Allows [InferenceChat] to read
/// the structured tool calls without a hard dependency on a concrete session
/// type, and lets non-FFI sessions opt out by simply not implementing this
/// mixin.
mixin RawSdkResponseSession on InferenceModelSession {
  /// Most recent raw SDK JSON. Null until first generation completes.
  String? get lastRawResponse;
}

/// Task type for embedding generation, following Google RAG SDK convention.
///
/// EmbeddingGemma models are trained with different prefixes for queries
/// and documents to improve retrieval quality.
enum TaskType {
  /// For search queries. Prepends query prefix before embedding.
  retrievalQuery,

  /// For document indexing. Prepends document prefix before embedding.
  retrievalDocument;

  /// Canonical prefix prepended to user text before tokenization. Single
  /// source of truth across all native platforms — fixes cross-platform
  /// drift on `retrievalQuery` (issue #264) by construction. The prefix
  /// strings are stable, so corpora indexed with earlier releases remain
  /// valid.
  String get prefix => switch (this) {
    TaskType.retrievalQuery => 'task: search result | query: ',
    TaskType.retrievalDocument => 'title: none | text: ',
  };
}

/// Represents an embedding model instance.
abstract class EmbeddingModel {
  /// Generate embedding vector for given text.
  ///
  /// [taskType] controls the prefix applied before embedding:
  /// - [TaskType.retrievalQuery] (default) — for search queries
  /// - [TaskType.retrievalDocument] — for document indexing
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  });

  /// Generate embedding vectors for multiple texts.
  ///
  /// [taskType] controls the prefix applied before embedding.
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  });

  /// Get the dimension of embedding vectors generated by this model.
  Future<int> getDimension();

  /// See [InferenceModel.addCloseListener].
  void addCloseListener(void Function() listener);

  /// Close the embedding model and release resources.
  Future<void> close();
}
