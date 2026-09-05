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

# Kotlinx coroutines — no wholesale keep, on purpose. The artifact ships its own
# R8 rules (META-INF/com.android.tools/r8/coroutines.pro) and they are complete;
# a package-wide keep here would pin ~920 classes against shrinking, which is
# what #486 reported against the plugin's consumer rules. This file is the
# app-side example people copy, so it should not teach the pattern back.
-dontwarn kotlinx.coroutines.**