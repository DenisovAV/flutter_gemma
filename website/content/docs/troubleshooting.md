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
- **Large downloads on Android** need `foreground: true` to get a foreground service (which shows a notification) and bypass Android's 9-minute background execution limit. The default (`null`) does not configure a notification, and without one the platform never starts the service — so the size threshold alone does nothing. iOS uses native URLSession and needs no special handling. See [Models → downloads](/docs/models#android-foreground-service-large-downloads).
- **Using `background_downloader` in your own app too?** flutter_gemma no longer listens to `FileDownloader().updates` (fixed in `flutter_gemma` 1.6.3). That stream takes a single subscription, so claiming it made every later `FileDownloader().updates.listen(...)` in the host app throw *"Stream has already been listened to"*. Updates are now scoped to flutter_gemma's own task group and the stream stays yours.
- **Custom servers on Web** must enable CORS headers. HuggingFace is already configured correctly; for Firebase Storage see the [CORS configuration docs](https://firebase.google.com/docs/storage/web/download-files#cors_configuration).

### Gated models / download errors (401, 403)

`installModel(...).install()` throws a public `DownloadException` carrying a sealed `DownloadError`, so you can react to gated HuggingFace models (HTTP 401/403) by **type** instead of substring-matching error strings:

```dart
try {
  await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
      .fromNetwork(url, token: hfToken)
      .install();
} on DownloadException catch (e) {
  switch (e.error) {
    case UnauthorizedError():   // 401 — missing/invalid HuggingFace token
    case ForbiddenError():      // 403 — token lacks access to this gated model
      showGatedModelDialog();
    case NotFoundError():       // 404 — bad URL (use /resolve/main/, not /blob/main/)
      showNotFoundDialog();
    case RateLimitedError():    // 429
    case ServerError():         // 5xx
    case NetworkError():        // connectivity
    case CanceledError():       // user canceled
    case UnknownError():
      showRetryDialog(e.error.toUserMessage());
  }
}
```

For a **gated** model (401/403): pass a valid `huggingFaceToken` to `FlutterGemma.initialize(...)` (or `token:` on `fromNetwork(...)`), open the model page on HuggingFace, accept its license, and request access. Each `DownloadError` also exposes `toUserMessage()`, `toTitle()`, `isRetryable`, and `requiresUserAction` for building UI.

<Info>
Auth errors (401/403/404) fail fast after one attempt — they are not retried. Only `NetworkError`, `ServerError`, and `RateLimitedError` are retryable (see `isRetryable`).
</Info>

## Memory

- **iOS:** ensure `Runner.entitlements` contains the memory entitlements and the deployment target is at least 15.0 (16.0 with `flutter_gemma_mediapipe`) — in Xcode on the Runner target under SPM, or in the `Podfile` when one exists. See [Installation → iOS](/docs/installation#ios).
- Reduce `maxTokens` if you hit memory pressure — but **keep it at 1024 or higher for `.litertlm` models** (see "maxTokens vs maxOutputTokens" below). To shorten replies, use `maxOutputTokens`, not a smaller `maxTokens`.
- Use smaller models (1B-2B parameters) for devices with <6GB RAM. Multimodal models (Gemma 4, Gemma3n) need 8GB+.
- Close sessions and models when not needed; monitor usage with `sizeInTokens()`.

## maxTokens vs maxOutputTokens

`maxTokens` (on `getActiveModel`/`createModel`) is the **context window** — the total budget shared by the input (system prompt + history + your message) **and** the generated output (the KV-cache size). It is **not** the reply length.

`.litertlm` models require a context window of at least **1024**. Passing a smaller `maxTokens` (e.g. `100`) used to crash with `DYNAMIC_UPDATE_SLICE failed to prepare` / `Failed to allocate tensors` (even on CPU — the failure is at graph compile, before the backend runs). As of **1.0.2** a too-small `maxTokens` is clamped up to 1024 automatically with a log warning.

To limit how many tokens the model **generates**, use `maxOutputTokens` on `createSession`/`openSession`/`createChat`/`openChat` instead:

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 1024); // context window
final chat = await model.createChat(maxOutputTokens: 100);        // reply cap
```

(`maxOutputTokens` is honored on `.litertlm`; the MediaPipe `.task` path has no session-level output cap and ignores it.)

## iOS

- **Build issues:** ensure the minimum iOS version is at least 15.0 (16.0 with `flutter_gemma_mediapipe`). If the app has a `Podfile` (any app using `flutter_gemma_mediapipe` does — it ships no `Package.swift`), also use static linking (`use_frameworks! :linkage => :static`) and reinstall with `cd ios && pod install --repo-update`. An SPM-only app has no `Podfile`; there the deployment target lives on the Runner target in Xcode.
- **Simulator GPU disabled:** iOS Simulator's Metal has a 256 MB single-allocation cap that LLM weight tensors exceed (e.g. Gemma 3 1B's KV cache alone is 288 MB). Use CPU on the simulator, or test GPU on a physical iPhone. This is a simulator limit, not a plugin bug.

## Android

- **`.litertlm` models require minSdk 30.** `libLiteRtLm.so` depends on API 30+ Bionic syscalls (`pthread_cond_clockwait`, `sem_clockwait`) that can't be shimmed on older devices. MediaPipe `.task` models work on lower API levels.
- **`.litertlm` / embeddings / vision are `arm64-v8a` only.** MediaPipe text inference (`.task` / `.bin`) also runs on `x86_64` and `armeabi-v7a`. If you only use arm64-only features, add `ndk { abiFilters 'arm64-v8a' }` so the Play Store doesn't offer broken APKs. See [Installation → Android architecture](/docs/installation#android-architecture-support).
- **GPU:** add the `libOpenCL.so` `<uses-native-library>` tags to `AndroidManifest.xml`. See [Installation → Android](/docs/installation#android).
- **Zero chunks and `Stream error: <U+FFFD>`, then `SIGABRT`.** Fixed in `flutter_gemma_litertlm` 1.5.2. On Android the first `dlopen` of `libLiteRtLm` decides for the whole process whether its symbols are reachable from the default search scope, and bionic never promotes it afterwards — so an app that embedded or transcribed anything before its first generation left the stream-callback ABI probe blind and the wrong callback shape was registered. Upgrade to 1.5.2. If your own or third-party code loads `libLiteRtLm` first, load it with `RTLD_GLOBAL` — 1.5.2 cannot repair that case, but it raises a `StateError` naming it rather than generating corrupt text. See [#447](https://github.com/DenisovAV/flutter_gemma/issues/447).

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

## Windows desktop GPU crashes

<Warning>
**Fixed in litertlm 1.4.0.** Windows **discrete GPUs** crash on
`PreferredBackend.gpu` in litertlm 1.2.0–1.3.1. Upgrade to 1.4.0; on the
affected versions use `PreferredBackend.cpu` or `.npu`. macOS/Linux GPU and
Windows CPU/NPU were never affected. See [Desktop → Known
limitations](/docs/desktop#known-limitations).
</Warning>

## Desktop storage locations

Desktop builds store downloaded models **outside** the user's `Documents/` folder
to avoid OneDrive / iCloud / Domain-Roaming sync corrupting FFI mmap of large
`.litertlm` files:

- **Windows:** `%LOCALAPPDATA%\flutter_gemma\` (never OneDrive-synced)
- **macOS:** `~/Library/Application Support/<bundle>/flutter_gemma/`
- **Linux:** `~/.local/share/<app>/flutter_gemma/`

Models installed by older 0.14.x / 0.15.0 builds that still live under
`Documents/` keep working via a fallback read.

On Windows, flutter_gemma **before 1.4.0** could write a *fresh* download to a
`$CWD`-relative path (`<cwd>\Users\…\AppData\Local\flutter_gemma\`) instead of the
absolute `%LOCALAPPDATA%\flutter_gemma\`, because `%LOCALAPPDATA%` is not one of
`background_downloader`'s base directories. The model then reported "installed"
but failed to load with *"model file paths not found"*. **Fixed in 1.4.0** — it
affected every fresh inference / embedding / STT download on Windows, so upgrade
if you hit it.

## Multimodal

- Ensure you're using a multimodal model (Gemma 4, Gemma3n E2B/E4B, FastVLM).
- Set `supportImage: true` (and `supportAudio: true` for audio) when creating the model.
- Check device memory — multimodal models require more RAM.
- **Image input crashes at model load on a GPU text backend (older releases).**
  On Metal (iOS/macOS) and WebGPU (Windows/Linux) the vision encoder's ops can't
  be prepared by the GPU delegate. Fixed in **`flutter_gemma_litertlm` 1.4.2 /
  core 1.5.9** — the vision encoder now defaults to CPU while the text decoder
  keeps the GPU. Upgrade if you hit it.
- Use the GPU backend for faster text decoding. Image encoding runs on CPU by
  default; move audio encoding to GPU with `preferredAudioBackend: PreferredBackend.gpu`.
  To force GPU vision (only for a model built to allow it), pass
  `preferredVisionBackend: PreferredBackend.gpu`. See [Multimodal](/docs/multimodal).

## Native libraries fetched at build time

Some packages download their native library from a GitHub Release when you first
build for a platform, then cache it under `~/.cache/flutter_gemma/native/`
(`~/Library/Caches/…` on macOS, `%LOCALAPPDATA%\…` on Windows). This applies to
`flutter_gemma_litertlm` (always has), `flutter_gemma_onnx`, and
`flutter_gemma_rag_sqlite` **from 1.3.0** — before that it shipped the loadables
inside the package.

- **The build fails with a download error or an HTTP status.** The first build of
  each platform needs `github.com` reachable. In an air-gapped or proxied CI,
  pre-populate that cache directory, or vendor the archives and point the build
  at them.
- **The build fails with `CHECKSUM MISMATCH`.** The bytes served do not match
  what the package version was pinned to. Re-run once to rule out a corrupt
  transfer. If it persists, the release asset was replaced after publication —
  do not work around it by clearing the checksum; report it.
- **A build that used to succeed now fails instead of quietly skipping.** That is
  deliberate. These hooks used to report success while bundling nothing, which
  surfaced later as an opaque `dlopen` crash on a user's device. A platform the
  package claims to support now fails the build when its library cannot be
  produced.
- **Maintainers only:** a local `native/<name>/prebuilt/<target>/` overrides the
  pinned release, and the hook says so on stderr when it takes that path. If a
  new release "did not take", that line is the first thing to look for.

## Function calling

- Function calling is supported only by select models (Gemma 4, Gemma3n, Gemma 3 1B, FunctionGemma, DeepSeek, Qwen, Phi-4). Unsupported models log a warning and ignore tools — they still work for text generation. Check `supportsFunctionCalls`. See [Function Calling](/docs/function-calling).
