// Flutter Gemma Windows Plugin
//
// This is a placeholder plugin class for Windows.
// The actual implementation is in Dart (FlutterGemmaDesktop) using gRPC
// to communicate with a Kotlin/JVM server process.

#include "flutter_gemma/flutter_gemma_plugin.h"

namespace flutter_gemma {

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
