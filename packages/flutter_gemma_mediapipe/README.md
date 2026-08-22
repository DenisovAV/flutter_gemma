# flutter_gemma_mediapipe

MediaPipe (`.task`) on-device inference engine for [`flutter_gemma`](https://pub.dev/packages/flutter_gemma). Opt-in package — add it only if you run MediaPipe `.task` models. Android, iOS, and Web.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

await FlutterGemma.initialize(
  inferenceEngines: [MediaPipeEngine()],
);
```

`MediaPipeEngine` handles `ModelFileType.task` / `.bin` models; pass it alongside other engines (e.g. `LiteRtLmEngine` from `flutter_gemma_litertlm`) if your app uses both formats.

## Web setup

On Web, the MediaPipe runtime is loaded from a CDN. Add this to your app's `web/index.html` (inside a `<script type="module">` before your Flutter bootstrap), exposing the symbols on `window`:

```html
<script type="module">
import { FilesetResolver, LlmInference } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai@0.10.27';
window.FilesetResolver = FilesetResolver;
window.LlmInference = LlmInference;
</script>
```

(Android needs no extra setup — the MediaPipe Gradle deps are bundled by this package.)

## iOS setup

**iOS needs a 16.0 minimum.** MediaPipe GenAI requires it, and this is the only
flutter_gemma package that does — core, `flutter_gemma_litertlm`, built-in AI and
embeddings build from 15.0 (#441).

This package ships no `Package.swift`, so even an app on Swift Package Manager gets a
`Podfile` for it. Set the floor in BOTH places: `platform :ios, '16.0'` in the `Podfile`,
and **iOS Deployment Target** on the Runner target in Xcode. Below 16, `pod install`
reports that specs satisfying the `flutter_gemma_mediapipe` dependency "required a higher
minimum deployment target".

MediaPipe ships static xcframeworks, so the `Podfile` also needs
`use_frameworks! :linkage => :static` — with the Flutter template's bare
`use_frameworks!`, `pod install` fails on "transitive dependencies that include
statically linked binaries".

## Platforms

| Platform | Support |
|----------|---------|
| Android  | ✅ `MediaPipeTasksGenAI` (Gradle) |
| iOS      | ✅ `MediaPipeTasksGenAI` (CocoaPods) — **requires iOS 16.0+** |
| Web      | ✅ `@mediapipe/tasks-genai` (CDN, see above) |
| Desktop  | ❌ (MediaPipe `.task` not supported on desktop — use `flutter_gemma_litertlm`) |
