# MediaPipe and protobuf
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class com.google.mediapipe.tasks.genai.llminference.LlmInference { *; }

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# RAG functionality
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**

# LiteRT-LM engine (for .litertlm models)
-keep class com.google.ai.edge.litertlm.** { *; }
-keepclassmembers class com.google.ai.edge.litertlm.** { *; }
-dontwarn com.google.ai.edge.litertlm.**

# Guava (used by RAG)
-keep class com.google.guava.** { *; }
-dontwarn com.google.guava.**
-keep class com.google.common.** { *; }
-dontwarn com.google.common.**

# Kotlinx coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# AutoValue and annotation processing
-keep class javax.lang.model.** { *; }
-dontwarn javax.lang.model.**
-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

# JavaPoet (used by AutoValue)
-keep class autovalue.shaded.com.squareup.javapoet.** { *; }
-dontwarn autovalue.shaded.com.squareup.javapoet.**