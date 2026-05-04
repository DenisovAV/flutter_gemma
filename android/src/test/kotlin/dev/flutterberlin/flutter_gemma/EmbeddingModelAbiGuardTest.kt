package dev.flutterberlin.flutter_gemma

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [EmbeddingModel.assertArm64v8aPrimaryAbi].
 *
 * Regression tests for #250 Mode 3: x86_64 Android emulators advertise
 * arm64-v8a as a translation fallback in Build.SUPPORTED_ABIS, so the old
 * `Build.SUPPORTED_ABIS.contains("arm64-v8a")` guard was too permissive
 * and let JNI loading proceed on x86_64, where the arm64-only native lib
 * fails with [UnsatisfiedLinkError].
 */
class EmbeddingModelAbiGuardTest {

    @Test
    fun `arm64 device passes`() {
        // Real Pixel 8: SUPPORTED_ABIS=[arm64-v8a]. No throw expected.
        EmbeddingModel.assertArm64v8aPrimaryAbi(arrayOf("arm64-v8a"))
    }

    @Test
    fun `arm64 device with fallbacks passes`() {
        // Some arm64 devices expose 32-bit fallbacks. Primary still arm64-v8a.
        EmbeddingModel.assertArm64v8aPrimaryAbi(
            arrayOf("arm64-v8a", "armeabi-v7a", "armeabi")
        )
    }

    @Test
    fun `x86_64 emulator with arm64 translation fallback throws (reproduces 250 mode 3)`() {
        // Standard Android x86_64 emulator: primary ABI is x86_64 but
        // arm64-v8a sits in the list as a Houdini/translation fallback.
        // The old contains() guard let this through; firstOrNull() catches
        // it because primary != arm64-v8a.
        try {
            EmbeddingModel.assertArm64v8aPrimaryAbi(
                arrayOf("x86_64", "arm64-v8a")
            )
            throw AssertionError("expected UnsupportedOperationException")
        } catch (e: UnsupportedOperationException) {
            assertTrue(
                "error message should mention primary ABI",
                e.message!!.contains("primary ABI x86_64")
            )
        }
    }

    @Test(expected = UnsupportedOperationException::class)
    fun `x86 32-bit emulator throws`() {
        EmbeddingModel.assertArm64v8aPrimaryAbi(arrayOf("x86", "armeabi-v7a"))
    }

    @Test(expected = UnsupportedOperationException::class)
    fun `armeabi-v7a only device throws`() {
        EmbeddingModel.assertArm64v8aPrimaryAbi(arrayOf("armeabi-v7a", "armeabi"))
    }

    @Test(expected = UnsupportedOperationException::class)
    fun `empty abi list throws`() {
        EmbeddingModel.assertArm64v8aPrimaryAbi(arrayOf())
    }

    @Test
    fun `error message lists full abi list for diagnostics`() {
        try {
            EmbeddingModel.assertArm64v8aPrimaryAbi(arrayOf("x86_64", "arm64-v8a"))
            throw AssertionError("expected throw")
        } catch (e: UnsupportedOperationException) {
            assertTrue(
                "should include full list for support diagnostics",
                e.message!!.contains("full list: x86_64, arm64-v8a")
            )
        }
    }
}
