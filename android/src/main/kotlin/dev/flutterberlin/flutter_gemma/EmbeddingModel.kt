package dev.flutterberlin.flutter_gemma

import android.content.Context
import android.os.Build
import com.google.ai.edge.localagents.rag.models.EmbedData
import com.google.ai.edge.localagents.rag.models.EmbeddingRequest
import com.google.ai.edge.localagents.rag.models.GemmaEmbeddingModel
import com.google.common.collect.ImmutableList
import java.io.File
import java.util.concurrent.Executors
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.runBlocking

class EmbeddingModel(
    private val context: Context,
    private val modelPath: String,
    private val tokenizerPath: String,
    private val useGPU: Boolean = false // Use CPU by default to avoid GPU delegate issues
) {
    private var gemmaEmbeddingModel: GemmaEmbeddingModel? = null
    
    companion object {
        const val EMBEDDING_DIMENSION = 768 // EmbeddingGemma/Gecko output dimension
    }
    
    fun initialize() {
        // Verify files exist
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file not found: $modelPath")
        }

        val tokenizerFile = File(tokenizerPath)
        if (!tokenizerFile.exists()) {
            throw IllegalArgumentException("Tokenizer file not found: $tokenizerPath")
        }

        // Auto-detect: Force CPU on emulator (no GPU/OpenCL support)
        val effectiveUseGPU = if (useGPU && isEmulator()) {
            android.util.Log.i("EmbeddingModel", "Emulator detected, forcing CPU backend")
            false
        } else {
            useGPU
        }

        // Initialize the new GemmaEmbeddingModel from RAG library
        gemmaEmbeddingModel = GemmaEmbeddingModel(
            modelPath,
            tokenizerPath,
            effectiveUseGPU
        )
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.startsWith("generic")
            || Build.MODEL.contains("Emulator")
            || Build.MODEL.contains("Android SDK built for x86")
            || Build.PRODUCT.contains("sdk")
    }
    
    fun embed(text: String): List<Double> {
        val model = gemmaEmbeddingModel ?: throw IllegalStateException("Tokenizer not initialized")

        try {
            // Create embedding request with proper structure
            val embedData = EmbedData.builder<String>()
                .setData(text)
                .setTask(EmbedData.TaskType.SEMANTIC_SIMILARITY)
                .build()

            val request = EmbeddingRequest.create(ImmutableList.of(embedData))

            // Get embeddings using the async API
            return runBlocking {
                val embeddings = model.getEmbeddings(request).await()
                // Convert ImmutableList<Float> to List<Double>
                embeddings.map { it.toDouble() }
            }
        } catch (e: Exception) {
            throw RuntimeException("Failed to generate embedding", e)
        }
    }
    
    fun close() {
        // GemmaEmbeddingModel doesn't have explicit close in the RAG library
        // but we can null it out to free resources
        gemmaEmbeddingModel = null
    }
}