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
# On Linux, use --dynamic-list (Google's own pattern from
# runtime/engine/litert_lm_main.exported_symbols) to extend the dynamic
# export set with LiteRt*/litert_lm_* while keeping internal symbols
# visible — the WebGPU accelerator plugin needs to resolve LiteRt* C API
# via dlsym(RTLD_DEFAULT) during auto-registration.
#
# Requires building with --define=litert_link_capi_so=true so that
# libLiteRtLm.so references libLiteRt.so dynamically at runtime instead
# of statically linking the LiteRt C API (which would create two copies
# of TFLite in the process alongside the prebuilt accelerator).
if ! grep -q "linkshared" "$DIR/c/BUILD"; then
  # Dynamic-list: make these symbols visible in the dynamic export table.
  cat > "$DIR/c/dynamic_list.lds" << 'LDSEOF'
{
  LiteRt*;
  litert_lm_*;
};
LDSEOF

  # Windows .def: whitelist of symbols to export from LiteRtLm.dll.
  # Derived from lib/core/ffi/litert_lm_bindings.dart lookupFunction calls.
  cat > "$DIR/c/windows_exports.def" << 'DEFEOF'
LIBRARY "LiteRtLm"
EXPORTS
  litert_lm_benchmark_info_delete
  litert_lm_benchmark_info_get_decode_token_count_at
  litert_lm_benchmark_info_get_decode_tokens_per_sec_at
  litert_lm_benchmark_info_get_num_decode_turns
  litert_lm_benchmark_info_get_num_prefill_turns
  litert_lm_benchmark_info_get_prefill_token_count_at
  litert_lm_benchmark_info_get_prefill_tokens_per_sec_at
  litert_lm_benchmark_info_get_time_to_first_token
  litert_lm_benchmark_info_get_total_init_time_in_second
  litert_lm_conversation_cancel_process
  litert_lm_conversation_config_create
  litert_lm_conversation_config_delete
  litert_lm_conversation_create
  litert_lm_conversation_delete
  litert_lm_conversation_get_benchmark_info
  litert_lm_conversation_send_message
  litert_lm_conversation_send_message_stream
  litert_lm_engine_create
  litert_lm_engine_create_session
  litert_lm_engine_delete
  litert_lm_engine_settings_create
  litert_lm_engine_settings_delete
  litert_lm_engine_settings_enable_benchmark
  litert_lm_engine_settings_set_activation_data_type
  litert_lm_engine_settings_set_cache_dir
  litert_lm_engine_settings_set_max_num_images
  litert_lm_engine_settings_set_max_num_tokens
  litert_lm_engine_settings_set_num_decode_tokens
  litert_lm_engine_settings_set_num_prefill_tokens
  litert_lm_engine_settings_set_parallel_file_section_loading
  litert_lm_engine_settings_set_prefill_chunk_size
  litert_lm_json_response_delete
  litert_lm_json_response_get_string
  litert_lm_responses_delete
  litert_lm_responses_get_num_candidates
  litert_lm_responses_get_response_text_at
  litert_lm_session_config_create
  litert_lm_session_config_delete
  litert_lm_session_config_set_max_output_tokens
  litert_lm_session_config_set_sampler_params
  litert_lm_session_delete
  litert_lm_session_generate_content
  litert_lm_session_generate_content_stream
  litert_lm_session_get_benchmark_info
  litert_lm_set_min_log_level
DEFEOF

  cat >> "$DIR/c/BUILD" << 'BUILDEOF'

