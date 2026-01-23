package dev.flutterberlin.flutter_gemma.engines.mediapipe

import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import dev.flutterberlin.flutter_gemma.engines.*
import kotlinx.coroutines.flow.MutableSharedFlow

/**
 * Adapter wrapping MediaPipe LlmInferenceSession.
 *
 * Direct pass-through to existing MediaPipe implementation.
 * Same logic as existing InferenceModelSession.kt.
 */
class MediaPipeSession(
    private val llmInference: LlmInference,
    config: SessionConfig,
    private val resultFlow: MutableSharedFlow<Pair<String, Boolean>>,
    private val errorFlow: MutableSharedFlow<Throwable>
) : InferenceSession {

    private val session: LlmInferenceSession

    init {
        // Same session creation logic as existing InferenceModelSession.kt
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

    override fun addQueryChunk(prompt: String) {
        session.addQueryChunk(prompt)
    }

    override fun addImage(imageBytes: ByteArray) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: throw IllegalArgumentException("Failed to decode image bytes")
        val mpImage = BitmapImageBuilder(bitmap).build()
        session.addImage(mpImage)
    }

    override fun generateResponse(): String {
        return session.generateResponse() ?: ""
    }

    override fun generateResponseAsync() {
        session.generateResponseAsync { result, done ->
            if (result != null) {
                resultFlow.tryEmit(result to done)
            } else if (done) {
                resultFlow.tryEmit("" to true)
            }
        }
    }

    override fun sizeInTokens(prompt: String): Int {
        return session.sizeInTokens(prompt)
    }

    override fun cancelGeneration() {
        session.cancelGenerateResponseAsync()
    }

    override fun close() {
        session.close()
    }
}
