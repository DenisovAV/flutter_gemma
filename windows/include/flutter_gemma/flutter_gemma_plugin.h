// Flutter Gemma Windows Plugin
//
// This is a placeholder plugin class for Windows.
// The actual implementation is in Dart (FlutterGemmaDesktop) using gRPC
// to communicate with a Kotlin/JVM server process.

#ifndef FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void FlutterGemmaPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#include <flutter/plugin_registrar_windows.h>

namespace flutter_gemma {

// Placeholder plugin class - actual implementation is in Dart using gRPC
class FlutterGemmaPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterGemmaPlugin();
  virtual ~FlutterGemmaPlugin();

  // Disallow copy and assign.
  FlutterGemmaPlugin(const FlutterGemmaPlugin&) = delete;
  FlutterGemmaPlugin& operator=(const FlutterGemmaPlugin&) = delete;
};

}  // namespace flutter_gemma

#endif  // FLUTTER_PLUGIN_FLUTTER_GEMMA_PLUGIN_H_
