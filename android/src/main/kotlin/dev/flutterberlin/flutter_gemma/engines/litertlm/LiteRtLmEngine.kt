package dev.flutterberlin.flutter_gemma.engines.litertlm

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig as LiteRtEngineConfig
import dev.flutterberlin.flutter_gemma.PreferredBackendEnum
import dev.flutterberlin.flutter_gemma.engines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.io.File

private const val TAG = "LiteRtLmEngine"

/**
 * LiteRT-LM Engine implementation for .litertlm files.
 *
 * Key Differences from MediaPipe:
 * - Uses Conversation API (not session-based)
 * - No chunk accumulation at engine level (handled by LiteRtLmSession)
 * - Supports audio modality
 * - Faster initialization (~1-2s with cache vs ~10s cold start)
 */
class LiteRtLmEngine(
    private val context: Context
) : InferenceEngine {

    private var engine: Engine? = null

    override var isInitialized: Boolean = false
        private set

    override val capabilities = EngineCapabilities(
        supportsVision = true,
        supportsAudio = true, // LiteRT-LM supports audio
        supportsFunctionCalls = true, // Native @Tool annotation support
        supportsStreaming = true,
        supportsTokenCounting = false, // No direct API, must estimate
        maxTokenLimit = 4096, // Higher context window
    )

    private val _partialResults = FlowFactory.createSharedFlow<Pair<String, Boolean>>()
    override val partialResults: SharedFlow<Pair<String, Boolean>> = _partialResults.asSharedFlow()

    private val _errors = FlowFactory.createSharedFlow<Throwable>()
    override val errors: SharedFlow<Throwable> = _errors.asSharedFlow()

    override suspend fun initialize(config: EngineConfig) {
        // Validate model file
        val modelFile = File(config.modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model not found at path: ${config.modelPath}")
        }

        // Map PreferredBackendEnum to LiteRT-LM Backend
        val backend = when (config.preferredBackend) {
            PreferredBackendEnum.GPU,
            PreferredBackendEnum.GPU_FLOAT16,
            PreferredBackendEnum.GPU_MIXED,
            PreferredBackendEnum.GPU_FULL -> Backend.GPU
            PreferredBackendEnum.CPU -> Backend.CPU
            else -> Backend.CPU // Default to CPU for safety
        }

        try {
            // Configure engine with cache directory for faster reloads
            // visionBackend is required for multimodal models (image support)
            val visionBackend = if (config.maxNumImages != null && config.maxNumImages > 0) backend else null

            val engineConfig = LiteRtEngineConfig(
                modelPath = config.modelPath,
                backend = backend,
                visionBackend = visionBackend,
                maxNumTokens = config.maxTokens,
                cacheDir = context.cacheDir.absolutePath, // Improves reload time 10s→1-2s
            )

            Log.i(TAG, "Initializing LiteRT-LM engine with backend: $backend, maxTokens: ${config.maxTokens}")

            val newEngine = Engine(engineConfig)
            newEngine.initialize() // Can take 10+ seconds on cold start, 1-2s with cache
            engine = newEngine
            isInitialized = true

            Log.i(TAG, "LiteRT-LM engine initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize LiteRT-LM engine", e)
            throw RuntimeException("Failed to initialize LiteRT-LM: ${e.message}", e)
        }
    }

    override fun createSession(config: SessionConfig): InferenceSession {
        val currentEngine = engine
            ?: throw IllegalStateException("Engine not initialized. Call initialize() first.")
        return LiteRtLmSession(currentEngine, config, _partialResults, _errors)
    }

    override fun close() {
        try {
            engine?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing LiteRT-LM engine", e)
        }
        engine = null
        isInitialized = false
        Log.i(TAG, "LiteRT-LM engine closed")
    }
}