cc_binary(
    name = "libLiteRtLm.dylib",
    linkshared = True,
    # Pass .def file via win_def_file (Bazel native Windows attribute) —
    # linkopts /DEF: doesn't work because bazel's MSVC link.exe action
    # already owns the linker invocation and will clobber stray /DEF flags.
    win_def_file = "windows_exports.def",
    linkopts = select({
        "@platforms//os:macos": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:ios": ["-Wl,-exported_symbol,_LiteRt*", "-Wl,-exported_symbol,_litert_lm_*"],
        "@platforms//os:linux": [
            "-Wl,--dynamic-list=$(location :dynamic_list.lds)",
        ],
        "//conditions:default": [],
    }),
    additional_linker_inputs = select({
        "@platforms//os:linux": [":dynamic_list.lds"],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
    deps = [":engine"],
)

exports_files(["dynamic_list.lds", "windows_exports.def"])
BUILDEOF
  echo "  OK: Added cc_binary(linkshared=True) to c/BUILD with Linux dynamic-list + Windows .def"
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

# ── 4. Add set_litert_dispatch_lib_dir for accelerator plugin discovery ──
# On iOS the gpu_registry dlopens accelerator dylibs by relative basename,
# which dyld 4 cannot resolve in a sandboxed app. Expose SetLitertDispatchLibDir
# so callers (Dart FFI) can pass the absolute Frameworks directory.
if ! grep -q "set_litert_dispatch_lib_dir" "$DIR/c/engine.h"; then
  sed -i.bak '/Creates a LiteRT LM Engine from the given settings/i\
// Sets the directory where LiteRT dispatch libraries (e.g. accelerator\
// plugins like libLiteRtMetalAccelerator.dylib) are located. On iOS this\
// must be set to the absolute path of the app bundle Frameworks directory\
// because dyld cannot resolve plugin libraries by basename in app sandboxes.\
LITERT_LM_C_API_EXPORT\
void litert_lm_engine_settings_set_litert_dispatch_lib_dir(\
    LiteRtLmEngineSettings* settings, const char* lib_dir);\
' "$DIR/c/engine.h"
  rm -f "$DIR/c/engine.h.bak"
  echo "  OK: Added set_litert_dispatch_lib_dir to c/engine.h"
else
  echo "  SKIP: c/engine.h already has set_litert_dispatch_lib_dir"
fi

if ! grep -q "set_litert_dispatch_lib_dir" "$DIR/c/engine.cc"; then
  sed -i.bak '/void litert_lm_engine_settings_set_activation_data_type/i\
void litert_lm_engine_settings_set_litert_dispatch_lib_dir(\
    LiteRtLmEngineSettings* settings, const char* lib_dir) {\
  if (settings \&\& settings->settings \&\& lib_dir) {\
    settings->settings->GetMutableMainExecutorSettings().SetLitertDispatchLibDir(\
        lib_dir);\
    if (settings->settings->GetVisionExecutorSettings().has_value()) {\
      settings->settings->GetMutableVisionExecutorSettings()->SetLitertDispatchLibDir(lib_dir);\
    }\
    if (settings->settings->GetAudioExecutorSettings().has_value()) {\
      settings->settings->GetMutableAudioExecutorSettings()->SetLitertDispatchLibDir(lib_dir);\
    }\
  }\
}\
' "$DIR/c/engine.cc"
  rm -f "$DIR/c/engine.cc.bak"
  echo "  OK: Added set_litert_dispatch_lib_dir impl to c/engine.cc"
else
  echo "  SKIP: c/engine.cc already has set_litert_dispatch_lib_dir"
fi

# ── 5. Patch litert_lm_conversation_config_create to 6-arg signature ──
# Upstream 5e0d86b ships the new no-args + setter pattern:
#   create() -> set_session_config -> set_system_message -> set_tools -> ...
# but our Dart bindings.dart and patched engine.h declare a 6-arg monolithic
# overload because it pre-dates the upstream split. The mismatch was silent:
# our 6-arg call ABI-compatibly resolved to the 0-arg create() (extra args
# discarded), so session_config + sampler params were always lost — every
# inference ran with model defaults.
#
# Fix: rewrite upstream's no-args create() to be the 6-arg version we
# need. Internally apply each non-null arg through the existing setter
# functions. This keeps bindings.dart unchanged.
if ! grep -q "// PATCH: 6-arg overload" "$DIR/c/engine.cc"; then
  python3 -c "
with open('$DIR/c/engine.cc', 'r') as f:
    content = f.read()

old = '''LiteRtLmConversationConfig* litert_lm_conversation_config_create() {
  return new LiteRtLmConversationConfig;
}'''

new = '''LiteRtLmConversationConfig* litert_lm_conversation_config_create(
    LiteRtLmEngine* engine, const LiteRtLmSessionConfig* session_config,
    const char* system_message_json, const char* tools_json,
    const char* messages_json, bool enable_constrained_decoding) {
  // PATCH: 6-arg overload of upstream's no-args create() — keeps our
  // Dart bindings.dart in sync with the existing C++ setter functions.
  // engine pointer is currently unused (kept in signature for symmetry
  // with upstream proposed monolithic API).
  (void)engine;
  auto* config = new LiteRtLmConversationConfig;
  if (session_config && session_config->config) {
    config->session_config = *session_config->config;
  }
  if (system_message_json) {
    config->system_message_json = system_message_json;
  }
  if (tools_json) {
    config->tools_json = tools_json;
  }
  if (messages_json) {
    config->messages_json = messages_json;
  }
  config->enable_constrained_decoding = enable_constrained_decoding;
  return config;
}'''

if old in content:
    content = content.replace(old, new)
    with open('$DIR/c/engine.cc', 'w') as f:
        f.write(content)
    print('  OK: Patched litert_lm_conversation_config_create to 6-arg overload')
else:
    print('  SKIP: config_create already patched or different format')
"
else
  echo "  SKIP: c/engine.cc already has 6-arg config_create patch"
fi

# Also patch the upstream header to expose the 6-arg signature so
# downstream Bazel users (and our generated bindings) match the impl.
if grep -q "LiteRtLmConversationConfig\* litert_lm_conversation_config_create();" "$DIR/c/engine.h"; then
  python3 -c "
with open('$DIR/c/engine.h', 'r') as f:
    content = f.read()

old = 'LiteRtLmConversationConfig* litert_lm_conversation_config_create();'
new = '''LiteRtLmConversationConfig* litert_lm_conversation_config_create(
    LiteRtLmEngine* engine, const LiteRtLmSessionConfig* session_config,
    const char* system_message_json, const char* tools_json,
    const char* messages_json, bool enable_constrained_decoding);'''
if old in content:
    content = content.replace(old, new)
    with open('$DIR/c/engine.h', 'w') as f:
        f.write(content)
    print('  OK: Patched c/engine.h declaration to 6-arg signature')
"
fi

echo "Patch complete."
