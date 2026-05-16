# MediaPipe and protobuf
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class com.google.mediapipe.tasks.genai.llminference.LlmInference { *; }

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Kotlinx coroutines (used by .litertlm FFI dispatch)
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# okhttp optional TLS providers — referenced reflectively, never present at
# runtime. Pre-0.15.2 these were absorbed by the wide `-dontwarn
# com.google.guava.**` rule (guava pulled okhttp transitively via
# localagents-rag); 0.15.2 dropped that dep so R8 release builds need the
# warning suppressed explicitly.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**