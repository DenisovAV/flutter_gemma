package dev.flutterberlin.flutter_gemma.engines

import android.content.Context
import dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine
import dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine

/**
 * Factory for creating inference engines.
 *
 * Engine selection strategy:
 * - MEDIAPIPE: .task, .bin, .tflite files
 * - LITERTLM: .litertlm files
 */
object EngineFactory {

    /**
     * Create engine based on file extension.
     *
     * @param modelPath Path to model file
     * @param context Android context
     * @return Appropriate engine instance
     * @throws IllegalArgumentException if file extension not recognized
     */
    fun createFromModelPath(modelPath: String, context: Context): InferenceEngine {
        return when {
            modelPath.endsWith(".litertlm", ignoreCase = true) -> LiteRtLmEngine(context)
            modelPath.endsWith(".task", ignoreCase = true) -> MediaPipeEngine(context)
            modelPath.endsWith(".bin", ignoreCase = true) -> MediaPipeEngine(context)
            modelPath.endsWith(".tflite", ignoreCase = true) -> MediaPipeEngine(context)
            else -> {
                val extension = if (modelPath.contains('.')) {
                    modelPath.substringAfterLast('.')
                } else {
                    "<no extension>"
                }
                throw IllegalArgumentException(
                    "Unsupported model format: .$extension. " +
                    "Supported: .litertlm (LiteRT-LM), .task/.bin/.tflite (MediaPipe)"
                )
            }
        }
    }

    /**
     * Create engine explicitly by type (for testing or advanced use cases).
     *
     * @param engineType Type of engine to create
     * @param context Android context
     * @return Engine instance of specified type
     */
    fun create(engineType: EngineType, context: Context): InferenceEngine {
        return when (engineType) {
            EngineType.MEDIAPIPE -> MediaPipeEngine(context)
            EngineType.LITERTLM -> LiteRtLmEngine(context)
        }
    }

    /**
     * Detect engine type from model path.
     *
     * @param modelPath Path to model file
     * @return Engine type for the given model
     * @throws IllegalArgumentException if extension not recognized
     */
    fun detectEngineType(modelPath: String): EngineType {
        return when {
            modelPath.endsWith(".litertlm", ignoreCase = true) -> EngineType.LITERTLM
            modelPath.endsWith(".task", ignoreCase = true) -> EngineType.MEDIAPIPE
            modelPath.endsWith(".bin", ignoreCase = true) -> EngineType.MEDIAPIPE
            modelPath.endsWith(".tflite", ignoreCase = true) -> EngineType.MEDIAPIPE
            else -> throw IllegalArgumentException(
                "Unsupported model format: ${modelPath.substringAfterLast('.')}"
            )
        }
    }
}

/**
 * Engine type enumeration.
 */
enum class EngineType {
    MEDIAPIPE,  // .task, .bin, .tflite
    LITERTLM    // .litertlm
}
