# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core (for deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# MediaPipe - keep everything
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# MediaPipe specific proto classes that might be missing in tasks-genai
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto*
-dontwarn com.google.mediapipe.proto.GraphTemplateProto*

# Protocol Buffers - keep everything
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# RAG functionality
-keep class com.google.ai.edge.localagents.** { *; }
-dontwarn com.google.ai.edge.localagents.**

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