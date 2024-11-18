package dev.flutterberlin.flutter_gemma

import android.content.Context

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import android.util.Log

/** FlutterGemmaPlugin */
class FlutterGemmaPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private var eventSink: EventChannel.EventSink? = null
  private lateinit var inferenceModel : InferenceModel
  private lateinit var context : Context
  private val scope = CoroutineScope(Dispatchers.Main)

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma")
    channel.setMethodCallHandler(this)
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_gemma_stream")
    eventChannel.setStreamHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "init") {
      try {
        val modelPath = call.argument<String>("modelPath")!!
        val maxTokens = call.argument<Int>("maxTokens")!!
        val temperature = call.argument<Float>("temperature")!!
        val randomSeed = call.argument<Int>("maxTokens")!!
        val topK = call.argument<Int>("topK")!!
        val loraPath = call.argument<String?>("loraPath")
        val numOfSupportedLoraRanks = call.argument<Int?>("numOfSupportedLoraRanks")
        val supportedLoraRanks = call.argument<List<Int>?>("supportedLoraRanks")

        inferenceModel = InferenceModel.getInstance(context, modelPath, maxTokens, temperature,
          randomSeed, topK, loraPath, numOfSupportedLoraRanks, supportedLoraRanks)
        result.success(true)
      } catch (e: Exception) {
        result.error("ERROR", "Failed to initialize gemma", e.localizedMessage)
      }
    } else if (call.method == "getGemmaResponse") {
      try {
        val prompt = call.argument<String>("prompt")!!
        val answer = inferenceModel.generateResponse(prompt)
        result.success(answer)
      } catch (e: Exception) {
        result.error("ERROR", "Failed to get gemma response", e.localizedMessage)
      }
    } else if (call.method == "getGemmaResponseAsync") {
      try {
        val prompt = call.argument<String>("prompt")!!
        inferenceModel.generateResponseAsync(prompt)
        result.success(null)
      } catch (e: Exception) {
        result.error("ERROR", e.localizedMessage, null)
      }
    } else {
      result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    scope.launch {

      launch {
        inferenceModel.partialResults.collect { pair ->
          if (pair.second) {
            events?.success(pair.first)
            events?.success(null)
          } else {
            events?.success(pair.first)
          }
        }
      }

      launch {
        inferenceModel.errors.collect { error ->
          events?.error("ERROR", error.message, null)
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }
}
