# flutter_gemma_speech

On-device speech for [flutter_gemma](https://pub.dev/packages/flutter_gemma) — STT now,
TTS and a voice loop later — via the LiteRT C API + `dart:ffi`. Opt-in package: add it
only if your app needs speech-to-text (or, later, text-to-speech).

This package depends on `flutter_gemma_litertlm`, which owns the shared `libLiteRtLm`
native bundle and exposes the LiteRt interpreter FFI (`LiteRtBindings`) used here.

## Status

STT works end-to-end for **moonshine-tiny** (raw-PCM seq2seq). `LiteRtSttBackend`
implements `SttBackendProvider` (`canHandle` always `true` — the *model* is
selected via `SttModelSpec.sttModelType`, not the backend) and drives a generic
`SttModelProfile`-based pipeline; `whisper`/`parakeet` (log-mel) profiles and
TTS/voice are follow-ons.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(
  sttBackends: [LiteRtSttBackend()],
);
```

## Platforms

| Platform | Support |
|----------|---------|
| Android / iOS | ✅ FFI |
| macOS / Linux / Windows | ✅ FFI |
| Web | 🚧 follow-on (stub throws `UnsupportedError` for now) |

No `hook/build.dart` of its own — the native library is bundled by
`flutter_gemma_litertlm`'s Native Assets hook and shared transitively.
