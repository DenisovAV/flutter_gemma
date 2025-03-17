package dev.flutterberlin.flutter_gemma

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession

import java.io.File
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

data class InferenceModelConfig(val modelPath: String, val maxTokens: Int, val supportedLoraRanks: List<Int>?, val preferredBackend: LlmInference.Backend,)
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

    val partialResultsMutable = MutableSharedFlow<Pair<String, Boolean>>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    val partialResults: SharedFlow<Pair<String, Boolean>> = partialResultsMutable.asSharedFlow()

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
                .setPreferredBackend(config.preferredBackend)
//                .setResultListener { result, done ->
//                    _partialResults.tryEmit(result to done)
//                }
//                .setErrorListener { error ->
//                    _errors.tryEmit(Exception(error.message))
//                }

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
    val inferenceModel: InferenceModel?,
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

    fun sizeInTokens(prompt: String): Int {
        return session.sizeInTokens(prompt)
    }

    fun addQueryChunk(prompt: String) {
        session.addQueryChunk(prompt)
    }

    fun generateResponse(): String {
        return session.generateResponse()
    }

    fun generateResponseAsync() {
        session.generateResponseAsync { result, done ->
            inferenceModel?.partialResultsMutable?.tryEmit(result to done)
        }
    }

    fun close() {
        session.close()
    }
}
