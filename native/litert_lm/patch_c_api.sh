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

# ── 6. Patch LlmExecutor base to add SetPendingSamplerParams virtual ──
# Upstream's LlmLiteRtCompiledModelExecutorBase::InitializeSampler() at
# llm_litert_compiled_model_executor.cc:1271-1276 hardcodes sampler_params
# (TOP_P, k=1, p=0, temperature=1, seed=0) ignoring SessionConfig. We add
# a new virtual on the LlmExecutor base so SessionBasic can push session-
# level sampler params into the executor BEFORE InitializeSampler runs.
#
# Defaulted to UnimplementedError so executor implementations that don't
# override (e.g. NPU executor) keep current upstream behavior — they just
# won't honor seed via this path.
EXECUTOR_BASE_HEADER="$DIR/runtime/executor/llm_executor_base.h"
if [ -f "$EXECUTOR_BASE_HEADER" ] && ! grep -q "// PATCH: SetPendingSamplerParams" "$EXECUTOR_BASE_HEADER"; then
  python3 -c "
with open('$EXECUTOR_BASE_HEADER', 'r') as f:
    content = f.read()

# Anchor: insert the new virtual right before UpdateExecutorSettings.
# UpdateExecutorSettings is the conventional 'change runtime config' verb,
# so SetPendingSamplerParams lives next to it.
import re
m = re.search(r'(  virtual absl::Status UpdateExecutorSettings\\b)', content)
if not m:
    print('  WARN: UpdateExecutorSettings not found in llm_executor_base.h; skipping section 6')
else:
    insertion = '''  // PATCH: SetPendingSamplerParams (flutter_gemma).
  // Inject session-level sampler params so InitializeSampler() honors the
  // user's seed/temperature/topK/topP instead of upstream's hardcoded
  // defaults at llm_litert_compiled_model_executor.cc:1271-1276.
  // Defaulted to UnimplementedError so executors that don't override keep
  // current behavior.
  virtual absl::Status SetPendingSamplerParams(
      const proto::SamplerParameters& sampler_params) {
    return absl::UnimplementedError(
        \"SetPendingSamplerParams not implemented for this executor.\");
  }

'''
    content = content[:m.start()] + insertion + content[m.start():]
    # Ensure the proto include is present (it's a transitive dep via the
    # sampler classes, but be explicit).
    if 'runtime/proto/sampler_params.pb.h' not in content:
        # Insert near other runtime includes.
        m2 = re.search(r'(#include \"runtime/[^\"]+\"\\n)', content)
        if m2:
            content = content[:m2.end()] + '#include \"runtime/proto/sampler_params.pb.h\"\\n' + content[m2.end():]
    with open('$EXECUTOR_BASE_HEADER', 'w') as f:
        f.write(content)
    print('  OK: Added SetPendingSamplerParams virtual to llm_executor_base.h')
"
else
  if [ -f "$EXECUTOR_BASE_HEADER" ]; then
    echo "  SKIP: llm_executor_base.h already has SetPendingSamplerParams"
  else
    echo "  WARN: $EXECUTOR_BASE_HEADER not found"
  fi
fi

# ── 7. Patch LlmLiteRtCompiledModelExecutorBase to add override + member ──
LITERT_EXECUTOR_HEADER="$DIR/runtime/executor/llm_litert_compiled_model_executor.h"
if [ -f "$LITERT_EXECUTOR_HEADER" ] && ! grep -q "// PATCH: pending_sampler_params_" "$LITERT_EXECUTOR_HEADER"; then
  python3 -c "
with open('$LITERT_EXECUTOR_HEADER', 'r') as f:
    content = f.read()

import re

# 7a: add override declaration after the existing InitializeSampler decl.
m = re.search(
    r'(  absl::Status InitializeSampler\\(\\s*std::optional<ActivationDataType>[^)]*\\)\\s*;\\s*\\n)',
    content)
if not m:
    print('  WARN: InitializeSampler decl not found; skipping section 7a')
else:
    override_decl = '''
  // PATCH: SetPendingSamplerParams (flutter_gemma).
  // See llm_executor_base.h. Stash and forward to UpdateConfig if the
  // sampler already exists (subsequent createSession on the same engine).
  absl::Status SetPendingSamplerParams(
      const proto::SamplerParameters& sampler_params) override;

'''
    content = content[:m.end()] + override_decl + content[m.end():]

# 7b: add member field after the existing sampler_ declaration.
m2 = re.search(r'(  std::unique_ptr<Sampler> sampler_;\\n)', content)
if not m2:
    print('  WARN: sampler_ field not found; skipping section 7b')
