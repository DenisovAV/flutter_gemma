// Flutter Gemma Linux Plugin
//
// This is a placeholder plugin class for Linux.
// The actual implementation is in Dart (FlutterGemmaDesktop) using gRPC
// to communicate with a Kotlin/JVM server process.

#include "include/flutter_gemma/flutter_gemma_plugin.h"

#include <flutter_linux/flutter_linux.h>

// Placeholder - no actual native implementation needed
// Dart plugin class (FlutterGemmaDesktop) handles everything via gRPC

extern "C" __attribute__((visibility("default")))
void flutter_gemma_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  // No-op: Desktop implementation is pure Dart using gRPC
  // This function exists only for plugin registration compatibility
}
