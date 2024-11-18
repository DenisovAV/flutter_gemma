package dev.flutterberlin.flutter_gemma

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
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
    numOfSupportedLoraRanks: Int?,
    supportedLoraRanks: List<Int>?,
) {
    private var llmInference: LlmInference

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
            .setTemperature(temperature)
            .setRandomSeed(randomSeed)
            .setTopK(topK)
            .setErrorListener { error ->
                _errors.tryEmit(error)
            }
            .setResultListener { partialResult, done ->
                _partialResults.tryEmit(partialResult to done)
            }

        numOfSupportedLoraRanks?.let { optionsBuilder.setNumOfSupportedLoraRanks(it) }
        supportedLoraRanks?.let { optionsBuilder.setSupportedLoraRanks(it) }
        loraPath?.let { optionsBuilder.setLoraPath(it) }

        val options = optionsBuilder.build()

        llmInference =
            LlmInference.createFromOptions(context, options)
        } catch (e: Exception) {
            throw RuntimeException("Failed to create LlmInference instance: ${e.message}", e)
        }
    }

    fun generateResponse(prompt: String): String? {
        return llmInference.generateResponse(prompt)
    }

    fun generateResponseAsync(prompt: String) {
        llmInference.generateResponseAsync(prompt)
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
            numOfSupportedLoraRanks: Int?,
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
                    numOfSupportedLoraRanks,
                    supportedLoraRanks
                ).also { instance = it }
            }
        }
    }
}
