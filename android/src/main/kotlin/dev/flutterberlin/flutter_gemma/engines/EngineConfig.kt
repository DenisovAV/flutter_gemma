package dev.flutterberlin.flutter_gemma.engines

import dev.flutterberlin.flutter_gemma.PreferredBackend
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * Engine initialization configuration.
 */
data class EngineConfig(
    val modelPath: String,
    val maxTokens: Int,
    val supportedLoraRanks: List<Int>? = null,
    val preferredBackend: PreferredBackend? = null,
    val maxNumImages: Int? = null,
    val supportAudio: Boolean? = null,
)

/**
 * Session-level configuration (sampling parameters).
 */
data class SessionConfig(
    val temperature: Float = 1.0f,
    val randomSeed: Int = 0,
    val topK: Int = 40,
    val topP: Float? = null,
    val loraPath: String? = null,
    val enableVisionModality: Boolean? = null,
    val enableAudioModality: Boolean? = null,
)

/**
 * Helper to create SharedFlow instances with consistent configuration.
 */
object FlowFactory {
    fun <T> createSharedFlow(): MutableSharedFlow<T> = MutableSharedFlow(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
}
