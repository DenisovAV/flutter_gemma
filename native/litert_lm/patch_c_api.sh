#!/bin/bash
# Patch LiteRT-LM C API source to add:
# 1. cc_binary(linkshared=True) target for shared library
# 2. litert_lm_engine_settings_set_max_num_images function
# 3. set_cache_dir propagation to vision/audio executors
#
# Usage: patch_c_api.sh <litert_lm_dir>
# Example: patch_c_api.sh /tmp/LiteRT-LM

set -euo pipefail

DIR="${1:?Usage: patch_c_api.sh <litert_lm_dir>}"

echo "Patching LiteRT-LM C API in $DIR..."

# ── 1. Add shared library target to c/BUILD ──
# On Linux, use a version script to hide all non-public symbols (same as
# macOS -exported_symbol whitelist). Without this, libLiteRtLm.so exports
# ~31k symbols including TFLite internals, and the Google-prebuilt
# libLiteRtWebGpuAccelerator.so resolves tflite::Subgraph::* via
# dlsym(RTLD_DEFAULT) against our exports instead of its own embedded
# copy — causing ABI mismatch and segfault in ModifyGraphWithDelegate.
if ! grep -q "linkshared" "$DIR/c/BUILD"; then
  # Version script: whitelist public C API, hide everything else
  cat > "$DIR/c/symbols.lds" << 'LDSEOF'
{
  global:
    LiteRt*;
    litert_lm_*;
  local:
    *;
};
LDSEOF

  cat >> "$DIR/c/BUILD" << 'BUILDEOF'

cc_binary(
    name = "libLiteRtLm.dylib",
    linkshared = True,
    linkopts = select({
        "@platforms//os:macos": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:ios": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:linux": [
            "-Wl,--version-script=$(location :symbols.lds)",
            "-Wl,--exclude-libs,ALL",
        ],
        "//conditions:default": [],
    }),
    additional_linker_inputs = select({
        "@platforms//os:linux": [":symbols.lds"],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
    deps = [":engine"],
)

exports_files(["symbols.lds"])
BUILDEOF
  echo "  OK: Added cc_binary(linkshared=True) to c/BUILD with Linux version script"
else
  echo "  SKIP: c/BUILD already has shared lib target"
fi

# ── 2. Add set_max_num_images to c/engine.h ──
if ! grep -q "set_max_num_images" "$DIR/c/engine.h"; then
  # Insert before "Creates a LiteRT LM Engine from the given settings"
  sed -i.bak '/Creates a LiteRT LM Engine from the given settings/i\
// Sets the maximum number of images for multimodal vision support.\
// Required for models with vision capabilities (e.g. Gemma 4, Gemma 3n).\
LITERT_LM_C_API_EXPORT\
void litert_lm_engine_settings_set_max_num_images(\
    LiteRtLmEngineSettings* settings, int max_num_images);\
' "$DIR/c/engine.h"
  rm -f "$DIR/c/engine.h.bak"
  echo "  OK: Added set_max_num_images to c/engine.h"
else
  echo "  SKIP: c/engine.h already has set_max_num_images"
fi

# ── 3. Add set_max_num_images impl + patch set_cache_dir in c/engine.cc ──
if ! grep -q "set_max_num_images" "$DIR/c/engine.cc"; then
  # Add set_max_num_images before set_activation_data_type
  sed -i.bak '/void litert_lm_engine_settings_set_activation_data_type/i\
void litert_lm_engine_settings_set_max_num_images(\
    LiteRtLmEngineSettings* settings, int max_num_images) {\
  if (settings \&\& settings->settings) {\
    settings->settings->GetMutableMainExecutorSettings().SetMaxNumImages(\
        max_num_images);\
  }\
}\
' "$DIR/c/engine.cc"
  rm -f "$DIR/c/engine.cc.bak"
  echo "  OK: Added set_max_num_images impl to c/engine.cc"
else
  echo "  SKIP: c/engine.cc already has set_max_num_images"
fi

# Patch set_cache_dir to also set on vision/audio executors
if ! grep -q "GetMutableVisionExecutorSettings.*SetCacheDir" "$DIR/c/engine.cc"; then
  python3 -c "
import sys
with open('$DIR/c/engine.cc', 'r') as f:
    content = f.read()

old = '''void litert_lm_engine_settings_set_cache_dir(LiteRtLmEngineSettings* settings,
                                             const char* cache_dir) {
  if (settings && settings->settings) {
    settings->settings->GetMutableMainExecutorSettings().SetCacheDir(cache_dir);
  }
}'''

new = '''void litert_lm_engine_settings_set_cache_dir(LiteRtLmEngineSettings* settings,
                                             const char* cache_dir) {
  if (settings && settings->settings) {
    settings->settings->GetMutableMainExecutorSettings().SetCacheDir(cache_dir);
    if (settings->settings->GetVisionExecutorSettings().has_value()) {
      settings->settings->GetMutableVisionExecutorSettings()->SetCacheDir(cache_dir);
    }
    if (settings->settings->GetAudioExecutorSettings().has_value()) {
      settings->settings->GetMutableAudioExecutorSettings()->SetCacheDir(cache_dir);
    }
  }
}'''

if old in content:
    content = content.replace(old, new)
    with open('$DIR/c/engine.cc', 'w') as f:
        f.write(content)
    print('  OK: Patched set_cache_dir to propagate to vision/audio executors')
else:
    print('  SKIP: set_cache_dir already patched or different format')
"
else
  echo "  SKIP: set_cache_dir already propagates to vision/audio"
fi

echo "Patch complete."
