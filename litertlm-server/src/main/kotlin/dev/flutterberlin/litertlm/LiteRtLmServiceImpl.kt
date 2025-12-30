package dev.flutterberlin.litertlm

import com.google.ai.edge.litertlm.*
import dev.flutterberlin.litertlm.proto.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.LoggerFactory
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class LiteRtLmServiceImpl : LiteRtLmServiceGrpcKt.LiteRtLmServiceCoroutineImplBase() {

    private val logger = LoggerFactory.getLogger(LiteRtLmServiceImpl::class.java)

    // Mutex to protect engine state from concurrent access
    private val engineMutex = Mutex()
    private var engine: Engine? = null
    private val conversations = ConcurrentHashMap<String, Conversation>()
    private val conversationCounter = AtomicInteger(0)

    override suspend fun initialize(request: InitializeRequest): InitializeResponse {
        logger.info("Initializing engine with model: ${request.modelPath}")

        // Validate model path
        if (request.modelPath.isBlank()) {
            return InitializeResponse.newBuilder()
                .setSuccess(false)
                .setError("Model path cannot be empty")
                .build()
        }

        val modelFile = File(request.modelPath)
        if (!modelFile.exists()) {
            return InitializeResponse.newBuilder()
                .setSuccess(false)
                .setError("Model file not found: ${request.modelPath}")
                .build()
        }

        // Use mutex to protect engine state
        return engineMutex.withLock {
            try {
                // Close existing engine if any
                engine?.close()

                val backend = when (request.backend.lowercase()) {
                    "gpu" -> Backend.GPU
                    else -> Backend.CPU
                }

                // Use data class constructor (LiteRT-LM 0.9+ API)
                val engineConfig = EngineConfig(
                    modelPath = request.modelPath,
                    backend = backend,
                    maxNumTokens = request.maxTokens,
                    visionBackend = if (request.enableVision) backend else null
                )

                engine = Engine(engineConfig)
                engine!!.initialize()

                logger.info("Engine initialized successfully")

                InitializeResponse.newBuilder()
                    .setSuccess(true)
                    .setModelInfo("{\"backend\": \"${request.backend}\", \"maxTokens\": ${request.maxTokens}}")
                    .build()
            } catch (e: Exception) {
                logger.error("Failed to initialize engine", e)
                InitializeResponse.newBuilder()
                    .setSuccess(false)
                    .setError(e.message ?: "Unknown error during initialization")
                    .build()
            }
        }
    }

    override suspend fun createConversation(request: CreateConversationRequest): CreateConversationResponse {
        // Get engine reference under lock to ensure thread safety
        val currentEngine = engineMutex.withLock { this.engine }
        if (currentEngine == null) {
            return CreateConversationResponse.newBuilder()
                .setError("Engine not initialized. Call Initialize first.")
                .build()
        }

        return try {
            val engine = currentEngine

            // Build sampler config if provided
            val samplerConfig = request.samplerConfig?.let { sampler ->
                com.google.ai.edge.litertlm.SamplerConfig(
                    topK = if (sampler.topK > 0) sampler.topK else 40,
                    topP = if (sampler.topP > 0) sampler.topP.toDouble() else 0.95,
                    temperature = if (sampler.temperature > 0) sampler.temperature.toDouble() else 0.8
                )
            }

            // Use data class constructor (LiteRT-LM 0.9+ API)
            val conversationConfig = ConversationConfig(
                systemMessage = if (request.systemMessage.isNotEmpty()) Message.of(request.systemMessage) else null,
                samplerConfig = samplerConfig
            )

            val conversation = engine.createConversation(conversationConfig)
            val id = "conv_${conversationCounter.incrementAndGet()}"
            conversations[id] = conversation

            logger.info("Created conversation: $id")

            CreateConversationResponse.newBuilder()
                .setConversationId(id)
                .build()
        } catch (e: Exception) {
            logger.error("Failed to create conversation", e)
            CreateConversationResponse.newBuilder()
                .setError(e.message ?: "Unknown error creating conversation")
                .build()
        }
    }

    override fun chat(request: ChatRequest): Flow<ChatResponse> = flow {
        val conversation = conversations[request.conversationId]
        if (conversation == null) {
            emit(
                ChatResponse.newBuilder()
                    .setError("Conversation not found: ${request.conversationId}")
                    .setDone(true)
                    .build()
            )
            return@flow
        }

        try {
            logger.debug("Chat request: ${request.text.take(50)}...")

            val message = Message.of(request.text)

            // Stream response using Flow
            conversation.sendMessageAsync(message).collect { response ->
                emit(
                    ChatResponse.newBuilder()
                        .setText(response.toString())
                        .setDone(false)
                        .build()
                )
            }

            // Send completion
            emit(
                ChatResponse.newBuilder()
                    .setDone(true)
                    .build()
            )

            logger.debug("Chat completed for ${request.conversationId}")
        } catch (e: Exception) {
            logger.error("Error during chat", e)
            emit(
                ChatResponse.newBuilder()
                    .setError(e.message ?: "Unknown error during chat")
                    .setDone(true)
                    .build()
            )
        }
    }

    override fun chatWithImage(request: ChatWithImageRequest): Flow<ChatResponse> = flow {
        val conversation = conversations[request.conversationId]
        if (conversation == null) {
            emit(
                ChatResponse.newBuilder()
                    .setError("Conversation not found: ${request.conversationId}")
                    .setDone(true)
                    .build()
            )
            return@flow
        }

        try {
            logger.debug("Chat with image request: ${request.text.take(50)}...")

            // Create multimodal message with image
            val contents = mutableListOf<Content>()

            if (request.image.size() > 0) {
                contents.add(Content.ImageBytes(request.image.toByteArray()))
            }

            if (request.text.isNotEmpty()) {
                contents.add(Content.Text(request.text))
            }

            val message = Message.of(contents)

            // Stream response
            conversation.sendMessageAsync(message).collect { response ->
                emit(
                    ChatResponse.newBuilder()
                        .setText(response.toString())
                        .setDone(false)
                        .build()
                )
            }

            emit(
                ChatResponse.newBuilder()
                    .setDone(true)
                    .build()
            )

            logger.debug("Chat with image completed for ${request.conversationId}")
        } catch (e: Exception) {
            logger.error("Error during chat with image", e)
            emit(
                ChatResponse.newBuilder()
                    .setError(e.message ?: "Unknown error during chat with image")
                    .setDone(true)
                    .build()
            )
        }
    }

    override suspend fun closeConversation(request: CloseConversationRequest): CloseConversationResponse {
        val conversation = conversations.remove(request.conversationId)
        if (conversation != null) {
            try {
                conversation.close()
                logger.info("Closed conversation: ${request.conversationId}")
            } catch (e: Exception) {
                logger.warn("Error closing conversation", e)
            }
        }
        return CloseConversationResponse.newBuilder()
            .setSuccess(true)
            .build()
    }

    override suspend fun shutdown(request: ShutdownRequest): ShutdownResponse {
        shutdown()
        return ShutdownResponse.newBuilder()
            .setSuccess(true)
            .build()
    }

    override suspend fun healthCheck(request: HealthCheckRequest): HealthCheckResponse {
        val engineReady = engine != null
        return HealthCheckResponse.newBuilder()
            .setHealthy(engineReady)
            .setStatus(if (engineReady) "Engine ready" else "Engine not initialized")
            .build()
    }

    fun shutdown() {
        logger.info("Shutting down service...")

        // Close all conversations
        conversations.values.forEach { conversation ->
            try {
                conversation.close()
            } catch (e: Exception) {
                logger.warn("Error closing conversation during shutdown", e)
            }
        }
        conversations.clear()

        // Close engine - use runBlocking since shutdown() is not suspend
        // In production, this would be called from a coroutine context
        kotlinx.coroutines.runBlocking {
            engineMutex.withLock {
                try {
                    engine?.close()
                } catch (e: Exception) {
                    logger.warn("Error closing engine during shutdown", e)
                }
                engine = null
            }
        }

        logger.info("Service shutdown complete")
    }
}
