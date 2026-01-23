package dev.flutterberlin.flutter_gemma.engines.mediapipe

import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import dev.flutterberlin.flutter_gemma.PreferredBackendEnum
import dev.flutterberlin.flutter_gemma.engines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.io.File

/**
 * Adapter wrapping existing MediaPipe LlmInference.
 *
 * This adapter wraps the existing MediaPipe implementation without
 * modifying the original InferenceModel logic.
 */
class MediaPipeEngine(
    private val context: Context
) : InferenceEngine {

    private var llmInference: LlmInference? = null

    override var isInitialized: Boolean = false
        private set

    override val capabilities = EngineCapabilities(
        supportsVision = true,
        supportsAudio = false,
        supportsFunctionCalls = true, // Manual via chat templates
        supportsStreaming = true,
        supportsTokenCounting = true, // MediaPipe has sizeInTokens()
        maxTokenLimit = 2048,
    )

    // SharedFlow instances (same pattern as existing InferenceModel)
    private val _partialResults = FlowFactory.createSharedFlow<Pair<String, Boolean>>()
    override val partialResults: SharedFlow<Pair<String, Boolean>> = _partialResults.asSharedFlow()

    private val _errors = FlowFactory.createSharedFlow<Throwable>()
    override val errors: SharedFlow<Throwable> = _errors.asSharedFlow()

    override suspend fun initialize(config: EngineConfig) {
        // Validate model file exists
        if (!File(config.modelPath).exists()) {
            throw IllegalArgumentException("Model not found at path: ${config.modelPath}")
        }

        try {
            // Build LlmInferenceOptions (same logic as existing InferenceModel.kt)
            val optionsBuilder = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(config.modelPath)
                .setMaxTokens(config.maxTokens)
                .apply {
                    config.supportedLoraRanks?.let { setSupportedLoraRanks(it) }
                    config.preferredBackend?.let {
                        // Explicit mapping instead of ordinal-based (safer)
                        val backendEnum: LlmInference.Backend? = when (it) {
                            PreferredBackendEnum.CPU -> LlmInference.Backend.CPU
                            PreferredBackendEnum.GPU,
                            PreferredBackendEnum.GPU_FLOAT16,
                            PreferredBackendEnum.GPU_MIXED,
                            PreferredBackendEnum.GPU_FULL -> LlmInference.Backend.GPU
                            PreferredBackendEnum.UNKNOWN,
                            PreferredBackendEnum.TPU -> null // Not supported by MediaPipe, use default
                        }
                        backendEnum?.let { backend -> setPreferredBackend(backend) }
                    }
                    config.maxNumImages?.let { setMaxNumImages(it) }
                }

            val options = optionsBuilder.build()
            llmInference = LlmInference.createFromOptions(context, options)
            isInitialized = true
        } catch (e: Exception) {
            throw RuntimeException("Failed to initialize MediaPipe LlmInference: ${e.message}", e)
        }
    }

    override fun createSession(config: SessionConfig): InferenceSession {
        val inference = llmInference
            ?: throw IllegalStateException("Engine not initialized. Call initialize() first.")
        return MediaPipeSession(inference, config, _partialResults, _errors)
    }

    override fun close() {
        llmInference?.close()
        llmInference = null
        isInitialized = false
    }
}