else:
    field_decl = '''
  // PATCH: pending_sampler_params_ (flutter_gemma).
  // User-supplied sampler params from SessionConfig; consumed by
  // InitializeSampler() if set, else fall back to upstream hardcoded
  // defaults. nullopt preserves behavior for callers that don't push
  // session params.
  std::optional<proto::SamplerParameters> pending_sampler_params_;
'''
    content = content[:m2.end()] + field_decl + content[m2.end():]

with open('$LITERT_EXECUTOR_HEADER', 'w') as f:
    f.write(content)
print('  OK: Added SetPendingSamplerParams + pending_sampler_params_ to litert_compiled_model_executor.h')
"
else
  if [ -f "$LITERT_EXECUTOR_HEADER" ]; then
    echo "  SKIP: litert_compiled_model_executor.h already patched"
  else
    echo "  WARN: $LITERT_EXECUTOR_HEADER not found"
  fi
fi

# ── 8. Patch InitializeSampler + add SetPendingSamplerParams definition ──
LITERT_EXECUTOR_CC="$DIR/runtime/executor/llm_litert_compiled_model_executor.cc"
if [ -f "$LITERT_EXECUTOR_CC" ] && ! grep -q "// PATCH: pending_sampler_params_ in InitializeSampler" "$LITERT_EXECUTOR_CC"; then
  python3 -c "
with open('$LITERT_EXECUTOR_CC', 'r') as f:
    content = f.read()

# 8a: replace hardcoded SamplerParameters block in InitializeSampler.
old = '''  proto::SamplerParameters sampler_params;
  sampler_params.set_type(proto::SamplerParameters::TOP_P);
  sampler_params.set_k(1);
  sampler_params.set_p(0.0f);
  sampler_params.set_temperature(1.0f);
  sampler_params.set_seed(0);
  ASSIGN_OR_RETURN(
      sampler_,
      CreateSampler(sampler_backend, output_heads, std::move(sampler_params),
                    env_.Get(), /*sequence_size=*/1, vocab_size, data_type));'''

new = '''  // PATCH: pending_sampler_params_ in InitializeSampler (flutter_gemma).
  // Consume session-supplied sampler params if present; otherwise
  // preserve upstream's hardcoded defaults so non-flutter_gemma callers
  // see no behavior change.
  proto::SamplerParameters sampler_params;
  if (pending_sampler_params_.has_value()) {
    sampler_params = *pending_sampler_params_;
    if (sampler_params.type() == proto::SamplerParameters::TYPE_UNSPECIFIED) {
      sampler_params.set_type(proto::SamplerParameters::TOP_P);
    }
    if (sampler_params.k() <= 0) sampler_params.set_k(1);
    // p == 0.0 is a legitimate \"no top-p\" choice; don\\'t backfill.
    if (sampler_params.temperature() <= 0.0f) {
      sampler_params.set_temperature(1.0f);
    }
    // seed == 0 is a legitimate user choice; don\\'t backfill.
  } else {
    sampler_params.set_type(proto::SamplerParameters::TOP_P);
    sampler_params.set_k(1);
    sampler_params.set_p(0.0f);
    sampler_params.set_temperature(1.0f);
    sampler_params.set_seed(0);
  }
  ASSIGN_OR_RETURN(
      sampler_,
      CreateSampler(sampler_backend, output_heads, std::move(sampler_params),
                    env_.Get(), /*sequence_size=*/1, vocab_size, data_type));'''

if old in content:
    content = content.replace(old, new)
    print('  OK: Patched InitializeSampler to consume pending_sampler_params_')
else:
    print('  WARN: hardcoded sampler_params block not found in cc; skipping section 8a')

# 8b: add SetPendingSamplerParams definition after UpdateExecutorSettings.
import re
m = re.search(
    r'(absl::Status LlmLiteRtCompiledModelExecutorBase::UpdateExecutorSettings\\([^)]*\\)\\s*\\{[^}]*\\}\\n)',
    content)
if not m:
    print('  WARN: UpdateExecutorSettings impl not found; skipping section 8b')
else:
    setter_def = '''
// PATCH: SetPendingSamplerParams (flutter_gemma).
absl::Status LlmLiteRtCompiledModelExecutorBase::SetPendingSamplerParams(
    const proto::SamplerParameters& sampler_params) {
  pending_sampler_params_ = sampler_params;
  // Always drop the cached sampler so the next InitializeSampler() call
  // recreates it with our pending_sampler_params_. We can't rely on
  // Sampler::UpdateConfig() because:
  //   - top_p_cpu_sampler.cc:168 ignores sampler_params.seed() — only k/p/
  //     temperature are mutated; the std::default_random_engine is left
  //     as-is, so the same input seed across two calls produces different
  //     outputs (RNG state accumulates).
  //   - GPU C-API sampler libs (Metal #1990) ship without the UpdateConfig
  //     export at all on some platforms.
  // Recreate-on-set is the only reliable way to honor a fresh seed.
  sampler_.reset();
  return absl::OkStatus();
}
'''
    content = content[:m.end()] + setter_def + content[m.end():]
    print('  OK: Added SetPendingSamplerParams definition to litert_compiled_model_executor.cc')

