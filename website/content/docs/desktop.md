---
title: Desktop Support
description: Setup and reference for running flutter_gemma on macOS, Windows, and Linux via dart:ffi.
image: https://fluttergemma.dev/images/og-image.png
---

Detailed setup and reference for running flutter_gemma on **macOS, Windows, and
Linux**. Desktop platforms run LiteRT-LM **directly via `dart:ffi`** — no
Kotlin/JVM gRPC server, no Java required, no separate process, no IPC overhead.
Engine startup is ~2 s instead of ~10–15 s.

Desktop is served exclusively by the **`flutter_gemma_litertlm`** package; see
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
**Model format:** desktop accepts only LiteRT-LM `.litertlm` files. MediaPipe
`.bin` / `.task` models used on web won't load on desktop. See the
[AI Edge Model Garden](https://ai.google.dev/edge/litert/models) for compatible
models.
</Warning>

## Supported platforms

| Platform | Architecture | GPU backend | Vision | Audio | Notes |
|---|---|---|---|---|---|
| macOS | arm64 (Apple Silicon) | Metal | ✅ | ✅ | Vision verified on Gemma 4 + Gemma 3n via Metal |
| macOS | x86_64 | — | — | — | Not supported (Apple Silicon only) |
| Windows | x86_64 | DirectX 12 (via Dawn/WebGPU) | ✅ | ✅ | Requires VS 2019+ runtime (`vcredist`) for DXC |
| Windows | arm64 | — | — | — | Not supported |
| Linux | x86_64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | glibc ≥ 2.34 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| Linux | arm64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | Same glibc requirement |

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
the bundled companion `.framework`s get matching `lib*.dylib` symlinks
(LiteRT-LM's `gpu_registry` calls `dlopen("libLiteRtMetalAccelerator.dylib")` by
basename and won't find a bare framework binary on its own). Without it,
`engine_create` returns null on `PreferredBackend.gpu` and the model silently
falls back to CPU.

Paste this into your `macos/Podfile` (replacing any existing `post_install`
block) and run `pod install`:

```
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_macos_build_settings(target)
  end

  # flutter_gemma: bundle Apple accelerator dylibs as .framework bundles into
  # Contents/Frameworks/ and re-point LiteRtLm.dylib's LC_LOAD_DYLIB reference.
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.user_targets.each do |user_target|
      phase_name = '[flutter_gemma] Setup LiteRT-LM macOS'

      # Only the app target embeds the Frameworks/ this phase patches.
      unless user_target.name == 'Runner'
        user_target.build_phases
          .select { |p| p.respond_to?(:name) && p.name == phase_name }
          .each { |p| user_target.build_phases.delete(p) }
        next
      end

      existing = user_target.shell_script_build_phases.find { |p| p.name == phase_name }
      phase = existing || user_target.new_shell_script_build_phase(phase_name)
      phase.output_paths = ['$(DERIVED_FILE_DIR)/flutter_gemma_litertlm_macos.stamp']
      phase.shell_script = <<~SHELL
        set -e
        FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
        if [ ! -d "${FRAMEWORKS}" ]; then
          exit 0
        fi
        for base in LiteRtMetalAccelerator LiteRtTopKMetalSampler GemmaModelConstraintProvider; do
          rm -f "${FRAMEWORKS}/lib${base}.dylib"
        done
        # Resolve dylib source — Native Assets cache (pub.dev), then path-dep fallbacks.
        for candidate in \
            "${HOME}/Library/Caches/flutter_gemma/native/macos_arm64" \
            "${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_gemma/native/litert_lm/prebuilt/macos_arm64" \
            "${SRCROOT}/../../native/litert_lm/prebuilt/macos_arm64"; do
          if [ -f "${candidate}/libGemmaModelConstraintProvider.dylib" ]; then
            PLUGIN_PREBUILT="${candidate}"
            break
          fi
        done
        if [ -z "${PLUGIN_PREBUILT:-}" ]; then
          echo "[flutter_gemma] ERROR: macOS companion dylibs not found. Run 'flutter clean && flutter pub get'."
          exit 1
        fi
        for base in GemmaModelConstraintProvider LiteRtMetalAccelerator LiteRtTopKMetalSampler; do
          src="${PLUGIN_PREBUILT}/lib${base}.dylib"
          if [ ! -f "${src}" ]; then
            echo "[flutter_gemma] WARNING: ${src} not found — runtime dlopen will fail"
            continue
          fi
          fw_dir="${FRAMEWORKS}/${base}.framework"
          mkdir -p "${fw_dir}/Versions/A/Resources"
          cp "${src}" "${fw_dir}/Versions/A/${base}"
          install_name_tool -id "@rpath/${base}.framework/Versions/A/${base}" \\
            "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
          (cd "${fw_dir}" && ln -sfh A Versions/Current && ln -sfh "Versions/Current/${base}" "${base}" && ln -sfh "Versions/Current/Resources" Resources)
          cat > "${fw_dir}/Versions/A/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${base}</string>
  <key>CFBundleIdentifier</key><string>dev.flutterberlin.flutter_gemma.${base}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
</dict>
</plist>
EOF
          # Re-sign the framework binary: install_name_tool invalidated its
          # code signature, and unlike LiteRtLm these companion frameworks are
          # not re-signed by Xcode — an unsigned/modified page trips CODESIGNING
          # "Invalid Page" at dlopen. Ad-hoc sign like LiteRtLm below.
          codesign --force --sign - "${fw_dir}/Versions/A/${base}" 2>/dev/null || true
        done
        LITERTLM="${FRAMEWORKS}/LiteRtLm.framework/Versions/A/LiteRtLm"
        if [ -f "${LITERTLM}" ]; then
          install_name_tool -change \\
            @rpath/libGemmaModelConstraintProvider.dylib \\
            @rpath/GemmaModelConstraintProvider.framework/Versions/A/GemmaModelConstraintProvider \\
            "${LITERTLM}" 2>/dev/null || true
          codesign --force --sign - "${LITERTLM}" 2>/dev/null || true
        fi
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

### Per-token sampler runs on CPU on all desktop platforms

When `preferredBackend: PreferredBackend.gpu`, the **forward pass** (prefill +
decode) runs on the GPU accelerator (Metal, DX12, Vulkan). The **per-token
sampler** (top-k / top-p / argmax) runs on CPU — roughly 1–5 ms per token vs. the
full LLM generation, which is dominated by the forward pass.

- **macOS, Windows** — upstream `libLiteRtTopKMetalSampler` / `libLiteRtTopKWebGpuSampler` ship with incomplete C ABI exports (3 of 7 functions); the factory falls back to the CPU chain. ([#1990](https://github.com/google-ai-edge/LiteRT-LM/issues/1990), [#2073](https://github.com/google-ai-edge/LiteRT-LM/issues/2073))
- **Linux** — the prebuilt sampler `.so` holds a process-static `wgpu::Instance` that any second `engine_create` rejects. Since runtime model swap matters more than the few ms saved, the plugin doesn't preload it and lets the factory fall back to CPU.

### `randomSeed` / `temperature` / `topK` / `topP` on GPU

Sampler params are honored on CPU and GPU on all platforms that ship the patched
`libLiteRtLm` build (macOS, iOS, Linux, Windows, Android). This required a
two-layer downstream patch to upstream LiteRT-LM applied at build time (offered
upstream as [#2080](https://github.com/google-ai-edge/LiteRT-LM/issues/2080) /
[PR #2081](https://github.com/google-ai-edge/LiteRT-LM/pull/2081)).

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
