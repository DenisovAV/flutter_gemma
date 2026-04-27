# Flutter Gemma Desktop Support

Detailed setup and reference for running Flutter Gemma on **macOS, Windows, and Linux**.

> **0.14.0 architecture**: desktop platforms now run LiteRT-LM **directly via `dart:ffi`**. The previous Kotlin/JVM gRPC server (`litertlm-server.jar` + Azul Zulu JRE) is gone — no Java required, no separate process, no IPC overhead. Engine startup is ~2 s instead of ~10–15 s.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Supported Platforms](#supported-platforms)
3. [Requirements](#requirements)
4. [Quick Start](#quick-start)
5. [Platform-Specific Setup](#platform-specific-setup)
6. [Model Lifecycle](#model-lifecycle)
7. [Known Limitations](#known-limitations)
8. [Troubleshooting](#troubleshooting)

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flutter Desktop App                     │
│                                                      │
│   ┌──────────────────────────────────────────────┐ │
│   │  FlutterGemmaDesktop (lib/desktop/)           │ │
│   │           ↓                                    │ │
│   │  LiteRtLmFfiClient (lib/core/ffi/)            │ │
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

**Native libraries** are fetched at build time by `hook/build.dart` from the
GitHub release `native-v0.10.2`, SHA256-verified, and bundled by Flutter
[Native Assets](https://docs.flutter.dev/development/platform-integration/c-interop)
into the application bundle. There is nothing for end-users to install
manually.

The Dart FFI layer is shared with mobile — Android and iOS use the same
`LiteRtLmFfiClient` against the same C API. Only the dynamic library
loading sequence differs per platform (handled in `litert_lm_client.dart`).

> **⚠️ Model format**
>
> Desktop accepts only LiteRT-LM `.litertlm` files. MediaPipe `.bin` / `.task`
> models used on web won't load on desktop. See
> [AI Edge Model Garden](https://ai.google.dev/edge/litert/models) for compatible models.

---

## Supported Platforms

| Platform | Architecture | GPU backend | Vision | Audio | Notes |
|----------|--------------|-------------|--------|-------|-------|
| macOS | arm64 (Apple Silicon) | Metal | ⚠️ | ✅ | Vision broken upstream (#684 — model hallucinates) |
| macOS | x86_64 | — | — | — | Not supported (Apple Silicon only) |
| Windows | x86_64 | DirectX 12 (via Dawn/WebGPU) | ✅ | ✅ | Requires VS 2019+ runtime (`vcredist`) for DXC |
| Windows | arm64 | — | — | — | Not supported |
| Linux | x86_64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | glibc ≥ 2.34 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| Linux | arm64 | Vulkan (via Dawn/WebGPU) | ✅ | ✅ | Same glibc requirement |

For mobile platforms see the main [README](README.md).

---

## Requirements

- **Flutter** ≥ 3.24.0
- **Dart SDK** ≥ 3.6.0
- **macOS**: 10.14+, Apple Silicon (arm64)
- **Windows**: 10/11 64-bit, [Microsoft Visual C++ Redistributable 2019+](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- **Linux**: glibc ≥ 2.34, libstdc++ ≥ 6.0.30 (Ubuntu 22.04+, Debian 12+, Fedora 36+, RHEL 9+)
- **GPU drivers**: any vendor driver with WebGPU/Vulkan/Metal/DX12 support; falls back to CPU if not available

No Java/JVM/JRE required.

---

## Quick Start

```yaml
# pubspec.yaml
dependencies:
  flutter_gemma: ^0.14.0
```

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';

Future<void> chat() async {
  await FlutterGemma.initialize();

  // Install model (downloads on first run, cached after).
  await FlutterGemma.installModel(
    modelType: ModelType.gemmaIt,
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
`model.createChat(...)` and `chat.generateChatResponseAsync()`. See
[`example/`](example/) for a complete app.

---

## Platform-Specific Setup

### macOS

`flutter_gemma` ships everything via Native Assets — no manual setup needed.

**Entitlements** required for the LLM to load weights and run inference:

`example/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.app-sandbox</key>
<true/>
```

If your app needs to download models from network at runtime, add
`com.apple.security.network.client`. Otherwise app-sandbox alone is enough.

For large models (≥1 GB) you may want
[`com.apple.developer.kernel.extended-virtual-addressing`](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_kernel_extended-virtual-addressing)
and `com.apple.developer.kernel.increased-memory-limit`.

### Windows

`flutter_gemma` bundles every required DLL — no manual setup. The bundle
includes:

- `LiteRtLm.dll`, `LiteRt.dll`, `libGemmaModelConstraintProvider.dll`
- `libLiteRtWebGpuAccelerator.dll`, `libLiteRtTopKWebGpuSampler.dll`
- `dxil.dll` + `dxcompiler.dll` (DirectX Shader Compiler runtime — required for WebGPU/DX12 shader compilation; sourced from
  [microsoft/DirectXShaderCompiler v1.9.2602](https://github.com/microsoft/DirectXShaderCompiler/releases/tag/v1.9.2602))

`StreamProxy.dll` exposes a `LoadLibraryExA(LOAD_WITH_ALTERED_SEARCH_PATH)`
helper that the plugin uses to pre-load `libLiteRt.dll`, `libLiteRtWebGpuAccelerator.dll`,
and `libLiteRtTopKWebGpuSampler.dll` before opening `LiteRtLm.dll`. Without
this, modern Windows DLL search order doesn't always include the application
directory for secondary `LoadLibrary` calls made by `gpu_registry.cc` /
`sampler_factory.cc` at runtime — they would fail to find the GPU accelerator
DLL and silently fall back to CPU. (Mirrors the Linux `RTLD_GLOBAL` pattern.)

Make sure your end-users have the **Microsoft Visual C++ Redistributable 2019+**
installed; LLM DLLs depend on its `vcruntime140.dll`/`msvcp140.dll`. Most modern
Windows 10/11 systems already have it; for distribution see
[the official redistributable download](https://aka.ms/vs/17/release/vc_redist.x64.exe).

### Linux

The bundle includes:

- `libLiteRtLm.so`, `libLiteRt.so`, `libGemmaModelConstraintProvider.so`
- `libLiteRtWebGpuAccelerator.so`, `libLiteRtTopKWebGpuSampler.so`, `libStreamProxy.so`

`libStreamProxy.so` is a tiny helper that exposes `stream_proxy_load_global`
(an `RTLD_GLOBAL` `dlopen`). The plugin uses it to pre-load `libLiteRt.so`
before `libLiteRtLm.so` so the WebGPU accelerator's runtime
`dlsym(RTLD_DEFAULT, "LiteRt*")` resolves — without `RTLD_GLOBAL` Dart's
default `RTLD_LOCAL` would hide the symbols. The Windows variant of the
same helper (`StreamProxy.dll` → `LoadLibraryExA`) plays the equivalent
role on Windows; macOS dyld auto-resolves by basename so no helper is
needed there.

Linux GPU uses Dawn/WebGPU on top of Vulkan, so you need a working Vulkan
driver. On NVIDIA install the proprietary driver; on Intel/AMD the open-source
Mesa driver works out of the box on most distros.

For headless / server-side use (no display), `Xvfb` is enough as a fake
display surrogate — Flutter Linux integration tests run that way.

---

## Model Lifecycle

This applies to all desktop platforms; understanding it avoids the most
common runtime issues.

### One model, many sessions

The recommended (and only well-supported) pattern is:

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
(2–10 s depending on backend and model size), which happens once when the
model is first opened.

### Why not "one model per chat"?

Upstream LiteRT-LM keeps `LiteRtEnvironment` as a **process singleton** for
GPU paths (see comment in `runtime/core/engine_impl.cc` referencing `b/454383477`).
Once the env is initialized with the first model's settings — `cache_dir`,
backend, capabilities — those become process-fixed. Trying to recreate the
engine with different settings results in conflicts in the GPU stack
(notably a `wgpu::Instance already set` from the WebGpu sampler binary on
Linux/Windows).

Since 0.14.0 the plugin avoids this by:

1. Reusing the same `InferenceModel` whenever requested params match (built-in singleton in `FlutterGemmaDesktop.createModel`).
2. Disabling GPU sampler preload on Linux so the upstream sampler factory falls back to a CPU sampler — eliminates the `wgpu::Instance` conflict and re-enables runtime model swap on Linux GPU.

If you do need to swap models at runtime, call `model.close()` first, then
`getActiveModel(...)` again with the new active model's spec. On Linux, this
works thanks to the CPU-sampler fallback above; on macOS / Windows it works
because their per-token sampling already runs on CPU (see Known Limitations
below).

### Switching backend (CPU ↔ GPU)

Same as switching model — close, then reopen with the new `preferredBackend`.

---

## Known Limitations

### Per-token sampler runs on CPU on all desktop platforms

When `preferredBackend: PreferredBackend.gpu`, the **forward pass** (prefill +
decode) runs on the GPU accelerator (Metal, DX12, Vulkan). The **per-token
sampler** (top-k / top-p / argmax) runs on CPU. Cost is roughly 1–5 ms per
token vs. full LLM generation, which is dominated by the forward pass.

Why this is the case:

- **macOS, Windows** — upstream `libLiteRtTopKMetalSampler` /
  `libLiteRtTopKWebGpuSampler` ship with incomplete C ABI exports (3 of 7
  functions). LiteRT-LM's sampler factory falls back to the static / CPU chain.
  - [google-ai-edge/LiteRT-LM #1990](https://github.com/google-ai-edge/LiteRT-LM/issues/1990) — Metal sampler missing/incomplete prebuilt
  - [google-ai-edge/LiteRT-LM #2073](https://github.com/google-ai-edge/LiteRT-LM/issues/2073) — WebGpu sampler exports only 3/7 functions on macOS/Windows
- **Linux** — the prebuilt `libLiteRtTopKWebGpuSampler.so` holds a
  process-static `wgpu::Instance` that any second `engine_create` rejects with
  `ALREADY_EXISTS: wgpu::Instance already set`. Since runtime model swap is
  more important than the few ms saved by GPU sampling, the plugin
  intentionally does not preload the sampler `.so` and lets the factory fall
  back to CPU.
  - [google-ai-edge/LiteRT #3133](https://github.com/google-ai-edge/LiteRT/issues/3133) — "MLDrift fails running second model" (closed; upstream confirms env singleton is intentional)
  - [google-ai-edge/LiteRT-LM #966](https://github.com/google-ai-edge/LiteRT-LM/issues/966) — community ask for the one-engine-many-sessions pattern

Once upstream lands the missing exports / a wgpu reset API, the plugin will
re-enable GPU sampling on the affected platforms.

### `randomSeed` is honored on CPU but not on GPU

`createSession(temperature: 1.0, randomSeed: 42)` and `randomSeed: 99` produce
**different** output on CPU (proper stochastic sampling) on every platform
that ships a freshly-rebuilt `libLiteRtLm` with the 0.14.0 patch
(`patch_c_api.sh` 6-arg `litert_lm_conversation_config_create`). On GPU,
output is **deterministic** (two runs with the same prompt → identical text)
but **does not vary across seeds** — the GPU sampler dynamic-load chain
fails before reaching the seed-aware path:

| Platform | GPU sampler dlopen failure |
|---|---|
| macOS / iOS | `libLiteRtTopKMetalSampler.dylib` ships without `LiteRtTopKMetalSampler_Create` C API export |
| Windows | `libLiteRtTopKWebGpuSampler.dll` exports 3/7 of the required symbols |
| Linux | sampler `.so` not preloaded on purpose (see `wgpu::Instance` issue above) |
| Android | `libLiteRtTopKOpenClSampler.so` `dlopen` fails with `cannot locate symbol "LiteRtCreateEnvironment"` because Android Native Assets loads `libLiteRtLm.so` with `RTLD_LOCAL` and the `LiteRt*` exports are not visible to the dlopen'd sampler |

`sampler_factory.cc:728` falls back to `CPU sampling` (a deterministic
statically-linked argmax) which ignores `randomSeed` entirely. The forward
pass still runs on the GPU accelerator — only the per-token pick is on CPU
argmax.

For comparison: on flutter_gemma **0.13.6** even CPU did not honor any
sampler params (`temperature`, `topK`, `topP`, `randomSeed`) because the
Dart-side `createConversation` gated session config on
`systemMessage != null`, and the prebuilt `libLiteRtLm` had a no-args
`config_create` that silently ignored the session config we tried to
attach. 0.14.0's `patch_c_api.sh` fixes that for CPU on every platform
that ships the patched `libLiteRtLm` build (macOS today; Linux, Windows,
Android, iOS pending CI rebuild). GPU honors-seed remains blocked on the
upstream sampler exports above.

Tracking issues: [#1990](https://github.com/google-ai-edge/LiteRT-LM/issues/1990),
[#2073](https://github.com/google-ai-edge/LiteRT-LM/issues/2073).

### macOS vision is broken upstream

Vision input (`supportImage: true`) on macOS produces hallucinated answers
unrelated to the image content. This is a bug in the upstream MediaPipe /
LiteRT vision pipeline ([flutter_gemma #684](https://github.com/DenisovAV/flutter_gemma/issues/684)). Use text-only mode on macOS until upstream fixes it.

### Audio modality requires LiteRT-LM models

Audio input only works with `.litertlm` models that include the audio adapter
(Gemma 3n E2B/E4B, Gemma 4 E2B/E4B). MediaPipe `.task` models on web don't
support audio.

### iOS Simulator: GPU disabled

iOS Simulator's Metal has a 256 MB single-allocation cap that LLM weight
tensors exceed (Gemma 3 1B's KV cache alone is 288 MB). Use CPU on the
simulator, or test on a physical iPhone for GPU validation.

---

## Troubleshooting

### Engine create fails with no native log on Linux

In **debug builds** the plugin redirects native stderr to
`<tmpdir>/litertlm_native.log` and dumps it via `debugPrint` after a failed
`engine_create`. If you don't see a dump, set `defaultTargetPlatform == TargetPlatform.linux` and run in `flutter run --debug`.

In release builds stderr goes to systemd journal / app's own stderr — check
your distribution's log facility.

### `glibc 2.38 not found` on Linux

The 0.14.0 bundle is built against glibc 2.34 (Ubuntu 22.04 toolchain). If
you see this error on a stock Ubuntu 22.04 system you're hitting a stale
local binary in `native/litert_lm/prebuilt/linux_x86_64/`. Clear it:

```bash
rm -rf native/litert_lm/prebuilt/linux_x86_64/
flutter clean && flutter run
```

`hook/build.dart` will fetch the correct glibc-2.34 binary from the GitHub
release on next run.

### Windows GPU shaders fail to compile

Symptom: `engine_create` returns null with no Dart-side error, app silently
falls back to CPU.

Verify `dxcompiler.dll` and `dxil.dll` are next to your `app.exe`. They should
be — Native Assets bundles them. If they're absent, the WebGPU/DX12 shader
compiler can't run.

If they're present but still failing, check that the user's Windows has the
[VS 2019+ Visual C++ Runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe).

### Model file not found / `Cannot find: gemma-...litertlm`

On all desktop platforms the model is downloaded to the platform's standard
"app support" directory:

- macOS: `~/Library/Containers/<bundle-id>/Data/Documents/`
- Windows: `%USERPROFILE%\AppData\Roaming\<app-name>\`
- Linux: `~/.local/share/<bundle-id>/`

Use `FlutterGemma.installModel(...).fromNetwork(...).install()` to download,
or `.fromFile(absolutePath)` if you already have it locally.

### Pre-cached engine + new code = stale cache

LiteRT-LM caches compiled GPU shaders next to the model file
(`<model>.litertlm_<random>_mldrift_program_cache.bin`). After upgrading the
plugin or the model, delete that file and the engine will rebuild the cache
on first run.

---

## API Reference

`FlutterGemma`, `InferenceModel`, `InferenceModelSession`, `InferenceChat` —
all platform-agnostic. See `lib/flutter_gemma_interface.dart` and the
[example app](example/) for usage patterns.

For native debugging on iOS / Linux, see comments in
`lib/core/ffi/litert_lm_client.dart` (search for `stream_proxy_redirect_stderr`
and `_dumpNativeLog`).
