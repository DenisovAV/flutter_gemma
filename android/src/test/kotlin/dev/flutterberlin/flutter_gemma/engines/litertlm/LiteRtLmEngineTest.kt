package dev.flutterberlin.flutter_gemma.engines.litertlm

import android.content.Context
import dev.flutterberlin.flutter_gemma.PreferredBackend
import dev.flutterberlin.flutter_gemma.engines.EngineConfig
import dev.flutterberlin.flutter_gemma.engines.SessionConfig
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.mockito.Mockito.*
import java.io.File

/**
 * Unit tests for LiteRtLmEngine.
 *
 * Tests initialization, backend mapping, and lifecycle management.
 */
class LiteRtLmEngineTest {

    private lateinit var mockContext: Context
    private lateinit var engine: LiteRtLmEngine
    private lateinit var tempCacheDir: File

    @Before
    fun setUp() {
        mockContext = mock(Context::class.java)
        tempCacheDir = File(System.getProperty("java.io.tmpdir"), "test_cache")
        tempCacheDir.mkdirs()

        `when`(mockContext.cacheDir).thenReturn(tempCacheDir)

        engine = LiteRtLmEngine(mockContext)
    }

    // ===========================================
    // Initialization Tests
    // ===========================================

    @Test
    fun `isInitialized is false before initialize`() {
        assertFalse("Engine should not be initialized", engine.isInitialized)
    }

    @Test
    fun `initialize with non-existent file throws IllegalArgumentException`() {
        val config = EngineConfig(
            modelPath = "/non/existent/path/model.litertlm",
            maxTokens = 1024
        )

        runBlocking {
            try {
                engine.initialize(config)
                fail("Should throw for non-existent file")
            } catch (e: IllegalArgumentException) {
                assertTrue(e.message?.contains("not found") == true)
            }
        }
    }

    // ===========================================
    // Capabilities Tests
    // ===========================================

    @Test
    fun `capabilities reports vision support`() {
        assertTrue("Should support vision", engine.capabilities.supportsVision)
    }

    @Test
    fun `capabilities reports audio support`() {
        assertTrue("Should support audio", engine.capabilities.supportsAudio)
    }

    @Test
    fun `capabilities reports function calls support`() {
        assertTrue("Should support function calls", engine.capabilities.supportsFunctionCalls)
    }

    @Test
    fun `capabilities reports streaming support`() {
        assertTrue("Should support streaming", engine.capabilities.supportsStreaming)
    }

    @Test
    fun `capabilities reports no token counting support`() {
        assertFalse("Should not support token counting", engine.capabilities.supportsTokenCounting)
    }

    @Test
    fun `capabilities has 4096 max token limit`() {
        assertEquals(4096, engine.capabilities.maxTokenLimit)
    }

    // ===========================================
    // Session Creation Tests
    // ===========================================

    @Test
    fun `createSession before initialize throws IllegalStateException`() {
        val config = SessionConfig(temperature = 0.7f)

        try {
            engine.createSession(config)
            fail("Should throw IllegalStateException")
        } catch (e: IllegalStateException) {
            assertTrue(e.message?.contains("not initialized") == true)
        }
    }

    // ===========================================
    // Close Tests
    // ===========================================

    @Test
    fun `close sets isInitialized to false`() {
        // Even if not initialized, close should work
        engine.close()
        assertFalse("Should not be initialized after close", engine.isInitialized)
    }

    @Test
    fun `close can be called multiple times safely`() {
        engine.close()
        engine.close()
        engine.close()

        // Should not throw
        assertFalse(engine.isInitialized)
    }

    // ===========================================
    // Flow Tests
    // ===========================================

    @Test
    fun `partialResults flow is accessible`() {
        assertNotNull("partialResults should not be null", engine.partialResults)
    }

    @Test
    fun `errors flow is accessible`() {
        assertNotNull("errors should not be null", engine.errors)
    }

    // ===========================================
    // Backend Mapping Tests (via EngineConfig)
    // ===========================================

    @Test
    fun `config with GPU backend is accepted`() {
        val config = EngineConfig(
            modelPath = "/test/model.litertlm",
            maxTokens = 1024,
            preferredBackend = PreferredBackend.GPU
        )

        // Config creation should not throw
        assertNotNull(config)
        assertEquals(PreferredBackend.GPU, config.preferredBackend)
    }

    @Test
    fun `config with CPU backend is accepted`() {
        val config = EngineConfig(
            modelPath = "/test/model.litertlm",
            maxTokens = 1024,
            preferredBackend = PreferredBackend.CPU
        )

        assertEquals(PreferredBackend.CPU, config.preferredBackend)
    }

    @Test
    fun `config with NPU backend is accepted`() {
        val config = EngineConfig(
            modelPath = "/test/model.litertlm",
            maxTokens = 1024,
            preferredBackend = PreferredBackend.NPU
        )

        assertEquals(PreferredBackend.NPU, config.preferredBackend)
    }

    @Test
    fun `config with null backend defaults correctly`() {
        val config = EngineConfig(
            modelPath = "/test/model.litertlm",
            maxTokens = 1024,
            preferredBackend = null
        )

        assertNull(config.preferredBackend)
    }
}
