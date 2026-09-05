---
title: Desktop Support
description: Setup and reference for running flutter_gemma on macOS, Windows, and Linux via dart:ffi.
image: https://fluttergemma.dev/images/og-image.png
---

Detailed setup and reference for running flutter_gemma on **macOS, Windows, and
Linux**. Desktop platforms run LiteRT-LM **directly via `dart:ffi`** — no
Kotlin/JVM gRPC server, no Java required, no separate process, no IPC overhead.
Engine startup is ~2 s instead of ~10–15 s.

LiteRT-LM (`.litertlm`) is the **primary, default** desktop engine — but not the
only one. **`flutter_gemma_onnx`** ([ONNX Runtime](/docs/onnx) — ORT-GenAI
generation + ORT embeddings) also runs on all three desktop OSes
(macOS/Windows/Linux), and on **macOS** the OS built-in model is available through
**`flutter_gemma_builtin_ai`** ([Apple Foundation Models](/docs/builtin-ai),
macOS only — not Windows/Linux). What holds across all of desktop is the narrower
statement: **there is no MediaPipe engine on desktop.** See
[Installation](/docs/installation) and [Packages](/docs/packages).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flutter Desktop App                     │
│                                                      │
│   ┌──────────────────────────────────────────────┐ │
│   │  FlutterGemmaDesktop (lib/desktop/)           │ │
│   │           ↓                                    │ │
│   │  LiteRtLmFfiClient                            │ │
│   │  (flutter_gemma_litertlm/lib/src/ffi/)        │ │
│   │           ↓ dart:ffi                           │ │
│   │  ───────────────────────────────────           │ │
│   │  libLiteRtLm.{dylib,dll,so}                    │ │
│   │  + libLiteRt.{dylib,dll,so}                    │ │
│   │  + libLiteRtMetalAccelerator.dylib (macOS)     │ │
│   │  + libLiteRtWebGpuAccelerator.{dll,so}         │ │
│   │  + libwebgpu_dawn.{dll,so} (Linux/Windows GPU) │ │
│   │  + dxil.dll + dxcompiler.dll (Windows GPU)     │ │
│   └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

