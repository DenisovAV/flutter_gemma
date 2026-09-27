package dev.flutterberlin.flutter_gemma_builtin_ai

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log

import io.flutter.plugin.common.EventChannel

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Backs the pigeon [BuiltInAiService] with the ML Kit GenAI Prompt API
 * (Gemini Nano via AICore) and drives the shared
 * "flutter_gemma_builtin_ai_stream" [EventChannel].
 *
 * Native → Dart stream contract (the Dart demux depends on all three):
 *  1. EVERY data event is tagged with `sessionId`.
 *  2. Completion is a TAGGED DATA event `{partialResult:"", done:true, sessionId}`
 *     — never [EventChannel.EventSink.endOfStream] (the channel is shared).
 *  3. [checkAvailability] reflects post-download readiness (Dart's ensureReady
 *     polls it; the event channel is progress-only).
 *
 * The Prompt API is single-turn (no server-side history), so each [SessionState]
 * keeps a [StringBuilder] transcript that is replayed as the [TextPart] on every
 * generate; the model turn is appended back so the next turn sees it. At most one
 * image per turn (ML Kit constraint).
 */
internal class BuiltInAiServiceImpl(
  private val context: Context
) : BuiltInAiService, EventChannel.StreamHandler {

  companion object {
    private const val TAG = "FlutterGemmaBuiltInAi"
  }

  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private var eventSink: EventChannel.EventSink? = null

  // The generative model client. `Generation.getClient()` is cheap/idempotent;
  // we keep a single instance for status checks, download and generation.
  @Volatile private var generativeModel: GenerativeModel? = null
  private val modelLock = Any()

  private fun client(): GenerativeModel = synchronized(modelLock) {
    generativeModel ?: Generation.getClient().also { generativeModel = it }
  }

  /** Per-session, single-turn transcript + pending image + sampling params. */
  private class SessionState(
    val temperature: Float,
    val topK: Int,
    val maxOutputTokens: Int?,
    systemInstruction: String?,
  ) {
    val transcript = StringBuilder()
    val images = mutableListOf<Bitmap>()
    @Volatile var job: Job? = null

    init {
      if (!systemInstruction.isNullOrEmpty()) {
        transcript.append(systemInstruction).append("\n\n")
      }
    }
  }

  private val sessions = mutableMapOf<Long, SessionState>()
  private val sessionsLock = Any()

  private fun requireSession(sessionId: Long): SessionState =
    synchronized(sessionsLock) {
      sessions[sessionId]
        ?: throw IllegalStateException("Session $sessionId not found")
    }

  fun cleanup() {
    scope.cancel()
    synchronized(sessionsLock) {
      sessions.values.forEach { it.job?.cancel() }
      sessions.clear()
    }
    synchronized(modelLock) {
      runCatching { generativeModel?.close() }
      generativeModel = null
    }
  }

  // === EventChannel.StreamHandler ===

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  /** Post a payload to the shared sink on the Main thread (EventSink is not
   *  thread-safe). Never closes the channel — it is shared across sessions. */
  private fun postEvent(payload: Map<String, Any?>) {
    scope.launch(Dispatchers.Main) { eventSink?.success(payload) }
  }

  // === BuiltInAiService ===

  override fun checkAvailability(callback: (Result<AvailabilityStatus>) -> Unit) {
    scope.launch {
      try {
        // Reflects post-download readiness: after a successful download the
        // status flips to AVAILABLE, which Dart's ensureReady polls for.
        val status = when (client().checkStatus()) {
          FeatureStatus.AVAILABLE -> AvailabilityStatus.AVAILABLE
          FeatureStatus.DOWNLOADABLE -> AvailabilityStatus.DOWNLOADABLE
          FeatureStatus.DOWNLOADING -> AvailabilityStatus.DOWNLOADING
          FeatureStatus.UNAVAILABLE -> AvailabilityStatus.UNAVAILABLE_DEVICE_UNSUPPORTED
          else -> AvailabilityStatus.UNAVAILABLE_OTHER
        }
        callback(Result.success(status))
      } catch (e: GenAiException) {
        Log.w(TAG, "checkStatus failed: ${e.message}")
        callback(Result.success(AvailabilityStatus.UNAVAILABLE_OTHER))
      } catch (e: Exception) {
        Log.w(TAG, "checkStatus failed: ${e.message}")
        callback(Result.success(AvailabilityStatus.UNAVAILABLE_OTHER))
      }
    }
  }

  override fun downloadFeature(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      // The pigeon reply must fire exactly once. Guard so a terminal status,
      // the post-collect fallback, and the catch are mutually exclusive: some
      // download flows end WITHOUT a terminal DownloadCompleted/Failed (e.g.
      // the feature is already present and the flow just finishes) — without
      // the fallback the Dart future would hang until ensureReady's timeout.
      val replied = AtomicBoolean(false)
      fun reply(result: Result<Unit>) {
        if (replied.compareAndSet(false, true)) callback(result)
      }
      try {
        client().download().collect { status ->
          when (status) {
            is DownloadStatus.DownloadStarted -> {
              Log.d(TAG, "Gemini Nano download started")
            }
            is DownloadStatus.DownloadProgress -> {
              // ML Kit exposes a running byte counter but no reliable total,
              // so bytesTotal is 0; Dart falls back to polling availability for
              // the terminal signal and only shows a percent when total > 0.
              postEvent(
                mapOf(
                  "code" to "DOWNLOAD_PROGRESS",
                  "bytesDownloaded" to status.totalBytesDownloaded,
                  "bytesTotal" to 0L,
                )
              )
            }
            is DownloadStatus.DownloadCompleted -> {
              Log.d(TAG, "Gemini Nano download complete")
              reply(Result.success(Unit))
            }
            is DownloadStatus.DownloadFailed -> {
              Log.e(TAG, "Gemini Nano download failed: ${status.e.message}")
              reply(Result.failure(status.e))
            }
          }
        }
        // Flow ended without a terminal status — treat as success; Dart's
        // ensureReady poll confirms readiness via checkAvailability.
        reply(Result.success(Unit))
      } catch (e: Exception) {
        reply(Result.failure(e))
      }
    }
  }

  override fun createModel(supportImage: Boolean, callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        // The OS owns the weights; getClient() just wires up the AICore-backed
        // client. supportImage is advisory — multimodality is per-request.
        client()
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeModel(callback: (Result<Unit>) -> Unit) {
    scope.launch {
      try {
        synchronized(sessionsLock) {
          sessions.values.forEach { it.job?.cancel() }
          sessions.clear()
        }
        synchronized(modelLock) {
          runCatching { generativeModel?.close() }
          generativeModel = null
        }
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun createSession(
    sessionId: Long,
    temperature: Double,
    topK: Long,
    topP: Double?,
    maxOutputTokens: Long?,
    systemInstruction: String?,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        // topP has no documented Prompt-API builder param; it is accepted for
        // contract parity but not applied to the request.
        val state = SessionState(
          temperature = temperature.toFloat(),
          topK = topK.toInt(),
          maxOutputTokens = maxOutputTokens?.toInt(),
          systemInstruction = systemInstruction,
        )
        synchronized(sessionsLock) {
          sessions[sessionId]?.job?.cancel()
          sessions[sessionId] = state
        }
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun closeSession(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    try {
      val removed = synchronized(sessionsLock) {
        sessions.remove(sessionId)
      }
      removed?.job?.cancel()
      // If a generation stream was still active, emit a tagged completion so a
      // consumer awaiting getResponseAsync() closes cleanly instead of hanging —
      // closing a session mid-stream must terminate that stream, same as
      // stopGeneration does (the job cancel alone is silent to Dart).
      if (removed != null) {
        postEvent(
          mapOf(
            "partialResult" to "",
            "done" to true,
            "sessionId" to sessionId,
          )
        )
      }
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun addQueryChunk(sessionId: Long, text: String, callback: (Result<Unit>) -> Unit) {
    try {
      requireSession(sessionId).transcript.append(text)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun addImage(sessionId: Long, imageBytes: ByteArray, callback: (Result<Unit>) -> Unit) {
    try {
      val state = requireSession(sessionId)
      if (state.images.isNotEmpty()) {
        throw IllegalStateException("one image per message")
      }
      val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        ?: throw IllegalArgumentException("Could not decode image bytes")
      state.images.add(bitmap)
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  /** Build a request replaying the transcript, with an optional single image. */
  private fun buildRequest(state: SessionState) =
    if (state.images.isNotEmpty()) {
      generateContentRequest(ImagePart(state.images.first()), TextPart(state.transcript.toString())) {
        temperature = state.temperature
        topK = state.topK
        state.maxOutputTokens?.let { maxOutputTokens = it }
      }
    } else {
      generateContentRequest(TextPart(state.transcript.toString())) {
        temperature = state.temperature
        topK = state.topK
        state.maxOutputTokens?.let { maxOutputTokens = it }
      }
    }

  override fun generateResponse(sessionId: Long, callback: (Result<String>) -> Unit) {
    scope.launch {
      try {
        val state = requireSession(sessionId)
        val response = client().generateContent(buildRequest(state))
        val text = response.candidates.firstOrNull()?.text.orEmpty()
        // Append the model turn (single-turn API keeps no history of its own),
        // then clear the pending image so the next turn starts clean.
        state.transcript.append(text)
        state.images.clear()
        callback(Result.success(text))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateResponseAsync(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    val state = try {
      requireSession(sessionId)
    } catch (e: Exception) {
      callback(Result.failure(e))
      return
    }

    val job = scope.launch {
      val builder = StringBuilder()
      try {
        client().generateContentStream(buildRequest(state)).collect { chunk ->
          val piece = chunk.candidates.firstOrNull()?.text.orEmpty()
          if (piece.isNotEmpty()) {
            builder.append(piece)
            // (1) tagged token event.
            postEvent(
              mapOf(
                "partialResult" to piece,
                "done" to false,
                "sessionId" to sessionId,
              )
            )
          }
        }
        // Persist the model turn, clear the pending image.
        state.transcript.append(builder.toString())
        state.images.clear()
        // (2) completion as a TAGGED DATA event — NOT endOfStream.
        postEvent(
          mapOf(
            "partialResult" to "",
            "done" to true,
            "sessionId" to sessionId,
          )
        )
      } catch (e: CancellationException) {
        // Cooperative cancellation from stopGeneration — not an error. Let it
        // propagate; stopGeneration's own {done:true} post is the single
        // completion signal on the stop path.
        throw e
      } catch (e: Exception) {
        // Surface as a TAGGED DATA error (not an EventChannel error, which
        // would hit every session and drop the sessionId).
        postEvent(
          mapOf(
            "code" to "ERROR",
            "message" to (e.message ?: "generation failed"),
            "sessionId" to sessionId,
          )
        )
      }
    }
    state.job = job
    callback(Result.success(Unit))
  }

  override fun stopGeneration(sessionId: Long, callback: (Result<Unit>) -> Unit) {
    try {
      requireSession(sessionId).job?.cancel()
      // Emit a tagged completion so the Dart stream closes cleanly on cancel.
      postEvent(
        mapOf(
          "partialResult" to "",
          "done" to true,
          "sessionId" to sessionId,
        )
      )
      callback(Result.success(Unit))
    } catch (e: Exception) {
      callback(Result.failure(e))
    }
  }

  override fun countTokens(text: String, callback: (Result<Long>) -> Unit) {
    scope.launch {
      try {
        val response = client().countTokens(generateContentRequest(TextPart(text)) {})
        callback(Result.success(response.totalTokens.toLong()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }
}
