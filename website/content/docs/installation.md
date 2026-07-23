---
title: Installation
description: Add the packages, register engines, and complete per-platform setup for iOS, Android, Web, and Desktop.
image: https://fluttergemma.dev/images/og-image.png
---

As of **1.0**, `flutter_gemma` is split into a small **core** package plus
**opt-in** packages for each engine / backend, so your app only pulls the native
weight it actually uses. Add the core package, then the packages for the model
formats and features you need.

## 1. Add packages to `pubspec.yaml`

```
dependencies:
  flutter_gemma: latest_version              # Core — always required (no engine on its own)

  # Inference engines — add at least one:
  flutter_gemma_litertlm: latest_version     # .litertlm models (FFI; mobile + desktop + web)
  flutter_gemma_mediapipe: latest_version    # .task / .bin models (MediaPipe; mobile + web)
  flutter_gemma_builtin_ai: latest_version   # OS system models — Gemini Nano (Android) / Apple FM (iOS 26+/macOS)

  # Optional — text embeddings + on-device RAG:
  flutter_gemma_embeddings: latest_version   # text embeddings (EmbeddingGemma / Gecko)
  flutter_gemma_rag_qdrant: latest_version   # RAG vector store (qdrant-edge; fastest on native)
  flutter_gemma_rag_sqlite: latest_version   # RAG vector store (sqlite-vec / vec0; all platforms, incl. web)
```

**Pick by need:**

| You want to… | Add |
|---|---|
| Run `.litertlm` models (Gemma 4, Qwen3, FastVLM, + all desktop) | `flutter_gemma_litertlm` |
| Run `.task` / `.bin` models (Gemma3n, Gemma 3, DeepSeek, Qwen 2.5, Phi-4) | `flutter_gemma_mediapipe` |
| Run the OS system model with no download (Gemini Nano / Apple Foundation Models) | `flutter_gemma_builtin_ai` |
| Generate text embeddings | `flutter_gemma_embeddings` |
| On-device RAG on native, fastest (Android/iOS/desktop) | `flutter_gemma_rag_qdrant` |
| On-device RAG on web, or a portable/exact store on any platform | `flutter_gemma_rag_sqlite` |

Core registers **no** engine by itself — you wire the packages you added in
`FlutterGemma.initialize(...)` (below). Run `flutter pub get` to install.

<Info>
**Migrating from 0.16.x (monolith)?** See the [Migration guide](/docs/migration) —
the only breaking change is adding the opt-in packages and the `initialize(...)`
call; every model / session / RAG API is unchanged.
</Info>

## 2. Initialize Flutter Gemma

Call `FlutterGemma.initialize(...)` once in `main()` and **register the opt-in
packages you added** to `pubspec.yaml`. Core registers no engine on its own, so
without this step `getActiveModel()` / `createEmbeddingModel()` throw a clear
"add the engine package" error.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart';
import 'package:flutter_gemma_rag_qdrant/flutter_gemma_rag_qdrant.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterGemma.initialize(
    // Inference engines — add the ones whose packages you depend on:
    inferenceEngines: const [
      LiteRtLmEngine(),     // flutter_gemma_litertlm  — .litertlm models
      MediaPipeEngine(),    // flutter_gemma_mediapipe — .task / .bin models
      BuiltInAiEngine(),    // flutter_gemma_builtin_ai — Gemini Nano / Apple FM
    ],
    // Optional — embeddings (needed for RAG / generateEmbedding):
    embeddingBackends: const [
      LiteRtEmbeddingBackend(), // flutter_gemma_embeddings
    ],
    // Optional — RAG vector store (pick one; native here):
    vectorStore: QdrantVectorStore(), // flutter_gemma_rag_qdrant

    // Common settings:
    huggingFaceToken: const String.fromEnvironment('HUGGINGFACE_TOKEN'),
    maxDownloadRetries: 10,
  );

  runApp(MyApp());
}
```

**Which parameter ← which package:**

| Parameter | Provided by | Notes |
|---|---|---|
| `inferenceEngines: [LiteRtLmEngine()]` | `flutter_gemma_litertlm` | `.litertlm` (mobile + desktop + web) |
| `inferenceEngines: [MediaPipeEngine()]` | `flutter_gemma_mediapipe` | `.task` / `.bin` (mobile + web) |
| `embeddingBackends: [LiteRtEmbeddingBackend()]` | `flutter_gemma_embeddings` | text embeddings |
| `vectorStore: QdrantVectorStore()` | `flutter_gemma_rag_qdrant` | native RAG |
| `vectorStore: SqliteVectorStore()` / `WebSqliteVectorStore()` | `flutter_gemma_rag_sqlite` | sqlite-vec RAG (all platforms; `WebSqliteVectorStore()` on web) |

Add only the engines you ship. Passing both `LiteRtLmEngine()` and
`MediaPipeEngine()` lets one app run both formats — the registry routes each
model to the engine that handles its file type. The `sqlite-vec` store runs on
every platform — use `vectorStore: SqliteVectorStore()` on native and
`WebSqliteVectorStore()` on web. `flutter_gemma_rag_qdrant` is native-only (and
the fastest option there).

**Common settings:**

- `huggingFaceToken`: authentication token for gated models (Gemma3n, EmbeddingGemma).
- `maxDownloadRetries`: number of retry attempts for failed downloads (default: 10).
- `webStorageMode` **(Web only)**: storage strategy for model files (default: `cacheApi`).
  - `WebStorageMode.cacheApi`: Cache API with Blob URLs (for models <2GB).
  - `WebStorageMode.streaming`: OPFS streaming (for large models >2GB like E4B, 7B).
  - `WebStorageMode.none`: no caching (ephemeral mode for testing).

<Info>
Use `WebStorageMode.streaming` when shipping `.litertlm` web models — the
`@litert-lm/core` engine consumes an OPFS ReadableStream and avoids Chrome's
~2 GB blob-fetch limit on Gemma 4 E2B/E4B web builds.
</Info>

## 3. Platform-specific setup

<Warning>
Complete platform-specific setup before using the plugin.
</Warning>

### iOS

Required by any inference engine package (`flutter_gemma_litertlm` and/or
`flutter_gemma_mediapipe`).

**Set the minimum iOS version** in `Podfile`:

```
platform :ios, '16.0'  # Required for MediaPipe GenAI
```

**Change the linking type** of pods to static in `Podfile`:

```
use_frameworks! :linkage => :static
```

**Enable file sharing** in `Info.plist`:

```
<key>UIFileSharingEnabled</key>
<true/>
```

**Add a network access description** in `Info.plist` (for development):

```
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires local network access for model inference services.</string>
```

**Enable performance optimization** in `Info.plist` (optional):

```
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

