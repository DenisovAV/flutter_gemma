package dev.flutterberlin.flutter_gemma

import android.content.Context
import android.health.connect.datatypes.units.Temperature
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import java.io.File
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

class InferenceModel private constructor(context: Context, maxTokens: Int, temperature: Float, randomSeed: Int, topK: Int) {
    private var llmInference: LlmInference

    private val _partialResults = MutableSharedFlow<Pair<String, Boolean>>(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    val partialResults: SharedFlow<Pair<String, Boolean>> = _partialResults.asSharedFlow()

    private val modelExists: Boolean
        get() = File(MODEL_PATH).exists()

    init {
        if (!modelExists) {
            throw IllegalArgumentException("Model not found at path: $MODEL_PATH")
        }

        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(MODEL_PATH)
            .setMaxTokens(maxTokens)
            .setTemperature(temperature)
            .setRandomSeed(randomSeed)
            .setTopK(topK)
            .setResultListener { partialResult, done ->
                _partialResults.tryEmit(partialResult to done)
            }
            .build()

        llmInference = LlmInference.createFromOptions(context, options)
    }

    fun generateResponse(prompt: String): String? {
        return llmInference.generateResponse(prompt)
    }

    fun generateResponseAsync(prompt: String) {
        llmInference.generateResponseAsync(prompt)
    }

    companion object {
//        private const val MODEL_PATH = "/data/local/tmp/llm/model.bin"
        private lateinit var MODEL_PATH : String
        private var instance: InferenceModel? = null

        fun getInstance(context: Context, modelPath: String, maxTokens: Int, temperature: Float, randomSeed: Int, topK: Int): InferenceModel {
            MODEL_PATH = modelPath
            return if (instance != null) {
                instance!!
            } else {
                InferenceModel(context, maxTokens, temperature, randomSeed, topK).also { instance = it }
            }
        }
    }
}
