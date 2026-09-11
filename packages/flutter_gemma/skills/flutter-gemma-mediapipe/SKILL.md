---
name: flutter-gemma-mediapipe
description: Use when running .task or .bin models (MediaPipe GenAI) with flutter_gemma_mediapipe on Android, iOS or web. Also use when CocoaPods rejects the iOS platform version, images are ignored in a MediaPipe chat, or maxOutputTokens has no effect. MediaPipe has no macOS, Windows or Linux support — use a .litertlm model there (flutter-gemma-inference).
---

# The MediaPipe engine

## Rules

1. Declare `fileType: ModelFileType.task` for `.task` files and `ModelFileType.binary` for `.bin` files.
2. An app that includes this package needs iOS 16.0.
3. There is no desktop support.
4. `maxOutputTokens` is ignored. Stop generation with `session.stopGeneration()`.
5. `createChat` does not inherit image support from the model — pass `supportImage: true` to the chat as well.

## Setup

```dart
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

await FlutterGemma.initialize(inferenceEngines: [MediaPipeEngine()]);

await FlutterGemma.installModel(
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.task,
).fromNetwork(url).install();
```

`ios/Podfile`, once:

```ruby
platform :ios, '16.0'
```

Core and the other engines build from iOS 15.0. If the app does not use `.task` models, leave this package out and stay on 15.

## Images

```dart
final model = await FlutterGemma.getActiveModel(maxTokens: 4096, supportImage: true);
final chat = await model.createChat(supportImage: true);
await chat.addQueryChunk(
  Message(text: 'Describe this image.', isUser: true, imageBytes: bytes),
);
```

Without `supportImage: true` on the chat, the image is dropped and the model answers the text alone. Audio input is not supported on MediaPipe.

## Bounding output

```dart
final session = await model.createSession();
await session.addQueryChunk(Message(text: prompt, isUser: true));
var produced = 0;
await for (final token in session.getResponseAsync()) {
  stdout.write(token);
  if (++produced >= 200) {
    await session.stopGeneration();
    break;
  }
}
await session.close();
```

## Web

Load the MediaPipe runtime in `web/index.html` before Flutter starts:

```html
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

Pin the version — an unpinned import takes whatever was published last.

Web is GPU-only. Models over about 2 GB need OPFS streaming storage:

```dart
await FlutterGemma.initialize(
  webStorageMode: WebStorageMode.streaming,
  inferenceEngines: [MediaPipeEngine()],
);
```

The storage modes need helper scripts in `web/` — see `references/platform-setup.md` in the flutter-gemma-inference skill.

## Android

Text inference runs on `arm64-v8a`, `x86_64` and `armeabi-v7a`. No manifest changes are needed.
