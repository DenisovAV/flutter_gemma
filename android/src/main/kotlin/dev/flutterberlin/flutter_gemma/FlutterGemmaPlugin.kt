package dev.flutterberlin.flutter_gemma

import android.content.Context

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*

/** FlutterGemmaPlugin */
class FlutterGemmaPlugin: FlutterPlugin {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var eventChannel: EventChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val service = PlatformServiceImpl(flutterPluginBinding.applicationContext)
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma_stream")
    eventChannel.setStreamHandler(service)
    PlatformService.setUp(flutterPluginBinding.binaryMessenger, service)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    eventChannel.setStreamHandler(null)
  }
}

private class PlatformServiceImpl(
  val context: Context
) : PlatformService, EventChannel.StreamHandler {
  private val scope = CoroutineScope(Dispatchers.IO)
  private var eventSink: EventChannel.EventSink? = null
  private var inferenceModel: InferenceModel? = null
  private var session: InferenceModelSession? = null

  override fun createModel(
    maxTokens: Long,
    modelPath: String,
    loraRanks: List<Long>?,
    preferredBackend: PreferredBackend?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        val backendEnum = preferredBackend?.let {
          PreferredBackendEnum.values()[it.ordinal]
        }
        val config = InferenceModelConfig(
          modelPath,
          maxTokens.toInt(),
          loraRanks?.map { it.toInt() },
          backendEnum
        )
        if (config != inferenceModel?.config) {
          inferenceModel?.close()
          inferenceModel = InferenceModel(context, config)
        }
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeModel(callback: (Result<Unit>) -> Unit) {
    try {
      inferenceModel?.close()
      inferenceModel = null
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun createSession(
    temperature: Double,
    randomSeed: Long,
    topK: Long,
    topP: Double?,
    loraPath: String?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        val model = inferenceModel ?: throw IllegalStateException("Inference model is not created")
        val config = InferenceSessionConfig(
          temperature.toFloat(),
          randomSeed.toInt(),
          topK.toInt(),
          topP?.toFloat(),
          loraPath
        )
        session?.close()
        session = model.createSession(config)
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeSession(callback: (Result<Unit>) -> Unit) {
    try {
      session?.close()
      session = null
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun sizeInTokens(prompt: String, callback: (Result<Long>) -> Unit) {
    scope.launch {
      try {
        val size = session?.sizeInTokens(prompt) ?: throw IllegalStateException("Session not created")
        callback(Result.success(size.toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun addQueryChunk(prompt: String, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        session?.addQueryChunk(prompt) ?: throw IllegalStateException("Session not created")
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponse(callback: (Result<String>) -> Unit) {
    scope.launch {
      try {
        val result = session?.generateResponse() ?: throw IllegalStateException("Session not created")
        callback(Result.success(result))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponseAsync(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        session?.generateResponseAsync() ?: throw IllegalStateException("Session not created")
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun cancelGenerateResponseAsync(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        session?.cancelGenerateResponseAsync() ?: throw IllegalStateException("Session not created")
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }


  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    val model = inferenceModel ?: return

    scope.launch {
      launch {
        model.partialResults.collect { (text, done) ->
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
        model.errors.collect { error ->
          withContext(Dispatchers.Main) {
            events?.error("ERROR", error.message, null)
          }
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}