with open('$LITERT_EXECUTOR_CC', 'w') as f:
    f.write(content)
"
else
  if [ -f "$LITERT_EXECUTOR_CC" ]; then
    echo "  SKIP: litert_compiled_model_executor.cc already patched"
  else
    echo "  WARN: $LITERT_EXECUTOR_CC not found"
  fi
fi

# ── 9. Patch SessionBasic::Create to push sampler params on GPU/NPU path ──
SESSION_BASIC_CC="$DIR/runtime/core/session_basic.cc"
if [ -f "$SESSION_BASIC_CC" ] && ! grep -q "// PATCH: push sampler params on GPU/NPU" "$SESSION_BASIC_CC"; then
  python3 -c "
with open('$SESSION_BASIC_CC', 'r') as f:
    content = f.read()

# Find the existing GPU/NPU else-if branch and replace it.
old = '''  } else if (sampler_backend != Backend::GPU &&
             sampler_backend != Backend::NPU) {
    return absl::InvalidArgumentError(
        absl::StrCat(\"Unsupported sampler backend: \", sampler_backend));
  }'''

new = '''  } else if (sampler_backend == Backend::GPU ||
             sampler_backend == Backend::NPU) {
    // PATCH: push sampler params on GPU/NPU (flutter_gemma).
    // Push session-level sampler params into the executor so its
    // InitializeSampler() consumes user's seed/temperature/topK/topP
    // instead of hardcoded defaults. Best-effort: NPU executor returns
    // Unimplemented and we ignore it (preserves upstream behavior).
    auto status = executor->SetPendingSamplerParams(
        session_config.GetSamplerParams());
    if (!status.ok() && status.code() != absl::StatusCode::kUnimplemented) {
      return status;
    }
  } else {
    return absl::InvalidArgumentError(
        absl::StrCat(\"Unsupported sampler backend: \", sampler_backend));
  }'''

if old in content:
    content = content.replace(old, new)
    with open('$SESSION_BASIC_CC', 'w') as f:
        f.write(content)
    print('  OK: Patched SessionBasic::Create to push sampler params on GPU/NPU')
else:
    print('  WARN: existing GPU/NPU else-if branch not found in session_basic.cc; skipping section 9')
"
else
  if [ -f "$SESSION_BASIC_CC" ]; then
    echo "  SKIP: session_basic.cc already patched"
  else
    echo "  WARN: $SESSION_BASIC_CC not found"
  fi
fi

# ── 10. Patch sampler_factory.cc + WORKSPACE for App-Store-safe dlopen on Apple ──
#
# `gpu_registry.cc` (LiteRT) and `sampler_factory.cc` (LiteRT-LM) hardcode the
# dylib basename "libLiteRtMetalAccelerator.dylib" / "libLiteRtTopKMetalSampler.dylib"
# in their dlopen calls. Native Assets bundles each prebuilt dylib as
# `<X>.framework/<X>` (Apple's required structure for iOS) — there is no flat
# `lib<X>.dylib` file in the app bundle for dyld to find by basename.
#
# Older flutter_gemma versions worked around this by symlinking lib*.dylib
# alongside the frameworks in `Frameworks/`, but Apple App Store Connect
# rejects that with ITMS-90432 ("Unexpected file found in Frameworks").
#
# Proper fix: rewrite the dlopen path on Apple to a relative-to-executable
# framework path, which dyld resolves natively:
#   `@executable_path/../Frameworks/<X>.framework/<X>` on macOS
#   `@executable_path/Frameworks/<X>.framework/<X>` on iOS
#
# Verified empirically (2026-04-30) on a built macOS Runner.app: the
# @executable_path-relative form resolves both from a binary in Contents/MacOS
# and from a binary inside another framework's Versions/A — i.e. it works for
# gpu_registry's call site inside libLiteRtLm.dylib.

