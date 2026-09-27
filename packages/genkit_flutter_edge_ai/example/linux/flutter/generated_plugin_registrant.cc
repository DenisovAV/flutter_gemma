//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_edge_ai/flutter_gemma_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) flutter_edge_ai_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FlutterGemmaPlugin");
  flutter_gemma_plugin_register_with_registrar(flutter_edge_ai_registrar);
}
