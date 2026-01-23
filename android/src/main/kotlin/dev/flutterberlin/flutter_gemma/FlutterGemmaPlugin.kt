package dev.flutterberlin.flutter_gemma

import android.content.Context
import java.io.File
import java.io.FileOutputStream

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

import dev.flutterberlin.flutter_gemma.engines.*

/** FlutterGemmaPlugin */
class FlutterGemmaPlugin: FlutterPlugin {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var eventChannel: EventChannel
  private lateinit var bundledChannel: MethodChannel
  private lateinit var context: Context
  private var service: PlatformServiceImpl? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    service = PlatformServiceImpl(context)
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma_stream")
    eventChannel.setStreamHandler(service!!)
    PlatformService.setUp(flutterPluginBinding.binaryMessenger, service!!)

    // Setup bundled assets channel
    bundledChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma_bundled")
    bundledChannel.setMethodCallHandler { call, result ->
      when (call.method) {
        "copyAssetToFile" -> {
          try {
            val assetPath = call.argument<String>("assetPath")!!
            val destPath = call.argument<String>("destPath")!!
            copyAssetToFile(assetPath, destPath)
            result.success("success")
          } catch (e: Exception) {
            result.error("COPY_ERROR", e.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun copyAssetToFile(assetPath: String, destPath: String) {
    val inputStream = context.assets.open(assetPath)
    val outputFile = File(destPath)
    outputFile.parentFile?.mkdirs()
    val outputStream = FileOutputStream(outputFile)

    inputStream.use { input ->
      outputStream.use { output ->
        input.copyTo(output, bufferSize = 8192)
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    eventChannel.setStreamHandler(null)
    bundledChannel.setMethodCallHandler(null)
    service?.cleanup()
    service = null
  }
}

private class PlatformServiceImpl(
  val context: Context
) : PlatformService, EventChannel.StreamHandler {
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private var eventSink: EventChannel.EventSink? = null
  private var streamJob: kotlinx.coroutines.Job? = null  // Track stream collection job
  private val engineLock = Any()  // Lock for thread-safe engine access

  // NEW: Use InferenceEngine abstraction instead of InferenceModel
  private var engine: InferenceEngine? = null
  private var session: InferenceSession? = null

  // RAG components
  private var embeddingModel: EmbeddingModel? = null
  private var vectorStore: VectorStore? = null

  fun cleanup() {
    scope.cancel()
    streamJob?.cancel()
    streamJob = null
    synchronized(engineLock) {
      session?.close()
      session = null
      engine?.close()
      engine = null
    }
    embeddingModel?.close()
    embeddingModel = null
    vectorStore?.close()
    vectorStore = null
  }

  override fun createModel(
    maxTokens: Long,
    modelPath: String,
    loraRanks: List<Long>?,
    preferredBackend: PreferredBackend?,
    maxNumImages: Long?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        // Build configuration first (before touching state)
        val backendEnum = preferredBackend?.let {
          PreferredBackendEnum.values()[it.ordinal]
        }
        val config = EngineConfig(
          modelPath = modelPath,
          maxTokens = maxTokens.toInt(),
          supportedLoraRanks = loraRanks?.map { it.toInt() },
          preferredBackend = backendEnum,
          maxNumImages = maxNumImages?.toInt()
        )

        // Create and initialize new engine BEFORE clearing old state
        // This ensures we don't leave state inconsistent on failure
        val newEngine = EngineFactory.createFromModelPath(modelPath, context)
        newEngine.initialize(config)

        // Only now clear old state and swap in new engine (thread-safe)
        synchronized(engineLock) {
          session?.close()
          session = null
          engine?.close()
          engine = newEngine
        }

        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeModel(callback: (Result<Unit>) -> Unit) {
    synchronized(engineLock) {
      try {
        session?.close()
        session = null
        engine?.close()
        engine = null
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun createSession(
    temperature: Double,
    randomSeed: Long,
    topK: Long,
    topP: Double?,
    loraPath: String?,
    enableVisionModality: Boolean?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        synchronized(engineLock) {
          val currentEngine = engine
            ?: throw IllegalStateException("Inference model is not created")

          val config = SessionConfig(
            temperature = temperature.toFloat(),
            randomSeed = randomSeed.toInt(),
            topK = topK.toInt(),
            topP = topP?.toFloat(),
            loraPath = loraPath,
            enableVisionModality = enableVisionModality
          )

          session?.close()
          session = currentEngine.createSession(config)
        }
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeSession(callback: (Result<Unit>) -> Unit) {
    synchronized(engineLock) {
      try {
        session?.close()
        session = null
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun sizeInTokens(prompt: String, callback: (Result<Long>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        val size = currentSession.sizeInTokens(prompt)
        callback(Result.success(size.toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun addQueryChunk(prompt: String, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        currentSession.addQueryChunk(prompt)
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun addImage(imageBytes: ByteArray, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        currentSession.addImage(imageBytes)
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponse(callback: (Result<String>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        val result = currentSession.generateResponse()
        callback(Result.success(result))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponseAsync(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        currentSession.generateResponseAsync()
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun stopGeneration(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        val currentSession = session
          ?: throw IllegalStateException("Session not created")
        currentSession.cancelGeneration()
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    // Cancel previous stream collection to prevent orphaned coroutines
    streamJob?.cancel()
    eventSink = events

    synchronized(engineLock) {
      val currentEngine = engine ?: return

      streamJob = scope.launch {
        launch {
          currentEngine.partialResults.collect { (text, done) ->
            val payload = mapOf("partialResult" to text, "done" to done)
            withContext(Dispatchers.Main) {
              events?.success(payload)
              if (done) {
                events?.endOfStream()
              }
            }
          }
        }

        launch {
          currentEngine.errors.collect { error ->
            withContext(Dispatchers.Main) {
              events?.error("ERROR", error.message, null)
            }
          }
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    streamJob?.cancel()
    streamJob = null
    eventSink = null
  }

  // === RAG Methods Implementation ===

  override fun createEmbeddingModel(
    modelPath: String,
    tokenizerPath: String,
    preferredBackend: PreferredBackend?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        embeddingModel?.close()

        // Convert PreferredBackend to useGPU boolean
        val useGPU = when (preferredBackend) {
          PreferredBackend.GPU, PreferredBackend.GPU_FLOAT16,
          PreferredBackend.GPU_MIXED, PreferredBackend.GPU_FULL -> true
          else -> false
        }

        embeddingModel = EmbeddingModel(context, modelPath, tokenizerPath, useGPU)
        embeddingModel!!.initialize()
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeEmbeddingModel(callback: (Result<Unit>) -> Unit) {
    try {
      embeddingModel?.close()
      embeddingModel = null
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun generateEmbeddingFromModel(text: String, callback: (Result<List<Double>>) -> Unit) {
    scope.launch {
      try {
        val embedding = embeddingModel?.embed(text)
          ?: throw IllegalStateException("Embedding model not initialized. Call createEmbeddingModel first.")
        callback(Result.success(embedding))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateEmbeddingsFromModel(texts: List<String>, callback: (Result<List<Any?>>) -> Unit) {
    scope.launch {
      try {
        if (embeddingModel == null) {
          throw IllegalStateException("Embedding model not initialized. Call createEmbeddingModel first.")
        }

        val embeddings = mutableListOf<List<Double>>()
        for (text in texts) {
          val embedding = embeddingModel!!.embed(text)
          embeddings.add(embedding)
        }
        // Convert to List<Any?> for pigeon compatibility (deep cast on Dart side)
        callback(Result.success(embeddings as List<Any?>))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun getEmbeddingDimension(callback: (Result<Long>) -> Unit) {
    scope.launch {
      try {
        if (embeddingModel == null) {
          throw IllegalStateException("Embedding model not initialized. Call createEmbeddingModel first.")
        }

        // Generate a small test embedding to get dimension
        val testEmbedding = embeddingModel!!.embed("test")
        val dimension = testEmbedding.size.toLong()
        callback(Result.success(dimension))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun initializeVectorStore(databasePath: String, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        vectorStore = null
        vectorStore = VectorStore(context)
        vectorStore!!.initialize(databasePath)
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun addDocument(
    id: String,
    content: String,
    embedding: List<Double>,
    metadata: String?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        vectorStore?.addDocument(id, content, embedding, metadata)
          ?: throw IllegalStateException("Vector store not initialized")
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun searchSimilar(
    queryEmbedding: List<Double>,
    topK: Long,
    threshold: Double,
    callback: (Result<List<RetrievalResult>>) -> Unit
  ) {
    scope.launch {
      try {
        val results = vectorStore?.searchSimilar(queryEmbedding, topK.toInt(), threshold)
          ?: throw IllegalStateException("Vector store not initialized")
        callback(Result.success(results))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun getVectorStoreStats(callback: (Result<VectorStoreStats>) -> Unit) {
    scope.launch {
      try {
        val stats = vectorStore?.getStats()
          ?: throw IllegalStateException("Vector store not initialized")
        callback(Result.success(stats))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun clearVectorStore(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        vectorStore?.clear()
          ?: throw IllegalStateException("Vector store not initialized")
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeVectorStore(callback: (Result<Unit>) -> Unit) {
    try {
      vectorStore?.close()
      vectorStore = null
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }
}