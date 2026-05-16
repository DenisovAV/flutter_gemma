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

# Kotlinx coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# okhttp optional TLS providers — referenced reflectively, never present at
# runtime. Pre-0.15.2 these were absorbed by the wide `-dontwarn
# com.google.guava.**` rule (guava pulled okhttp transitively); 0.15.2 dropped
# guava so R8 needs the warning suppressed explicitly.
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**