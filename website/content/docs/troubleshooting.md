---
title: Troubleshooting
description: Common issues — downloads, memory, iOS simulator GPU, Android minSdk, web caching, and desktop storage.
image: https://fluttergemma.dev/images/og-image.png
---

Common issues and fixes. For desktop-specific problems (Linux native logs,
glibc, Windows DXC, stale GPU shader cache) see
[Desktop Support → Troubleshooting](/docs/desktop#troubleshooting).

## Downloads

- **Resume isn't supported by the HuggingFace CDN.** flutter_gemma uses smart retry with exponential backoff and **automatic restart** of interrupted downloads instead. Tune the attempt count via `maxDownloadRetries` in `FlutterGemma.initialize(...)` (default: 10).
- **Large downloads on Android (>500MB)** automatically use a foreground service (shows a notification) to bypass Android's 9-minute background execution limit. iOS uses native URLSession and needs no special handling. See [Models → downloads](/docs/models#android-foreground-service-large-downloads).
- **Custom servers on Web** must enable CORS headers. HuggingFace is already configured correctly; for Firebase Storage see the [CORS configuration docs](https://firebase.google.com/docs/storage/web/download-files#cors_configuration).

## Memory

- **iOS:** ensure `Runner.entitlements` contains the memory entitlements and the Podfile sets `platform :ios, '16.0'`. See [Installation → iOS](/docs/installation#ios).
- Reduce `maxTokens` if you hit memory pressure.
- Use smaller models (1B-2B parameters) for devices with <6GB RAM. Multimodal models (Gemma 4, Gemma3n) need 8GB+.
- Close sessions and models when not needed; monitor usage with `sizeInTokens()`.

## iOS

- **Build issues:** ensure minimum iOS version is 16.0, use static linking (`use_frameworks! :linkage => :static`), and clean/reinstall pods with `cd ios && pod install --repo-update`.
- **Simulator GPU disabled:** iOS Simulator's Metal has a 256 MB single-allocation cap that LLM weight tensors exceed (e.g. Gemma 3 1B's KV cache alone is 288 MB). Use CPU on the simulator, or test GPU on a physical iPhone. This is a simulator limit, not a plugin bug.

## Android

- **`.litertlm` models require minSdk 30.** `libLiteRtLm.so` depends on API 30+ Bionic syscalls (`pthread_cond_clockwait`, `sem_clockwait`) that can't be shimmed on older devices. MediaPipe `.task` models work on lower API levels.
- **`.litertlm` / embeddings / vision are `arm64-v8a` only.** MediaPipe text inference (`.task` / `.bin`) also runs on `x86_64` and `armeabi-v7a`. If you only use arm64-only features, add `ndk { abiFilters 'arm64-v8a' }` so the Play Store doesn't offer broken APKs. See [Installation → Android architecture](/docs/installation#android-architecture-support).
- **GPU:** add the `libOpenCL.so` `<uses-native-library>` tags to `AndroidManifest.xml`. See [Installation → Android](/docs/installation#android).

## Web

- **GPU only.** MediaPipe has no web CPU backend, so web models must run on `PreferredBackend.gpu`.
- **Mobile `.task` models often don't work on web** — use the `-web.task` (MediaPipe) or `.litertlm` (LiteRT-LM) web variant.
- **Memory / cache limits:**

| Browser | Max Model Size | Notes |
|---|---|---|
| **Chrome/Firefox** | ~2 GB | ArrayBuffer limit |
| **Safari** | ~50 MB | ⚠️ Not suitable |

- **Large models (>2GB):** use `WebStorageMode.streaming` (OPFS) to bypass the ~2 GB blob limit. Check support with `await FlutterGemma.isStreamingSupported()`. See [Installation → web storage](/docs/installation#2-initialize-flutter-gemma).
- **Storage modes:** `cacheApi` (default, persists across restarts, <2GB), `streaming` (OPFS, large models, requires Chrome 86+/Edge 86+/Safari 15.2+), `none` (ephemeral, testing only).

### Web `.litertlm` (early preview) feature matrix

Web `.litertlm` inference runs Gemma `.litertlm` models in the browser via the
upstream [`@litert-lm/core`](https://www.npmjs.com/package/@litert-lm/core)
package (WebGPU + WASM). It is an **early preview** and a subset of the native
path. MediaPipe `.task` on web is unaffected and remains fully supported.

**Works on web `.litertlm`:** text generation (sync + streaming), multi-turn chat
with history, system instruction, concurrent sessions (serialized), large models
via OPFS streaming, GPU only.

**Not supported on web `.litertlm` yet (mobile/desktop only):**

- ❌ **Vision / image input** — image inputs are dropped with a debug warning.
- ❌ **Audio input** — no Audio executor config in the JS API.
- ❌ **Thinking mode** — `extraContext` thinking channel is not wired on web.
- ❌ **Function calling / tool calls** — not available on the web runtime.
- ❌ **LoRA weights** — `loraPath` throws `UnsupportedError`.

<Info>
For full vision / audio / thinking / function calling on web today, use MediaPipe
`.task` web models instead. These web `.litertlm` limits track the upstream
`@litert-lm/core` early-preview API and will lift as Google extends the JS
executor surface.
</Info>

## Desktop storage locations

Desktop builds store downloaded models **outside** the user's `Documents/` folder
to avoid OneDrive / iCloud / Domain-Roaming sync corrupting FFI mmap of large
`.litertlm` files:

- **Windows:** `%LOCALAPPDATA%\flutter_gemma\` (never OneDrive-synced)
- **macOS:** `~/Library/Application Support/<bundle>/flutter_gemma/`
- **Linux:** `~/.local/share/<app>/flutter_gemma/`

Models installed by older 0.14.x / 0.15.0 builds that still live under
`Documents/` keep working via a fallback read.

## Multimodal

- Ensure you're using a multimodal model (Gemma 4, Gemma3n E2B/E4B, FastVLM).
- Set `supportImage: true` (and `supportAudio: true` for audio) when creating the model.
- Check device memory — multimodal models require more RAM.
- Use the GPU backend for better performance. See [Multimodal](/docs/multimodal).

## Function calling

- Function calling is supported only by select models (Gemma 4, Gemma3n, Gemma 3 1B, FunctionGemma, DeepSeek, Qwen, Phi-4). Unsupported models log a warning and ignore tools — they still work for text generation. Check `supportsFunctionCalls`. See [Function Calling](/docs/function-calling).
