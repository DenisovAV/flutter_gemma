package dev.flutterberlin.litertlm

import com.google.ai.edge.litertlm.*
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import dev.flutterberlin.litertlm.proto.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.LoggerFactory
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.imageio.ImageIO

class LiteRtLmServiceImpl : LiteRtLmServiceGrpcKt.LiteRtLmServiceCoroutineImplBase() {

    private val logger = LoggerFactory.getLogger(LiteRtLmServiceImpl::class.java)

    // Mutex to protect engine state from concurrent access
    private val engineMutex = Mutex()
    private var engine: Engine? = null
    private var visionEnabled: Boolean = false  // Track if vision backend was initialized
    private val conversations = ConcurrentHashMap<String, Conversation>()
    private val conversationCounter = AtomicInteger(0)

    override suspend fun initialize(request: InitializeRequest): InitializeResponse {
        logger.info("Initializing engine with model: ${request.modelPath}")
        logger.info("Request params: enableVision=${request.enableVision}, enableAudio=${request.enableAudio}, backend=${request.backend}, maxNumImages=${request.maxNumImages}")

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

                // Match Android behavior: use same backend for main and vision
                val backend = when (request.backend.lowercase()) {
                    "gpu" -> Backend.GPU
                    else -> Backend.CPU
                }
                // Vision on macOS Desktop: GPU required by Gemma 3n model but macOS GPU accelerator
                // doesn't work (issue #1050). CPU gives "Vision backend constraint mismatch".
                // Workaround: disable vision (maxNumImages=0 from client) until Google fixes GPU on macOS.
                val visionBackend = if (request.maxNumImages > 0) backend else null
                val audioBackend = if (request.enableAudio) Backend.CPU else null

                // Use model directory as cache dir (like Android does)
                val cacheDir = modelFile.parentFile?.absolutePath

                logger.info("Creating EngineConfig: backend=$backend, visionBackend=$visionBackend, audioBackend=$audioBackend, maxTokens=${request.maxTokens}, cacheDir=$cacheDir")

                val engineConfig = EngineConfig(
                    modelPath = request.modelPath,
                    backend = backend,
                    maxNumTokens = request.maxTokens,
                    visionBackend = visionBackend,
                    audioBackend = audioBackend,
                    cacheDir = cacheDir
                )

                engine = Engine(engineConfig)
                engine!!.initialize()
                visionEnabled = visionBackend != null

                logger.info("Engine initialized successfully with visionEnabled=$visionEnabled, audioBackend=$audioBackend")

                InitializeResponse.newBuilder()
                    .setSuccess(true)
                    .setModelInfo("{\"backend\": \"${request.backend}\", \"maxTokens\": ${request.maxTokens}}")
                    .build()
            } catch (e: Exception) {
                logger.error("Failed to initialize engine: ${e.javaClass.name}: ${e.message}")
                e.printStackTrace()
                val fullError = buildString {
                    append(e.javaClass.name)
                    append(": ")
                    append(e.message ?: "Unknown error")
                    e.cause?.let { cause ->
                        append("\nCaused by: ${cause.javaClass.name}: ${cause.message}")
                    }
                }
                InitializeResponse.newBuilder()
                    .setSuccess(false)
                    .setError(fullError)
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

            logger.info("Creating conversation with config: samplerConfig=$samplerConfig")
            val conversation = engine.createConversation(conversationConfig)
            val id = "conv_${conversationCounter.incrementAndGet()}"
            conversations[id] = conversation

            logger.info("Created conversation: $id (conversation class: ${conversation.javaClass.name})")

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

    /**
     * Build Contents from components (matches Android's buildAndConsumeMessage pattern).
     * Order: Image → Audio → Text (text last for multimodal compatibility)
     */
    private fun buildContents(
        text: String,
        imageBytes: ByteArray? = null,
        audioBytes: ByteArray? = null
    ): Contents {
        val contents = mutableListOf<Content>()

        // Image first (if present)
        imageBytes?.let {
            val pngBytes = convertToPng(it)
            contents.add(Content.ImageBytes(pngBytes))
        }

        // Audio second (if present)
        audioBytes?.let {
            contents.add(Content.AudioBytes(it))
        }

        // Text last (always add if non-empty, or if no other content)
        if (text.isNotEmpty() || contents.isEmpty()) {
            contents.add(Content.Text(text))
        }

        return Contents.of(contents)
    }

    override fun chat(request: ChatRequest): Flow<ChatResponse> = callbackFlow {
        val conversation = conversations[request.conversationId]
        if (conversation == null) {
            trySend(
                ChatResponse.newBuilder()
                    .setError("Conversation not found: ${request.conversationId}")
                    .setDone(true)
                    .build()
            )
            close()
            return@callbackFlow
        }

        try {
            logger.info("=== CHAT REQUEST ===")
            logger.info("conversationId: '${request.conversationId}'")
            logger.info("text: '${request.text}' (length=${request.text.length})")
            logger.info("text bytes: ${request.text.toByteArray().take(20).map { it.toInt() and 0xFF }}")

            // Use Contents format (like Android does)
            val message = Contents.of(listOf(Content.Text(request.text)))
            logger.info("Created Contents: $message")

            // Use callback-based API (like Android does)
            conversation.sendMessageAsync(message, object : MessageCallback {
                override fun onMessage(msg: Message) {
                    trySend(
                        ChatResponse.newBuilder()
                            .setText(msg.toString())
                            .setDone(false)
                            .build()
                    )
                }

                override fun onDone() {
                    trySend(
                        ChatResponse.newBuilder()
                            .setDone(true)
                            .build()
                    )
                    close()
                    logger.debug("Chat completed for ${request.conversationId}")
                }

                override fun onError(throwable: Throwable) {
                    logger.error("Error during chat", throwable)
                    trySend(
                        ChatResponse.newBuilder()
                            .setError(throwable.message ?: "Unknown error during chat")
                            .setDone(true)
                            .build()
                    )
                    close(throwable)
                }
            })
        } catch (e: Exception) {
            logger.error("Error starting chat", e)
            trySend(
                ChatResponse.newBuilder()
                    .setError(e.message ?: "Unknown error during chat")
                    .setDone(true)
                    .build()
            )
            close(e)
        }

        awaitClose { }
    }

    override suspend fun chatWithImageSync(request: ChatWithImageRequest): ChatResponse {
        val conversation = conversations[request.conversationId]
            ?: return ChatResponse.newBuilder()
                .setError("Conversation not found: ${request.conversationId}")
                .setDone(true)
                .build()

        return try {
            val imageBytes = request.image.toByteArray()
            logger.info("ChatWithImageSync: text='${request.text.take(50)}', imageBytes=${imageBytes.size}")

            val message = buildContents(request.text, imageBytes = imageBytes)

            logger.info("Calling SYNC sendMessage...")
            val response = conversation.sendMessage(message)
            val responseText = response.toString()
            logger.info("Sync response (${responseText.length} chars): ${responseText.take(200)}")

            ChatResponse.newBuilder()
                .setText(responseText)
                .setDone(true)
                .build()
        } catch (e: Exception) {
            logger.error("Error during sync chat with image", e)
            ChatResponse.newBuilder()
                .setError(e.message ?: "Unknown error")
                .setDone(true)
                .build()
        }
    }

    override fun chatWithImage(request: ChatWithImageRequest): Flow<ChatResponse> = callbackFlow {
        val conversation = conversations[request.conversationId]
        if (conversation == null) {
            trySend(
                ChatResponse.newBuilder()
                    .setError("Conversation not found: ${request.conversationId}")
                    .setDone(true)
                    .build()
            )
            close()
            return@callbackFlow
        }

        try {
            val imageBytes = request.image.toByteArray()
            logger.info("Chat with image request: text='${request.text.take(50)}', imageBytes=${imageBytes.size}, visionEnabled=$visionEnabled")

            // If vision is not enabled, ignore image and send text only (will hallucinate but won't crash)
            // This is a workaround for Desktop where GPU vision doesn't work (LiteRT-LM issues #684, #1050)
            val message = if (visionEnabled) {
                // Log image format (first bytes indicate format: JPEG=FFD8, PNG=89504E47)
                if (imageBytes.size >= 4) {
                    val header = imageBytes.take(4).map { String.format("%02X", it) }.joinToString("")
                    logger.info("Image header: $header (JPEG=FFD8, PNG=89504E47)")
                }
                buildContents(request.text, imageBytes = imageBytes)
            } else {
                logger.warn("Vision not enabled - ignoring image, sending text only. Model will hallucinate.")
                buildContents(request.text)  // Text only, no image
            }

            logger.info("Sending message to conversation...")
            var responseCount = 0

            // Use callback-based API (like Android does)
            conversation.sendMessageAsync(message, object : MessageCallback {
                override fun onMessage(msg: Message) {
                    responseCount++
                    if (responseCount <= 3) {
                        logger.info("Response chunk $responseCount: '${msg.toString().take(100)}'")
                    }
                    trySend(
                        ChatResponse.newBuilder()
                            .setText(msg.toString())
                            .setDone(false)
                            .build()
                    )
                }

                override fun onDone() {
                    logger.info("Chat with image completed, total chunks: $responseCount")
                    trySend(
                        ChatResponse.newBuilder()
                            .setDone(true)
                            .build()
                    )
                    close()
                }

                override fun onError(throwable: Throwable) {
                    logger.error("Error during chat with image", throwable)
                    trySend(
                        ChatResponse.newBuilder()
                            .setError(throwable.message ?: "Unknown error during chat with image")
                            .setDone(true)
                            .build()
                    )
                    close(throwable)
                }
            })
        } catch (e: Exception) {
            logger.error("Error starting chat with image", e)
            trySend(
                ChatResponse.newBuilder()
                    .setError(e.message ?: "Unknown error during chat with image")
                    .setDone(true)
                    .build()
            )
            close(e)
        }

        awaitClose { }
    }

    override fun chatWithAudio(request: ChatWithAudioRequest): Flow<ChatResponse> = callbackFlow {
        val conversation = conversations[request.conversationId]
        if (conversation == null) {
            trySend(
                ChatResponse.newBuilder()
                    .setError("Conversation not found: ${request.conversationId}")
                    .setDone(true)
                    .build()
            )
            close()
            return@callbackFlow
        }

        try {
            val audioBytes = request.audio.toByteArray()
            logger.info("Chat with audio request: text='${request.text.take(50)}', audioBytes=${audioBytes.size}")

            // Log audio format info (first 44 bytes are WAV header if it's WAV)
            if (audioBytes.size >= 44) {
                val header = audioBytes.take(12).map { it.toInt() and 0xFF }
                val headerStr = audioBytes.take(4).map { it.toInt().toChar() }.joinToString("")
                logger.info("Audio header: $headerStr, first 12 bytes: $header")

                // If WAV, parse some info
                if (headerStr == "RIFF") {
                    val channels = (audioBytes[22].toInt() and 0xFF) or ((audioBytes[23].toInt() and 0xFF) shl 8)
                    val sampleRate = (audioBytes[24].toInt() and 0xFF) or
                                    ((audioBytes[25].toInt() and 0xFF) shl 8) or
                                    ((audioBytes[26].toInt() and 0xFF) shl 16) or
                                    ((audioBytes[27].toInt() and 0xFF) shl 24)
                    val bitsPerSample = (audioBytes[34].toInt() and 0xFF) or ((audioBytes[35].toInt() and 0xFF) shl 8)
                    logger.info("WAV info: sampleRate=$sampleRate, channels=$channels, bitsPerSample=$bitsPerSample")
                }
            }

            val message = buildContents(request.text, audioBytes = audioBytes)

            logger.info("Sending message to conversation...")
            var responseCount = 0

            // Use callback-based API (like Android does)
            conversation.sendMessageAsync(message, object : MessageCallback {
                override fun onMessage(msg: Message) {
                    responseCount++
                    val responseText = msg.toString()
                    if (responseCount <= 3) {
                        logger.info("Response chunk $responseCount: '${responseText.take(100)}'")
                    }
                    trySend(
                        ChatResponse.newBuilder()
                            .setText(responseText)
                            .setDone(false)
                            .build()
                    )
                }

                override fun onDone() {
                    logger.info("Chat with audio completed, total chunks: $responseCount")
                    trySend(
                        ChatResponse.newBuilder()
                            .setDone(true)
                            .build()
                    )
                    close()
                }

                override fun onError(throwable: Throwable) {
                    logger.error("Error during chat with audio", throwable)
                    trySend(
                        ChatResponse.newBuilder()
                            .setError(throwable.message ?: "Unknown error during chat with audio")
                            .setDone(true)
                            .build()
                    )
                    close(throwable)
                }
            })
        } catch (e: Exception) {
            logger.error("Error starting chat with audio", e)
            trySend(
                ChatResponse.newBuilder()
                    .setError(e.message ?: "Unknown error during chat with audio")
                    .setDone(true)
                    .build()
            )
            close(e)
        }

        awaitClose { }
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

    /**
     * Convert any image format to PNG (LiteRT-LM expects PNG like AI Edge Gallery)
     */
    private fun convertToPng(imageBytes: ByteArray): ByteArray {
        return try {
            // Check if already PNG (89 50 4E 47 = 0x89PNG)
            if (imageBytes.size >= 4 &&
                imageBytes[0] == 0x89.toByte() &&
                imageBytes[1] == 0x50.toByte() &&
                imageBytes[2] == 0x4E.toByte() &&
                imageBytes[3] == 0x47.toByte()) {
                logger.info("Image already PNG, returning as-is")
                return imageBytes
            }

            // Read image (JPEG, PNG, BMP, etc.)
            val inputStream = ByteArrayInputStream(imageBytes)
            val bufferedImage = ImageIO.read(inputStream)
            if (bufferedImage == null) {
                logger.warn("Failed to read image, returning original bytes")
                return imageBytes
            }

            logger.info("Read image: ${bufferedImage.width}x${bufferedImage.height}, type=${bufferedImage.type}")

            // Write as PNG
            val outputStream = ByteArrayOutputStream()
            ImageIO.write(bufferedImage, "PNG", outputStream)
            val pngBytes = outputStream.toByteArray()

            // Verify PNG header
            if (pngBytes.size >= 4) {
                val header = pngBytes.take(4).map { String.format("%02X", it) }.joinToString("")
                logger.info("PNG output header: $header")
            }

            pngBytes
        } catch (e: Exception) {
            logger.error("Failed to convert image to PNG: ${e.message}", e)
            imageBytes // Return original on error
        }
    }
}
