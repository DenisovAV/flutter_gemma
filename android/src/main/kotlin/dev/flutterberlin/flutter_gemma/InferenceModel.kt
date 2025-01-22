package dev.flutterberlin.flutter_gemma

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.io.File
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

class InferenceModel private constructor(
    context: Context,
    private val modelPath: String,
    maxTokens: Int,
    temperature: Float,
    randomSeed: Int,
    topK: Int,
    loraPath: String?,
    supportedLoraRanks: List<Int>?
) {
    private val llmInference: LlmInference
    private var session: LlmInferenceSession? = null

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
        get() = File(modelPath).exists()

    init {
        if (!modelExists) {
            throw IllegalArgumentException("Model not found at path: $modelPath")
        }
        try {
            val optionsBuilder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(maxTokens)
                .setSupportedLoraRanks(supportedLoraRanks)
                .setResultListener { result, done ->
                    _partialResults.tryEmit(result to done)
                }
                .setErrorListener { error ->
                    _errors.tryEmit(Exception(error.message))
                }

            val options = optionsBuilder.build()
            llmInference = LlmInference.createFromOptions(context, options)

            val sessionOptionsBuilder = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                .setTemperature(temperature)
                .setRandomSeed(randomSeed)
                .setTopK(topK)

            loraPath?.let { sessionOptionsBuilder.setLoraPath(it) }

            val sessionOptions = sessionOptionsBuilder.build()

            session = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)

        } catch (e: Exception) {
            throw RuntimeException("Failed to initialize LlmInference or Session: ${e.message}", e)
        }
    }

    fun generateResponse(prompt: String): String? {
        return try {
            session?.addQueryChunk(prompt)
            session?.generateResponse()
        } catch (e: Exception) {
            _errors.tryEmit(e)
            null
        }
    }

    fun generateResponseAsync(prompt: String) {
        try {
            session?.addQueryChunk(prompt)
            session?.generateResponseAsync()
        } catch (e: Exception) {
            _errors.tryEmit(e)
        }
    }


    companion object {
        private var instance: InferenceModel? = null

        fun getInstance(
            context: Context,
            modelPath: String,
            maxTokens: Int,
            temperature: Float,
            randomSeed: Int,
            topK: Int,
            loraPath: String?,
            supportedLoraRanks: List<Int>?
        ): InferenceModel {
            return if (instance != null) {
                instance!!
            } else {
                InferenceModel(
                    context,
                    modelPath,
                    maxTokens,
                    temperature,
                    randomSeed,
                    topK,
                    loraPath,
                    supportedLoraRanks
                ).also { instance = it }
            }
        }
    }
}
