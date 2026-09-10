---
name: flutter-gemma-mediapipe
description: Use when the app runs .task or .bin models through flutter_gemma_mediapipe — mobile and web only, no desktop. Covers the iOS 16 floor this package alone imposes, the web script tags, and why maxOutputTokens is ignored here.
---

# The MediaPipe engine

`flutter_gemma_mediapipe` runs `.task` and `.bin` models through MediaPipe
GenAI on Android, iOS and web. **There is no desktop support** — macOS, Windows
and Linux need `.litertlm`.

```dart
await FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()]);

await FlutterGemma.installModel(
  modelType: ModelType.gemma3,
  fileType: ModelFileType.task,   // the default, but say it anyway
).fromNetwork(url).install();
```

`.task` is the default `fileType`, so this is the one engine where forgetting to
declare it happens to work. Declare it regardless — it documents intent, and a
later switch to `.litertlm` then fails loudly instead of silently routing here.

## This package alone requires iOS 16

Core, litertlm, embeddings and builtin_ai all build from iOS 15.0. MediaPipe
GenAI raises the floor to **16.0** for the whole app:

```ruby
platform :ios, '16.0'
use_frameworks! :linkage => :static
```

If the app does not use `.task` models, drop this package and stay on 15.

## maxOutputTokens is ignored

MediaPipe has no session-level output cap. Passing `maxOutputTokens` logs that
it was ignored and generation runs to the model's own limit. To bound output
here, stop consuming the stream yourself.

`maxTokens` still means the context window, and MediaPipe tolerates small values
rather than crashing — unlike `.litertlm`. That difference is a property of the
engine, not of the API.

## Web

The web arm needs the MediaPipe runtime loaded before Flutter starts. Add to
`web/index.html`:

```html
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

Pin the version. An unpinned CDN import takes whatever published last, which has
shipped broken before.

Web is **GPU-only** — there is no CPU backend for MediaPipe in the browser — and
large models need the streaming storage mode:

```dart
await FlutterGemma.initialize(
  webStorageMode: WebStorageMode.streaming,   // OPFS; cacheApi caps near 2 GB
  inferenceEngines: [MediaPipeEngine()],
);
```

The runtime JS files (`cache_api.js`, `opfs_helper.js`) are not injected
automatically — copy them into the app's own `web/` directory.

## Android

The plugin ships its own native layer and its own pigeon; nothing to configure
beyond the usual OpenCL `<uses-native-library>` entries, which the core plugin's
manifest merges in for you.

Only `arm64-v8a` is shipped.

## Vision

Multimodal `.task` models work on Android, iOS and web. Audio input does not —
that is `.litertlm` only, and only on native.