**Add memory entitlements** in `Runner.entitlements` (for large models):

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.kernel.extended-virtual-addressing</key>
	<true/>
	<key>com.apple.developer.kernel.increased-memory-limit</key>
	<true/>
	<key>com.apple.developer.kernel.increased-debugging-memory-limit</key>
	<true/>
</dict>
</plist>
```

<Info>
No host-side `Podfile` `post_install` is required on iOS — flutter_gemma patches
the upstream LiteRT-LM `dlopen` path to use
`@executable_path/Frameworks/<X>.framework/<X>` so dyld resolves Metal
accelerators directly through the Native-Assets-bundled framework. This also
keeps `Runner.app/Frameworks/` App-Store-clean (fixes ITMS-90432).
</Info>

### Android

**GPU (any engine):** if you want to run on the GPU, add OpenCL support to the
manifest. Required by both inference engines. CPU-only? Skip this step. Add the
following above `</application>` in `AndroidManifest.xml`:

```
<uses-native-library
    android:name="libOpenCL.so"
    android:required="false"/>
<uses-native-library android:name="libOpenCL-car.so" android:required="false"/>
<uses-native-library android:name="libOpenCL-pixel.so" android:required="false"/>
```

**ProGuard/R8 (only if you use `flutter_gemma_mediapipe`):** the package ships
its own consumer ProGuard rules, so release builds work out of the box. If you
still hit `UnsatisfiedLinkError` / missing MediaPipe classes, add to your
`proguard-rules.pro`:

```
# MediaPipe
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Protocol Buffers
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
```

<Info>
`flutter_gemma_litertlm` is delivered as a Native-Assets dylib (no MediaPipe Java
classes), so it needs no ProGuard rules.
</Info>

#### Android architecture support

MediaPipe text inference (`.task` / `.bin`) works on `arm64-v8a`, `x86_64`, and
`armeabi-v7a`. Everything else (`.litertlm` FFI, embedding via LiteRT FFI, image
generation) is **`arm64-v8a` only**:

| Android feature | arm64-v8a | x86_64 | armeabi-v7a |
|---|:---:|:---:|:---:|
| Text inference (`.task` / `.bin`) | ✅ | ✅ | ✅ |
| `.litertlm` (FFI) | ✅ | ❌ | ❌ |
| Embedding (LiteRT FFI) | ✅ | ❌ | ❌ |
| Image generation (vision) | ✅ | ❌ | ❌ |

If your app uses only the arm64-only features, restrict the build to arm64 so the
Play Store does not offer broken APKs to incompatible devices:

```
android {
    defaultConfig {
        ndk { abiFilters 'arm64-v8a' }
    }
}
```

<Warning>
`.litertlm` models on Android require **minSdk 30** — `libLiteRtLm.so` depends on
API 30+ Bionic syscalls (`pthread_cond_clockwait`, `sem_clockwait`) that cannot
be shimmed on older devices. MediaPipe `.task` models work on lower API levels.
</Warning>

### Web

Web runs on the GPU backend only (MediaPipe has no web CPU backend). Add the CDN
script(s) for the **engine package(s) you use** to your `web/index.html`.

**`flutter_gemma_mediapipe`** (`.task` / `-web.task` models):

```
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

