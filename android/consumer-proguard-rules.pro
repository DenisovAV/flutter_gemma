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