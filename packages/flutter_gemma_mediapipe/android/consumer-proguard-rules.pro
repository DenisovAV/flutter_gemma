# MediaPipe and protobuf
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class com.google.mediapipe.tasks.genai.llminference.LlmInference { *; }

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Classes MediaPipe references but does not ship. Without these R8 fails the
# app's release build with "Missing class" (measured with AGP 9.1).
-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
