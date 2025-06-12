package dev.flutterberlin.flutter_gemma

import android.content.Context
import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.io.File
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.asSharedFlow

// Enum generated via Pigeon
enum class PreferredBackendEnum(val value: Int) {
    UNKNOWN(0), CPU(1), GPU(2), GPU_FLOAT16(3), GPU_MIXED(4), GPU_FULL(5), TPU(6)
}

// Configuration data classes

data class InferenceModelConfig(
    val modelPath: String,
    val maxTokens: Int,
    val supportedLoraRanks: List<Int>?,
    val preferredBackend: PreferredBackendEnum?,
    val maxNumImages: Int?,
)

data class InferenceSessionConfig(
    val temperature: Float,
    val randomSeed: Int,
    val topK: Int,
    val topP: Float?,
    val loraPath: String?,
    val enableVisionModality: Boolean?,
)

// Updated InferenceModel

class InferenceModel(
    context: Context,
    val config: InferenceModelConfig
) {
    val llmInference: LlmInference

    private val _partialResults = MutableSharedFlow<Pair<String, Boolean>>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val partialResults: SharedFlow<Pair<String, Boolean>> = _partialResults.asSharedFlow()

    private val _errors = MutableSharedFlow<Throwable>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    val errors: SharedFlow<Throwable> = _errors.asSharedFlow()

    private val modelExists: Boolean
        get() = File(config.modelPath).exists()

    init {
        if (!modelExists) {
            throw IllegalArgumentException("Model not found at path: ${config.modelPath}")
        }
        try {
            val optionsBuilder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(config.modelPath)
                .setMaxTokens(config.maxTokens)
                .apply {
                    config.supportedLoraRanks?.let { setSupportedLoraRanks(it) }
                    config.preferredBackend?.let {
                        val backendEnum = LlmInference.Backend.values().getOrNull(it.ordinal)
                            ?: throw IllegalArgumentException("Invalid preferredBackend value: ${it.ordinal}")
                        setPreferredBackend(backendEnum)
                    }
                    config.maxNumImages?.let { setMaxNumImages(it) }
                }
            val options = optionsBuilder.build()
            llmInference = LlmInference.createFromOptions(context, options)
        } catch (e: Exception) {
            throw RuntimeException("Failed to initialize LlmInference: ${e.message}", e)
        }
    }

    fun createSession(config: InferenceSessionConfig): InferenceModelSession {
        return InferenceModelSession(llmInference, config, _partialResults, _errors)
    }

    fun close() {
        llmInference.close()
    }
}

// Updated InferenceModelSession

class InferenceModelSession(
    private val llmInference: LlmInference,
    val config: InferenceSessionConfig,
    private val resultFlow: MutableSharedFlow<Pair<String, Boolean>>,
    private val errorFlow: MutableSharedFlow<Throwable>
) {
    private val session: LlmInferenceSession

    init {
        val sessionOptionsBuilder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
            .setTemperature(config.temperature)
            .setRandomSeed(config.randomSeed)
            .setTopK(config.topK)
            .apply {
                config.topP?.let { setTopP(it) }
                config.loraPath?.let { setLoraPath(it) }
                config.enableVisionModality?.let { enableVision ->
                    setGraphOptions(
                        GraphOptions.builder()
                            .setEnableVisionModality(enableVision)
                            .build()
                    )
                }
            }

        val sessionOptions = sessionOptionsBuilder.build()
        session = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
    }

    fun sizeInTokens(prompt: String): Int = session.sizeInTokens(prompt)

    fun addQueryChunk(prompt: String) = session.addQueryChunk(prompt)

    fun addImage(imageBytes: ByteArray) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: throw IllegalArgumentException("Failed to decode image bytes")
        val mpImage = BitmapImageBuilder(bitmap).build()
        session.addImage(mpImage)
    }

    fun generateResponse(): String = session.generateResponse()

    fun generateResponseAsync() {
        session.generateResponseAsync { result, done ->
            result?.let {
                resultFlow.tryEmit(it to done)
            }
        }
    }

    fun close() {
        session.close()
    }
}