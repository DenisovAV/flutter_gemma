package dev.flutterberlin.flutter_gemma.engines.litertlm

import android.util.Log
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import dev.flutterberlin.flutter_gemma.engines.*
import kotlinx.coroutines.flow.MutableSharedFlow

private const val TAG = "LiteRtLmSession"

/**
 * LiteRT-LM Session implementation.
 *
 * Key Design Decision: Chunk Buffering
 * - MediaPipe: addQueryChunk() directly on session
 * - LiteRT-LM: sendMessage() takes complete message
 * - Solution: Buffer chunks in StringBuilder, send on generateResponse()
 */
class LiteRtLmSession(
    engine: Engine,
    config: SessionConfig,
    private val resultFlow: MutableSharedFlow<Pair<String, Boolean>>,
    private val errorFlow: MutableSharedFlow<Throwable>
) : InferenceSession {

    private val conversation: Conversation

    // Extra context for thinking mode (Jinja template variable)
    // Always pass enable_thinking: Qwen3 needs explicit false to disable thinking
    private val extraContext: Map<String, Any> = mapOf("enable_thinking" to config.enableThinking)

    // Chunk buffering (MediaPipe compatibility) - thread-safe access
    private val pendingPrompt = StringBuilder()
    private val promptLock = Any()
    @Volatile private var pendingImage: ByteArray? = null
    @Volatile private var pendingAudio: ByteArray? = null

    init {
        // Build sampler config
        val samplerConfig = SamplerConfig(
            topK = config.topK,
            topP = (config.topP ?: 0.95f).toDouble(),
            temperature = config.temperature.toDouble(),
        )

        // Build conversation config
        val conversationConfig = ConversationConfig(
            samplerConfig = samplerConfig,
            systemInstruction = config.systemInstruction?.let { Contents.of(it) },
        )

        conversation = engine.createConversation(conversationConfig)
        Log.d(TAG, "Created LiteRT-LM conversation with topK=${config.topK}, temp=${config.temperature}")
    }

    override fun addQueryChunk(prompt: String) {
        // Accumulate chunks (LiteRT-LM uses sendMessage, not addQueryChunk)
        synchronized(promptLock) {
            pendingPrompt.append(prompt)
            Log.v(TAG, "Accumulated chunk: ${prompt.length} chars, total: ${pendingPrompt.length}")
        }
    }

    override fun addImage(imageBytes: ByteArray) {
        // Store image for multimodal message (thread-safe)
        synchronized(promptLock) {
            pendingImage = imageBytes
        }
        Log.d(TAG, "Added image: ${imageBytes.size} bytes")
    }

    override fun addAudio(audioBytes: ByteArray) {
        // Store audio for multimodal message (thread-safe)
        synchronized(promptLock) {
            pendingAudio = audioBytes
        }
        Log.d(TAG, "Added audio: ${audioBytes.size} bytes")
    }

    override fun generateResponse(): String {
        val message = buildAndConsumeMessage()
        Log.d(TAG, "Generating sync response for message: ${message.toString().length} chars")

        return try {
            val response = if (extraContext.isNotEmpty()) {
                conversation.sendMessage(message, extraContext)
            } else {
                conversation.sendMessage(message)
            }
            val thinking = response.channels["thought"]
            val text = response.toString()
            if (!thinking.isNullOrEmpty()) {
                "<|channel>thought\n$thinking<channel|>$text"
            } else {
                text
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error generating response", e)
            if (!errorFlow.tryEmit(e)) {
                Log.w(TAG, "Error emission dropped (buffer full): ${e.message}")
            }
            throw e
        }
    }

    override fun generateResponseAsync() {
        val message = buildAndConsumeMessage()
        Log.d(TAG, "Generating async response for message: ${message.toString().length} chars")

        val callback = object : MessageCallback {
            override fun onMessage(msg: Message) {
                // Combine thinking + text into single emission to prevent DROP_OLDEST loss
                // (buffer=1, two rapid tryEmit calls would drop the first)
                val thinking = msg.channels["thought"]
                val text = msg.toString()
                val combined = buildString {
                    if (!thinking.isNullOrEmpty()) {
                        append("<|channel>thought\n$thinking<channel|>")
                    }
                    if (text.isNotEmpty()) {
                        append(text)
                    }
                }
                if (combined.isNotEmpty()) {
                    resultFlow.tryEmit(combined to false)
                }
            }

            override fun onDone() {
                resultFlow.tryEmit("" to true)
            }

            override fun onError(throwable: Throwable) {
                Log.e(TAG, "Async generation error", throwable)
                if (!errorFlow.tryEmit(throwable)) {
                    Log.w(TAG, "Error emission dropped (buffer full): ${throwable.message}")
                }
                resultFlow.tryEmit("" to true)
            }
        }

        try {
            if (extraContext.isNotEmpty()) {
                conversation.sendMessageAsync(message, callback, extraContext)
            } else {
                conversation.sendMessageAsync(message, callback)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start async generation", e)
            if (!errorFlow.tryEmit(e)) {
                Log.w(TAG, "Error emission dropped (buffer full): ${e.message}")
            }
            resultFlow.tryEmit("" to true)
        }
    }

    override fun sizeInTokens(prompt: String): Int {
        // LiteRT-LM doesn't expose tokenizer API
        // Estimate: ~4 characters per token (GPT-style average)
        val estimate = (prompt.length + 3) / 4
        Log.w(TAG, "sizeInTokens: LiteRT-LM does not support token counting. " +
                "Using estimate (~4 chars/token): $estimate tokens for ${prompt.length} chars. " +
                "This may be inaccurate for non-English text.")
        return estimate
    }

    override fun cancelGeneration() {
        try {
            conversation.cancelProcess()
            Log.i(TAG, "cancelGeneration: cancelled via Conversation.cancelProcess()")
        } catch (e: Exception) {
            Log.w(TAG, "cancelGeneration: failed to cancel", e)
        }
    }

    override fun close() {
        try {
            conversation.close()
            Log.d(TAG, "Conversation closed")
        } catch (e: Exception) {
            Log.w(TAG, "Error closing conversation", e)
        }
    }

    /**
     * Build Message from accumulated chunks/images/audio and clear buffer.
     * Thread-safe: uses synchronized access to pending data.
     *
     * Note: Use Contents.of() for multimodal messages (audio/image support).
     * Message.of() only works for text-only messages.
     *
     * Content order: Image → Audio → Text (last)
     * AI Edge Gallery: "add text after image and audio for accurate last token"
     */
    private fun buildAndConsumeMessage(): Contents {
        val text: String
        val image: ByteArray?
        val audio: ByteArray?
        synchronized(promptLock) {
            text = pendingPrompt.toString()
            pendingPrompt.clear()
            image = pendingImage
            pendingImage = null
            audio = pendingAudio
            pendingAudio = null
        }

        // Build content list based on available modalities
        // Order: Image → Audio → Text (matching AI Edge Gallery pattern)
        val contents = mutableListOf<Content>()

        image?.let {
            contents.add(Content.ImageBytes(it))
            Log.d(TAG, "Added image: ${it.size} bytes")
        }

        audio?.let {
            // LiteRT-LM expects WAV format (miniaudio decoder needs container format)
            // Flutter sends WAV data, pass it through directly
            contents.add(Content.AudioBytes(it))
            Log.d(TAG, "Added audio: ${it.size} bytes (WAV format)")
        }

        // Text should be last for multimodal messages
        if (text.isNotEmpty() || contents.isEmpty()) {
            contents.add(Content.Text(text))
            Log.d(TAG, "Added text: ${text.length} chars")
        }

        Log.d(TAG, "Building message with ${contents.size} content items")
        return Contents.of(contents)
    }
}