# 10a. sampler_factory.cc — DELIBERATELY NOT PATCHED.
#
# Patching the Metal sampler dlopen to find the framework binary exposes a
# different bug: the bundled libLiteRtTopKMetalSampler.dylib only exports 3
# of the 7 C ABI functions sampler_factory expects (upstream issue #2073).
# When dlopen succeeds, GetSamplerCApi() does dlsym for UpdateConfig which
# returns NULL — and a later virtual call through the half-built sampler
# vtable dereferences uninitialized memory, crashing the app with
# EXC_BAD_ACCESS deep inside the inference pipeline (observed on iPhone
# 16 Pro device with Gemma 4 E2B GPU temperature=0.0 test 2026-04-30).
#
# Leaving the original "libLiteRtTopKMetalSampler.dylib" basename means
# dlopen on Apple cannot resolve it (Native Assets bundles a framework, not
# a flat .dylib), so sampler_factory.cc falls back to the CPU sampling
# path — same behavior we had pre-0.14.1. Inference still runs on the GPU
# accelerator; only the per-token argmax happens on CPU (~1-5 ms/token).
#
# When upstream ships a 7/7 export sampler dylib, revisit this patch.

# 10b. gpu_registry.cc lives in LiteRT (transitive dep). Bazel applies
# patch_cmds AFTER extracting an http_archive — that's the canonical hook for
# patching transitive deps. Use python with a separator to avoid the multi-
# layer shell-inside-Bazel-string-inside-python quoting nightmare.
export WORKSPACE_FILE="$DIR/WORKSPACE"
if [ -f "$WORKSPACE_FILE" ] && ! grep -q "FLUTTER_GEMMA_GPU_REGISTRY_PATCH" "$WORKSPACE_FILE"; then
  python3 << 'PYEOF'
import os
ws = os.environ['WORKSPACE_FILE']
with open(ws, 'r') as f:
    content = f.read()

# The existing third_party-rewrite line is the anchor. Use a stable substring
# match (the file path is unique enough).
anchor_substring = 'third_party/*/*",'
new_line_after_anchor = """
        # FLUTTER_GEMMA_GPU_REGISTRY_PATCH — App Store ITMS-90432 fix:
        # rewrite gpu_registry.cc dlopen path on Apple to a framework path so
        # dyld resolves the bundled .framework/<X> via @executable_path. iOS
        # bundle is flat (Frameworks/), macOS bundle has Contents/Frameworks/.
        "sed -i.bak 's|\\"libLiteRtMetalAccelerator\\" SO_EXT|FLUTTER_GEMMA_METAL_FW_PATH|g' litert/runtime/accelerators/gpu_registry.cc",
        # Inject the macro definition AFTER the namespace opens (i.e. after
        # the SO_EXT block has fully closed, since SO_EXT is defined before
        # the namespace block). The TargetConditionals.h include must be
        # wrapped in #if defined(__APPLE__) — that header is Apple-only,
        # Android NDK doesn't ship it. Using awk to avoid sed nesting issues.
        "awk 'BEGIN{p=0} /^namespace litert::internal/ && !p {print; print \\"\\"; print \\"#if defined(__APPLE__)\\"; print \\"#include <TargetConditionals.h>\\"; print \\"#if TARGET_OS_OSX\\"; print \\"#define FLUTTER_GEMMA_METAL_FW_PATH \\\\\\"@executable_path/../Frameworks/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator\\\\\\"\\"; print \\"#elif TARGET_OS_IPHONE\\"; print \\"#define FLUTTER_GEMMA_METAL_FW_PATH \\\\\\"@executable_path/Frameworks/LiteRtMetalAccelerator.framework/LiteRtMetalAccelerator\\\\\\"\\"; print \\"#else\\"; print \\"#define FLUTTER_GEMMA_METAL_FW_PATH \\\\\\"libLiteRtMetalAccelerator.dylib\\\\\\"\\"; print \\"#endif\\"; print \\"#else\\"; print \\"#define FLUTTER_GEMMA_METAL_FW_PATH \\\\\\"libLiteRtMetalAccelerator\\\\\\" SO_EXT\\"; print \\"#endif\\"; p=1; next} {print}' litert/runtime/accelerators/gpu_registry.cc > /tmp/gpu_registry.cc.new && mv /tmp/gpu_registry.cc.new litert/runtime/accelerators/gpu_registry.cc","""

# Find the anchor line and insert our new lines right after it.
idx = content.find(anchor_substring)
if idx < 0:
    print("  WARN: anchor line not found in WORKSPACE; skipping section 10b")
else:
    # End-of-line for the anchor
    eol = content.find('\n', idx)
    if eol < 0:
        eol = len(content)
    content = content[:eol] + new_line_after_anchor + content[eol:]
    with open(ws, 'w') as f:
        f.write(content)
    print("  OK: Patched WORKSPACE litert.patch_cmds with gpu_registry.cc dlopen rewrite")
PYEOF
else
  if [ -f "$WORKSPACE_FILE" ]; then
    echo "  SKIP: WORKSPACE already has FLUTTER_GEMMA_GPU_REGISTRY_PATCH"
  else
    echo "  WARN: $WORKSPACE_FILE not found"
  fi
fi

echo "Patch complete."
