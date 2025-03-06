package dev.flutterberlin.flutter_gemma

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.io.File
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

data class InferenceModelConfig(val modelPath: String, val maxTokens: Int, val supportedLoraRanks: List<Int>?)
data class InferenceSessionConfig(
    val temperature: Float,
    val randomSeed: Int,
    val topK: Int,
    val loraPath: String?,
)

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
            throw IllegalArgumentException("Model not found at path: $config.modelPath")
        }
        try {
            val optionsBuilder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(config.modelPath)
                .setMaxTokens(config.maxTokens)
                .setResultListener { result, done ->
                    _partialResults.tryEmit(result to done)
                }
                .setErrorListener { error ->
                    _errors.tryEmit(Exception(error.message))
                }

            config.supportedLoraRanks?.let(optionsBuilder::setSupportedLoraRanks)

            val options = optionsBuilder.build()
            llmInference = LlmInference.createFromOptions(context, options)
        } catch (e: Exception) {
            throw RuntimeException("Failed to initialize LlmInference or Session: ${e.message}", e)
        }
    }

    fun close() {
        llmInference.close()
    }
}

class InferenceModelSession(
    llmInference: LlmInference,
    val config: InferenceSessionConfig,
) {
    private var session: LlmInferenceSession

    init {
       val sessionOptionsBuilder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
           .setTemperature(config.temperature)
           .setRandomSeed(config.randomSeed)
           .setTopK(config.topK)

       config.loraPath?.let(sessionOptionsBuilder::setLoraPath)

       val sessionOptions = sessionOptionsBuilder.build()
       session = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
    }

    fun generateResponse(prompt: String): String {
        session.addQueryChunk(prompt)
        return session.generateResponse()
    }

    fun generateResponseAsync(prompt: String) {
        session.addQueryChunk(prompt)
        session.generateResponseAsync()
    }

    fun close() {
        session.close()
    }
}