**`flutter_gemma_litertlm`** (`.litertlm` web models — early preview). The
`@litert-lm/core` ESM doesn't assign window globals and module scripts are
deferred, so Dart must await `window.litertLmReady` before any static interop:

```
<script type="module">
window.litertLmReady = (async () => {
  const m = await import('https://cdn.jsdelivr.net/npm/@litert-lm/core@0.14.0/+esm');
  window.Engine = m.Engine;
  return m.Engine;
})();
</script>
```

**`flutter_gemma_rag_sqlite`** (web RAG): add the sqlite-vec loader — a
`sqlite3.wasm` with the `sqlite-vec` extension statically linked, loaded via
`package:sqlite3/wasm.dart`. See that package's README for the exact `<script>` +
Subresource-Integrity hash.

<Info>
**Model compatibility:** mobile `.task` models often don't work on web — use the
`-web.task` (MediaPipe) or `.litertlm` (LiteRT-LM) web variant. Check the model
repo for web-compatible builds.
</Info>

### Desktop (macOS, Windows, Linux)

Desktop is served exclusively by **`flutter_gemma_litertlm`** and uses
**LiteRT-LM format only** (`.litertlm` files). There is no MediaPipe engine on
desktop — `.task` / `.bin` models are **NOT compatible** with desktop. The native
library is fetched at build time by the package's Native-Assets hook — no manual
download/bundling.

See [Desktop Support](/docs/desktop) for the full per-platform reference (macOS
`Podfile` `post_install`, entitlements, Windows VC++ runtime, Linux Vulkan
driver, and known limitations).

## Platform & architecture support

The plugin ships native prebuilts only for the architectures below. Other ABIs
fail at native load with a typed error.

| Platform | Supported architecture | Not supported |
|---|---|---|
| Android | `arm64-v8a` (full) | `armeabi-v7a`, `x86_64` ¹ |
| iOS device | `arm64` | — |
| iOS Simulator | `arm64` (Apple Silicon Mac) | `x86_64` (Intel Mac) |
| macOS | `arm64` (Apple Silicon) | `x86_64` (Intel Mac) |
| Linux | `x86_64`, `arm64` | — |
| Windows | `x86_64` | `arm64` |

¹ MediaPipe text inference also works on Android `x86_64` / `armeabi-v7a` (see
the Android section above).

For development, prefer an Apple Silicon Mac — the Android emulator runs
`arm64-v8a` natively, and macOS / iOS Simulator builds are arm64.

## HuggingFace authentication

Many models require authentication to download from HuggingFace. **Never commit
tokens to version control.**

### Recommended: `config.json` pattern

Create a config template `config.json.example`:

```
{
  "HUGGINGFACE_TOKEN": ""
}
```

Copy it and add your token from
[huggingface.co/settings/tokens](https://huggingface.co/settings/tokens):

```
cp config.json.example config.json
```

Add `config.json` to `.gitignore`, then run with the config:

```
flutter run --dart-define-from-file=config.json
```

Access it in code:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const token = String.fromEnvironment('HUGGINGFACE_TOKEN');

  FlutterGemma.initialize(
    huggingFaceToken: token.isNotEmpty ? token : null,
  );

  runApp(MyApp());
}
```

### Which models require authentication?

**Gated (auth required):** Gemma 4, Gemma3n (E2B, E4B), Gemma 3 1B, Gemma 3 270M,
EmbeddingGemma.

**Public (no auth):** DeepSeek, Qwen3, Qwen 2.5, SmolLM, Phi-4, FastVLM.

To use a gated repo: visit the model page → "Request Access" button.

## Logging

The plugin's internal logs are **silent in release builds** — model output,
prompts, and conversation history are never written to logcat / syslog. In debug
builds they're shown according to `FlutterGemma.logLevel`:

| Level | What it prints (debug only) |
|---|---|
| `GemmaLogLevel.none` | Nothing — fully silent. |
| `GemmaLogLevel.info` *(default)* | Lifecycle, errors, diagnostics. **No** model output / prompts. |
| `GemmaLogLevel.verbose` | Everything above **plus** model output, prompts, and conversation history. |

```dart
import 'package:flutter_gemma/flutter_gemma.dart';

// See the model's generated tokens and prompts while debugging:
FlutterGemma.logLevel = GemmaLogLevel.verbose;

// Or silence the plugin entirely:
FlutterGemma.logLevel = GemmaLogLevel.none;
```

Release builds are always silent regardless of this setting. The level is
process-global and per-isolate; set it once at startup.
