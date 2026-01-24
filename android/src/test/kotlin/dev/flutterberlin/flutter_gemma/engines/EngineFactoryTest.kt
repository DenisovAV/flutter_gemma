package dev.flutterberlin.flutter_gemma.engines

import android.content.Context
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock

/**
 * Unit tests for EngineFactory.
 *
 * Tests file extension detection and engine type selection.
 */
class EngineFactoryTest {

    private val mockContext: Context = mock(Context::class.java)

    // ===========================================
    // createFromModelPath() tests
    // ===========================================

    @Test
    fun `createFromModelPath with litertlm extension returns LiteRtLmEngine`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.litertlm", mockContext)
        assertTrue("Expected LiteRtLmEngine", engine is dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine)
    }

    @Test
    fun `createFromModelPath with LITERTLM uppercase returns LiteRtLmEngine`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.LITERTLM", mockContext)
        assertTrue("Expected LiteRtLmEngine for uppercase", engine is dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine)
    }

    @Test
    fun `createFromModelPath with task extension returns MediaPipeEngine`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.task", mockContext)
        assertTrue("Expected MediaPipeEngine", engine is dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine)
    }

    @Test
    fun `createFromModelPath with bin extension returns MediaPipeEngine`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.bin", mockContext)
        assertTrue("Expected MediaPipeEngine", engine is dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine)
    }

    @Test
    fun `createFromModelPath with tflite extension returns MediaPipeEngine`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.tflite", mockContext)
        assertTrue("Expected MediaPipeEngine", engine is dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `createFromModelPath with unknown extension throws IllegalArgumentException`() {
        EngineFactory.createFromModelPath("/path/to/model.unknown", mockContext)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `createFromModelPath with no extension throws IllegalArgumentException`() {
        EngineFactory.createFromModelPath("/path/to/model", mockContext)
    }

    // ===========================================
    // detectEngineType() tests
    // ===========================================

    @Test
    fun `detectEngineType returns LITERTLM for litertlm extension`() {
        val type = EngineFactory.detectEngineType("/path/to/model.litertlm")
        assertEquals(EngineType.LITERTLM, type)
    }

    @Test
    fun `detectEngineType returns MEDIAPIPE for task extension`() {
        val type = EngineFactory.detectEngineType("/path/to/model.task")
        assertEquals(EngineType.MEDIAPIPE, type)
    }

    @Test
    fun `detectEngineType returns MEDIAPIPE for bin extension`() {
        val type = EngineFactory.detectEngineType("/path/to/model.bin")
        assertEquals(EngineType.MEDIAPIPE, type)
    }

    @Test
    fun `detectEngineType returns MEDIAPIPE for tflite extension`() {
        val type = EngineFactory.detectEngineType("/path/to/model.tflite")
        assertEquals(EngineType.MEDIAPIPE, type)
    }

    @Test
    fun `detectEngineType is case insensitive`() {
        assertEquals(EngineType.LITERTLM, EngineFactory.detectEngineType("/model.LiteRtLm"))
        assertEquals(EngineType.MEDIAPIPE, EngineFactory.detectEngineType("/model.TASK"))
        assertEquals(EngineType.MEDIAPIPE, EngineFactory.detectEngineType("/model.BIN"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `detectEngineType throws for unknown extension`() {
        EngineFactory.detectEngineType("/path/to/model.gguf")
    }

    // ===========================================
    // create() tests
    // ===========================================

    @Test
    fun `create with MEDIAPIPE returns MediaPipeEngine`() {
        val engine = EngineFactory.create(EngineType.MEDIAPIPE, mockContext)
        assertTrue("Expected MediaPipeEngine", engine is dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine)
    }

    @Test
    fun `create with LITERTLM returns LiteRtLmEngine`() {
        val engine = EngineFactory.create(EngineType.LITERTLM, mockContext)
        assertTrue("Expected LiteRtLmEngine", engine is dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine)
    }

    // ===========================================
    // Edge cases
    // ===========================================

    @Test
    fun `createFromModelPath handles paths with multiple dots`() {
        val engine = EngineFactory.createFromModelPath("/path/to/model.v1.2.litertlm", mockContext)
        assertTrue("Expected LiteRtLmEngine", engine is dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine)
    }

    @Test
    fun `createFromModelPath handles paths with spaces`() {
        val engine = EngineFactory.createFromModelPath("/path/to/my model.task", mockContext)
        assertTrue("Expected MediaPipeEngine", engine is dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine)
    }
}
