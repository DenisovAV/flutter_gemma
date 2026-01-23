package dev.flutterberlin.flutter_gemma.engines.litertlm

import android.util.Log
import com.google.ai.edge.litertlm.Content
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

    // Chunk buffering (MediaPipe compatibility) - thread-safe access
    private val pendingPrompt = StringBuilder()
    private val promptLock = Any()
    @Volatile private var pendingImage: ByteArray? = null

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
            systemMessage = null, // System message not exposed in current API
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

    override fun generateResponse(): String {
        val message = buildAndConsumeMessage()
        Log.d(TAG, "Generating sync response for message: ${message.toString().length} chars")

        return try {
            val response = conversation.sendMessage(message)
            response.toString()
        } catch (e: Exception) {
            Log.e(TAG, "Error generating response", e)
            errorFlow.tryEmit(e)
            throw e
        }
    }

    override fun generateResponseAsync() {
        val message = buildAndConsumeMessage()
        Log.d(TAG, "Generating async response for message: ${message.toString().length} chars")

        try {
            // Use callback-based API
            conversation.sendMessageAsync(message, object : MessageCallback {
                override fun onMessage(message: Message) {
                    val text = message.toString()
                    resultFlow.tryEmit(text to false)
                }

                override fun onDone() {
                    resultFlow.tryEmit("" to true)
                }

                override fun onError(throwable: Throwable) {
                    Log.e(TAG, "Async generation error", throwable)
                    errorFlow.tryEmit(throwable)
                    resultFlow.tryEmit("" to true)
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start async generation", e)
            errorFlow.tryEmit(e)
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
        // LiteRT-LM 0.9.x doesn't expose cancellation API
        Log.w(TAG, "cancelGeneration: Not yet supported by LiteRT-LM SDK")
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
     * Build Message from accumulated chunks/images and clear buffer.
     * Thread-safe: uses synchronized access to pendingPrompt and pendingImage.
     *
     * Note: Message.of() is deprecated in newer SDK versions but Contents
     * is not exported in 0.9.0-alpha01. Text comes first per API convention.
     */
    private fun buildAndConsumeMessage(): Message {
        val text: String
        val image: ByteArray?
        synchronized(promptLock) {
            text = pendingPrompt.toString()
            pendingPrompt.clear()
            image = pendingImage
            pendingImage = null
        }

        return if (image != null) {
            // Multimodal message: text first, then image (per API convention)
            Message.of(
                Content.Text(text),
                Content.ImageBytes(image)
            )
        } else {
            // Text-only message
            Message.of(text)
        }
    }
}
