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
    val service = PlatformServiceImpl(flutterPluginBinding.applicationContext);
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma_stream")
    eventChannel.setStreamHandler(service)
    PlatformService.setUp(flutterPluginBinding.binaryMessenger, service)
  }


  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    eventChannel.setStreamHandler(null)
  }
}

private class PlatformServiceImpl(
  var context : Context
): PlatformService, EventChannel.StreamHandler {
  private val scope = CoroutineScope(Dispatchers.Main)
  private var eventSink: EventChannel.EventSink? = null
  private var inferenceModel : InferenceModel? = null
  private var session: InferenceModelSession? = null

  override fun createModel(
    maxTokens: Long,
    modelPath: String,
    loraRanks: List<Long>?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch(Dispatchers.IO) {
      try {
        val config = InferenceModelConfig(
          modelPath,
          maxTokens.toInt(),
          loraRanks?.map { it.toInt() },
        )
        // Recreate model only if it's needed. Useful for hot restart
        if (config != inferenceModel?.config) {
          inferenceModel?.close()
          inferenceModel = InferenceModel(
            context,
            config,
          )
        } else {
          println("Inference model with given parameters is already created")
        }
        withContext(Dispatchers.Main) {
          callback(Result.success(Unit))
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          callback(Result.failure(e))
        }
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
    loraPath: String?,
    topK: Long,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch(Dispatchers.IO) {
      try {
        if (inferenceModel == null) throw Exception("Inference model is not created")
        val config = InferenceSessionConfig(
          temperature.toFloat(),
          randomSeed.toInt(),
          topK.toInt(),
          loraPath,
        )
        // Always recreate session to 
        session?.close()
        session = InferenceModelSession(inferenceModel!!.llmInference, config)
        withContext(Dispatchers.Main) {
          callback(Result.success(Unit))
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          callback(Result.failure(e))
        }
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

  override fun generateResponse(prompt: String, callback: (Result<String>) -> Unit) {
    scope.launch(Dispatchers.IO) {
      try {
        if (session == null) throw Exception("Inference model session is not created")
        val result = session!!.generateResponse(prompt)
        withContext(Dispatchers.Main) {
          callback(Result.success(result))
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          callback(Result.failure(e))
        }
      }
    }
  }

  override fun generateResponseAsync(prompt: String, callback: (Result<Unit>) -> Unit) {
    scope.launch(Dispatchers.IO) {
      try {
        if (session == null) throw Exception("Inference model session is not created")
        session!!.generateResponseAsync(prompt)
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          callback(Result.failure(e))
        }
      }
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    scope.launch {
      launch {
        inferenceModel?.partialResults?.collect { pair ->
          if (pair.second) {
            events?.success(pair.first)
            events?.endOfStream()
          } else {
            events?.success(pair.first)
          }
        }
      }

      launch {
        inferenceModel?.errors?.collect { error ->
          events?.error("ERROR", error.message, null)
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}
