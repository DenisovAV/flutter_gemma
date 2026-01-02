// Flutter Gemma Windows Plugin
//
// This is a placeholder plugin class for Windows.
// The actual implementation is in Dart (FlutterGemmaDesktop) using gRPC
// to communicate with a Kotlin/JVM server process.

#include <flutter/plugin_registrar_windows.h>

namespace flutter_gemma {

// Placeholder plugin class - actual implementation is in Dart
class FlutterGemmaPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterGemmaPlugin();
  virtual ~FlutterGemmaPlugin();

  // Disallow copy and assign.
  FlutterGemmaPlugin(const FlutterGemmaPlugin&) = delete;
  FlutterGemmaPlugin& operator=(const FlutterGemmaPlugin&) = delete;
};

// static
void FlutterGemmaPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  // No-op: Desktop implementation is pure Dart using gRPC
  // This class exists only for CMake/plugin registration compatibility
}

FlutterGemmaPlugin::FlutterGemmaPlugin() {}

FlutterGemmaPlugin::~FlutterGemmaPlugin() {}

}  // namespace flutter_gemma

void FlutterGemmaPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_gemma::FlutterGemmaPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
