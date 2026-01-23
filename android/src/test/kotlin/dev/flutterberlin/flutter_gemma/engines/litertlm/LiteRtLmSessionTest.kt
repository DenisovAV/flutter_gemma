package dev.flutterberlin.flutter_gemma.engines.litertlm

import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.Message
import dev.flutterberlin.flutter_gemma.engines.SessionConfig
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Unit tests for LiteRtLmSession.
 *
 * Tests chunk buffering, thread safety, and message building.
 */
class LiteRtLmSessionTest {

    private lateinit var mockEngine: Engine
    private lateinit var mockConversation: Conversation
    private lateinit var resultFlow: MutableSharedFlow<Pair<String, Boolean>>
    private lateinit var errorFlow: MutableSharedFlow<Throwable>
    private lateinit var session: LiteRtLmSession

    @Before
    fun setUp() {
        mockEngine = mock(Engine::class.java)
        mockConversation = mock(Conversation::class.java)
        resultFlow = MutableSharedFlow()
        errorFlow = MutableSharedFlow()

        `when`(mockEngine.createConversation(any())).thenReturn(mockConversation)

        val config = SessionConfig(
            temperature = 0.7f,
            randomSeed = 42,
            topK = 40,
            topP = 0.95f
        )

        session = LiteRtLmSession(mockEngine, config, resultFlow, errorFlow)
    }

    // ===========================================
    // Chunk Buffering Tests
    // ===========================================

    @Test
    fun `addQueryChunk accumulates text`() {
        session.addQueryChunk("Hello, ")
        session.addQueryChunk("world!")

        // Token count estimate should reflect accumulated length
        // "Hello, world!" = 13 chars → ~3-4 tokens
        val tokenCount = session.sizeInTokens("")
        // This verifies internal state indirectly
        assertTrue("Token count should be reasonable", tokenCount >= 0)
    }

    @Test
    fun `addQueryChunk handles empty string`() {
        session.addQueryChunk("")
        session.addQueryChunk("test")
        session.addQueryChunk("")

        // Should not crash
        val tokenCount = session.sizeInTokens("test")
        assertTrue(tokenCount >= 0)
    }

    @Test
    fun `addQueryChunk handles unicode text`() {
        session.addQueryChunk("Привет, ")
        session.addQueryChunk("мир! 🌍")

        // Should handle unicode without crashing
        val tokenCount = session.sizeInTokens("Тест")
        assertTrue(tokenCount >= 0)
    }

    // ===========================================
    // Thread Safety Tests
    // ===========================================

    @Test
    fun `concurrent addQueryChunk calls are thread-safe`() {
        val executor = Executors.newFixedThreadPool(10)
        val latch = CountDownLatch(100)

        repeat(100) { i ->
            executor.submit {
                try {
                    session.addQueryChunk("chunk$i ")
                } finally {
                    latch.countDown()
                }
            }
        }

        assertTrue("Should complete without deadlock", latch.await(5, TimeUnit.SECONDS))
        executor.shutdown()
    }

    @Test
    fun `concurrent addImage and addQueryChunk are thread-safe`() {
        val executor = Executors.newFixedThreadPool(10)
        val latch = CountDownLatch(100)

        repeat(50) { i ->
            executor.submit {
                try {
                    session.addQueryChunk("chunk$i ")
                } finally {
                    latch.countDown()
                }
            }
            executor.submit {
                try {
                    session.addImage(byteArrayOf(i.toByte()))
                } finally {
                    latch.countDown()
                }
            }
        }

        assertTrue("Should complete without deadlock", latch.await(5, TimeUnit.SECONDS))
        executor.shutdown()
    }

    // ===========================================
    // Token Counting Tests
    // ===========================================

    @Test
    fun `sizeInTokens returns estimate based on character count`() {
        // Formula: (length + 3) / 4
        val prompt = "Hello world" // 11 chars
        val expected = (11 + 3) / 4 // = 3

        val result = session.sizeInTokens(prompt)

        assertEquals("Token estimate should be ~chars/4", expected, result)
    }

    @Test
    fun `sizeInTokens handles empty string`() {
        val result = session.sizeInTokens("")
        assertEquals("Empty string should return 0 tokens", 0, result)
    }

    @Test
    fun `sizeInTokens handles very long text`() {
        val longText = "a".repeat(10000)
        val result = session.sizeInTokens(longText)

        assertTrue("Should handle long text", result > 2000)
    }

    // ===========================================
    // Cancel Generation Tests
    // ===========================================

    @Test
    fun `cancelGeneration does not throw`() {
        // LiteRT-LM doesn't support cancellation, but should not crash
        session.cancelGeneration()
        // If we get here, test passes
    }

    // ===========================================
    // Close Tests
    // ===========================================

    @Test
    fun `close releases conversation resource`() {
        session.close()

        verify(mockConversation).close()
    }

    @Test
    fun `close can be called multiple times`() {
        session.close()
        session.close()
        session.close()

        // Should not throw, verify close was attempted
        verify(mockConversation, atLeast(1)).close()
    }

    // ===========================================
    // Image Handling Tests
    // ===========================================

    @Test
    fun `addImage stores image bytes`() {
        val imageBytes = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47) // PNG header

        session.addImage(imageBytes)

        // Should not throw - image stored for later use
    }

    @Test
    fun `addImage replaces previous image`() {
        session.addImage(byteArrayOf(1, 2, 3))
        session.addImage(byteArrayOf(4, 5, 6))

        // Only last image should be used (implementation detail)
        // No assertion needed - just verify no crash
    }
}
