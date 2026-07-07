package dev.flutterberlin.flutter_gemma_builtin_ai

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/** FlutterGemmaBuiltInAiPlugin — hosts the built-in OS AI (Gemini Nano via ML
 *  Kit GenAI Prompt) BuiltInAiService HostApi + the
 *  "flutter_gemma_builtin_ai_stream" async-result EventChannel. */
class FlutterGemmaBuiltInAiPlugin : FlutterPlugin {
  private var service: BuiltInAiServiceImpl? = null
  private lateinit var eventChannel: EventChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val svc = BuiltInAiServiceImpl(binding.applicationContext)
    service = svc
    eventChannel = EventChannel(binding.binaryMessenger, "flutter_gemma_builtin_ai_stream")
    eventChannel.setStreamHandler(svc)
    BuiltInAiService.setUp(binding.binaryMessenger, svc)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    BuiltInAiService.setUp(binding.binaryMessenger, null)
    eventChannel.setStreamHandler(null)
    service?.cleanup()
    service = null
  }
}