**Native libraries** are fetched at build time by the package's `hook/build.dart`
from the GitHub release, SHA256-verified, and bundled by Flutter
[Native Assets](https://docs.flutter.dev/development/platform-integration/c-interop)
into the application bundle. The Dart FFI layer is shared with mobile — Android
and iOS use the same `LiteRtLmFfiClient` against the same C API. Only the dynamic
library loading sequence differs per platform.

<Warning>
**Model format (LiteRT-LM engine):** the LiteRT-LM engine on desktop accepts only
`.litertlm` files. MediaPipe `.bin` / `.task` models used on web won't load on
desktop. See the [AI Edge Model Garden](https://ai.google.dev/edge/litert/models)
for compatible models. (The [ONNX engine](/docs/onnx) uses its own `.onnx` model
directories instead.)
</Warning>

## Supported platforms

| Platform | Architecture | GPU backend | Vision | Audio | Notes |
|---|---|---|---|---|---|
| macOS | arm64 (Apple Silicon) | Metal | ✅ | ✅ | Vision verified on Gemma 4 + Gemma 3n (text decoder on Metal, vision encoder on CPU) |
| macOS | x86_64 | — | — | — | Not supported (Apple Silicon only) |
| Windows | x86_64 | DirectX 12 (via Dawn/WebGPU) | ✅ | ✅ | Requires VS 2019+ runtime (`vcredist`) for DXC |
| Windows | arm64 | — | — | — | Not supported |
| Linux | x86_64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | glibc ≥ 2.34 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| Linux | arm64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | Same glibc requirement |

<Warning>
**Fixed in litertlm 1.4.0.** On litertlm 1.2.0–1.3.1, Windows **discrete GPUs**
crash on `PreferredBackend.gpu`. Upgrade to 1.4.0; on the affected versions use
`PreferredBackend.cpu` or `.npu`. macOS/Linux GPU and Windows CPU/NPU were
never affected.
</Warning>

<Info>
**Windows NPU.** `PreferredBackend.npu` on Windows requires **Intel
LunarLake/PantherLake** silicon — the Windows native archive ships
`LiteRtDispatch.dll` + the OpenVino runtime + TBB to drive it. On any other
Windows hardware the NPU backend is unavailable; use `PreferredBackend.gpu` or
`.cpu`.
</Info>

## Requirements

- **Flutter** ≥ 3.44.0
- **macOS**: Apple Silicon (arm64)
- **Windows**: 10/11 64-bit, [Microsoft Visual C++ Redistributable 2019+](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- **Linux**: glibc ≥ 2.34, libstdc++ ≥ 6.0.30 (Ubuntu 22.04+, Debian 12+, Fedora 36+, RHEL 9+)
- **GPU drivers**: any vendor driver with WebGPU/Vulkan/Metal/DX12 support; falls back to CPU if not available

No Java/JVM/JRE required.

## Quick Start

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

Future<void> chat() async {
  // Install model (downloads on first run, cached after).
  await FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  ).fromNetwork(
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    token: 'hf_...',
  ).install();

  // Create model with full capabilities — keep it for the app's lifetime.
  final model = await FlutterGemma.getActiveModel(
    maxTokens: 4096,
    preferredBackend: PreferredBackend.gpu,
    supportImage: true,
    supportAudio: true,
  );

  // Each chat / conversation is a session. Sessions are cheap to create
  // and destroy; the engine is reused across them.
  final session = await model.createSession(temperature: 0.8, topK: 1);
  await session.addQueryChunk(Message(text: 'Hi!', isUser: true));
  await for (final chunk in session.getResponseAsync()) {
    print(chunk);
  }
  await session.close();
}
```

For the high-level chat API with history + thinking + tool calling, use
`model.createChat(...)` and `chat.generateChatResponseAsync()`.

## Platform-specific setup

### macOS

Native libs are fetched and bundled automatically via Native Assets. The **only
manual step** is adding a `post_install` block to your app's `macos/Podfile` so
the upstream companion dylibs get wrapped into `.framework` bundles (and
re-signed) inside `Contents/Frameworks/`, and `LiteRtLm.dylib`'s `LC_LOAD_DYLIB`
reference is re-pointed at the new framework path (LiteRT-LM's `gpu_registry`
resolves the Metal accelerator through that framework). Without it,
`engine_create` returns null on `PreferredBackend.gpu` and the model silently
falls back to CPU.

Paste this into your `macos/Podfile` (replacing any existing `post_install`
block) and run `pod install`:

```
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  # flutter_gemma: stage the upstream Apple companion dylibs into the built
  # .app. `hook/build.dart` deliberately skips them from Native Assets on macOS
  # (#247 — Google ships them without `-Wl,-headerpad_max_install_names`, so the
  # JIT bundling path cannot rewrite their install_name), which leaves this
  # build phase to stage them.
  #
  # The phase only LOCATES and RUNS a script; the staging logic itself lives in
  # flutter_gemma_litertlm and is delivered next to the dylibs it stages. That
  # is deliberate: this block is frozen into your Xcode project, and a copy of
  # the logic frozen there cannot be fixed by upgrading the package.
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_targets.each do |user_target|
      phase_name = '[flutter_gemma] Setup LiteRT-LM macOS'

      # Only the app target embeds the Frameworks/ this phase patches.
      # RunnerTests inherits Runner's framework search paths and has no
      # Contents/Frameworks of its own — having the phase there creates a
      # cross-target dependency on Runner's framework output that Xcode reports
      # as "Cycle inside Flutter Assemble" (#300). Remove any stale copy from
      # non-app targets and skip them.
      unless user_target.name == 'Runner'
        user_target.build_phases
          .select { |p| p.respond_to?(:name) && p.name == phase_name }
          .each { |p| user_target.build_phases.delete(p) }
        next
      end

      existing = user_target.shell_script_build_phases.find { |p| p.name == phase_name }
      phase = existing || user_target.new_shell_script_build_phase(phase_name)
      # The embedded LiteRtLm binary is an INPUT so the phase re-runs whenever
      # Flutter's always-out-of-date `embed` phase re-copies the raw, unpatched
      # binary over the patched one. Without it Xcode caches the phase after the
      # first build and the second incremental build ships an unpatched
      # LiteRtLm that fails dlopen at runtime (#368).
      phase.input_paths = [
        '$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Frameworks/LiteRtLm.framework/Versions/A/LiteRtLm',
      ]
      # A declared output lets Xcode order the phase in its dependency graph
      # instead of treating it as "runs every build with no outputs" — the other
      # half of the cycle warning (#300). The script touches this file.
      phase.output_paths = ['$(DERIVED_FILE_DIR)/flutter_gemma_litertlm_macos.stamp']
      phase.shell_script = <<~SHELL
        set -e
        STAGER="${HOME}/Library/Caches/flutter_gemma/native/macos_arm64/stage_macos_companions.sh"
        if [ ! -f "${STAGER}" ]; then
          echo "[flutter_gemma] ERROR: ${STAGER} not found." >&2
          echo "  flutter_gemma_litertlm 1.6.2+ installs it there from its build hook." >&2
          echo "  Upgrade the package, then: flutter clean && flutter pub get" >&2
          exit 1
        fi
        sh "${STAGER}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
        mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
        touch "${SCRIPT_OUTPUT_FILE_0}"
      SHELL
    end
  end
end
```

**Entitlements** required for the LLM to load weights and run inference. Add to
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.app-sandbox</key>
<true/>
```

For large models (≥1 GB) you may also want
`com.apple.developer.kernel.extended-virtual-addressing` and
`com.apple.developer.kernel.increased-memory-limit`.

### Windows

`flutter_gemma_litertlm` bundles every required DLL — no manual setup. The bundle
includes:

- `LiteRtLm.dll`, `LiteRt.dll`, `libGemmaModelConstraintProvider.dll`
- `libLiteRtWebGpuAccelerator.dll`, `libLiteRtTopKWebGpuSampler.dll`
- `webgpu_dawn.dll` (Dawn WebGPU backend — split into a shared lib in LiteRT-LM v0.14.0; the accelerator DLL imports it, so GPU fails without it)
- `dxil.dll` + `dxcompiler.dll` (DirectX Shader Compiler runtime — required for WebGPU/DX12 shader compilation; from [microsoft/DirectXShaderCompiler v1.9.2602](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2602))

`StreamProxy.dll` exposes a `LoadLibraryExA(LOAD_WITH_ALTERED_SEARCH_PATH)` helper
that the plugin uses to pre-load `libLiteRt.dll`, `libLiteRtWebGpuAccelerator.dll`,
and `libLiteRtTopKWebGpuSampler.dll` before opening `LiteRtLm.dll`. Without this,
modern Windows DLL search order doesn't always include the application directory
for secondary `LoadLibrary` calls — they would fail to find the GPU accelerator
DLL and silently fall back to CPU.

End-users need the **Microsoft Visual C++ Redistributable 2019+** (LLM DLLs depend
on `vcruntime140.dll`/`msvcp140.dll`). Most modern Windows 10/11 systems already
have it.

### Linux

The bundle includes:

- `libLiteRtLm.so`, `libLiteRt.so`, `libGemmaModelConstraintProvider.so`
- `libLiteRtWebGpuAccelerator.so`, `libLiteRtTopKWebGpuSampler.so`, `libStreamProxy.so`
- `libwebgpu_dawn.so` (Dawn WebGPU backend — split into a shared lib in LiteRT-LM v0.14.0; the accelerator loads it via `$ORIGIN` rpath, so GPU fails without it)

`libStreamProxy.so` exposes `stream_proxy_load_global` (an `RTLD_GLOBAL`
`dlopen`). The plugin uses it to pre-load `libLiteRt.so` before `libLiteRtLm.so`
so the WebGPU accelerator's runtime `dlsym(RTLD_DEFAULT, "LiteRt*")` resolves —
without `RTLD_GLOBAL`, Dart's default `RTLD_LOCAL` would hide the symbols.

Build dependencies:

```
sudo apt install clang cmake ninja-build libgtk-3-dev lld
```

Linux GPU uses Dawn/WebGPU on top of Vulkan, so you need a working vendor Vulkan
driver. On NVIDIA install the proprietary driver; on Intel/AMD the open-source
Mesa driver works on most distros.

```
sudo apt install vulkan-tools libvulkan1
# Plus your vendor driver, e.g. NVIDIA:
sudo apt install nvidia-driver-535-server
```

<Warning>
Mesa's `llvmpipe` software fallback caps `maxStorageBufferRange` at 128 MB, which
is below Gemma 4's per-buffer requirement — Gemma 4 will not run on `llvmpipe`.
Install a vendor driver before running on GPU. For headless / server-side use,
`Xvfb` is enough as a fake display surrogate.
</Warning>

## Model lifecycle

### One model, many sessions

The recommended (and only well-supported) pattern:

```dart
// At app startup, ONCE:
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,
  supportImage: true,
  supportAudio: true,
);

// During app runtime, MANY TIMES:
final session = await model.createSession(...);
// ... chat, generate, etc.
await session.close();   // cheap

// At app shutdown:
await model.close();
```

Sessions are cheap to create/destroy. The expensive part is `engine_create`
(2–10 s depending on backend and model size), which happens once when the model is
first opened.

### Why not "one model per chat"?

Upstream LiteRT-LM keeps `LiteRtEnvironment` as a **process singleton** for GPU
paths. Once the env is initialized with the first model's settings (`cache_dir`,
backend, capabilities), those become process-fixed. Recreating the engine with
different settings causes GPU-stack conflicts (notably `wgpu::Instance already set`
from the WebGpu sampler binary on Linux/Windows).

The plugin avoids this by reusing the same `InferenceModel` when params match, and
by disabling GPU sampler preload on Linux (CPU-sampler fallback) so runtime model
swap works. To swap models at runtime, call `model.close()` first, then
`getActiveModel(...)` again. Switching backend (CPU ↔ GPU) works the same way.

## Known limitations

### Windows discrete GPU crashes (litertlm 1.2.0–1.3.1) — fixed in 1.4.0

Windows **discrete GPUs** crash on `PreferredBackend.gpu` in litertlm
1.2.0–1.3.1. The Windows native build passed a Bazel define that upstream had
removed, so it silently linked the LiteRt runtime statically — which conflicts
with the separately shipped WebGPU accelerator once Dawn was split out into its
own library. The define was corrected in 1.4.0 and Windows GPU works again.

On 1.2.0–1.3.1 use `PreferredBackend.cpu` or `.npu`. macOS/Linux GPU and
Windows CPU/NPU were never affected.

### Per-token sampler runs on CPU on all desktop platforms

When `preferredBackend: PreferredBackend.gpu`, the **forward pass** (prefill +
decode) runs on the GPU accelerator (Metal, DX12, Vulkan). The **per-token
sampler** (top-k / top-p / argmax) runs on CPU — roughly 1–5 ms per token vs. the
full LLM generation, which is dominated by the forward pass. The **vision
encoder** likewise runs on CPU by default (the GPU delegate can't prepare its
ops); override per-encoder with `preferredVisionBackend:` / `preferredAudioBackend:`
on `getActiveModel(...)`.

- **macOS, Windows** — upstream `libLiteRtTopKMetalSampler` / `libLiteRtTopKWebGpuSampler` ship with incomplete C ABI exports (3 of 7 functions); the factory falls back to the CPU chain. ([#1990](https://github.com/google-ai-edge/LiteRT-LM/issues/1990), [#2073](https://github.com/google-ai-edge/LiteRT-LM/issues/2073))
- **Linux** — the prebuilt sampler `.so` holds a process-static `wgpu::Instance` that any second `engine_create` rejects. Since runtime model swap matters more than the few ms saved, the plugin doesn't preload it and lets the factory fall back to CPU.

### `randomSeed` / `temperature` / `topK` / `topP` — only the first session's values apply

<Warning>
**Only the first generation on an engine sets the sampler.** Every later session
on that same engine keeps those values, whatever it asks for. Upstream defect
([LiteRT-LM #2080](https://github.com/google-ai-edge/LiteRT-LM/issues/2080),
open), reproducing on v0.14.0, v0.15.0 and v0.16.0, on CPU as well as GPU.
</Warning>

`topK` defaults to `1`, which is greedy — so the common shape is: an app loads a
model, runs one generation with defaults, and from then on the engine is locked
greedy. A later `temperature: 1.5` changes nothing, with no error and no warning.
It runs the other way too: an engine whose first session is stochastic keeps
sampling, and a later `topK: 1` will not give you argmax. The seed is not
re-applied either — the sampler keeps its RNG state across sessions, so two
identical requests on one engine produce different text.

**Workaround:** close and recreate the engine when you need different sampler
settings — `model.close()` then `FlutterGemma.getActiveModel(...)` — at the cost
of a model reload. If your app uses one fixed configuration throughout, as most
chat apps do, this never surfaces: the first session already set the values you
wanted.

Before litertlm 1.2.0 we carried a build-time patch that fixed this downstream
(offered upstream as [PR #2081](https://github.com/google-ai-edge/LiteRT-LM/pull/2081)).
v0.14.0 added a native session-config sampler API and the patch was dropped, but
the underlying baking was never fixed.

### Audio modality requires LiteRT-LM models

Audio input only works with `.litertlm` models that include the audio adapter
(Gemma 3n E2B/E4B, Gemma 4 E2B/E4B). See [Multimodal](/docs/multimodal).

### iOS Simulator: GPU disabled

iOS Simulator's Metal has a 256 MB single-allocation cap that LLM weight tensors
exceed. Use CPU on the simulator, or test on a physical iPhone for GPU validation.

## Troubleshooting

### Engine create fails with no native log on Linux

In **debug builds** the plugin redirects native stderr to
`<tmpdir>/litertlm_native.log` and dumps it via `debugPrint` after a failed
`engine_create`. In release builds stderr goes to the systemd journal / app's own
stderr.

### `glibc 2.38 not found` on Linux

You're hitting a stale local binary. Clear it and let `hook/build.dart` re-fetch
the correct glibc-2.34 binary:

```
rm -rf native/litert_lm/prebuilt/linux_x86_64/
flutter clean && flutter run
```

### Windows GPU shaders fail to compile

Symptom: `engine_create` returns null with no Dart-side error, app silently falls
back to CPU. Verify `dxcompiler.dll` and `dxil.dll` are next to your `app.exe`
(Native Assets bundles them). If present but still failing, check the user has the
VS 2019+ Visual C++ Runtime.

<Warning>
On a Windows **discrete GPU** with litertlm 1.2.0–1.3.1, GPU also crashes for a
separate reason — a Bazel define we passed had been removed upstream, so the
runtime linked statically. Fixed in 1.4.0. See
[Known limitations](#known-limitations).
</Warning>

### Model file not found

On desktop the model is downloaded to the platform's standard "app support"
directory (see [Troubleshooting → desktop storage](/docs/troubleshooting)). Use
`FlutterGemma.installModel(...).fromNetwork(...).install()` to download, or
`.fromFile(absolutePath)` if you already have it locally.

### Pre-cached engine + new code = stale cache

LiteRT-LM caches compiled GPU shaders next to the model file
(`<model>.litertlm_<random>_mldrift_program_cache.bin`). After upgrading the
plugin or the model, delete that file and the engine rebuilds the cache on first
run.
