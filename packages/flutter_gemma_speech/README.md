# flutter_gemma_speech

On-device speech for [flutter_gemma](https://pub.dev/packages/flutter_gemma) — STT
and TTS today, a voice loop later — via the LiteRT C API + `dart:ffi`. Opt-in
package: add it only if your app needs speech-to-text or text-to-speech.

This package depends on `flutter_gemma_litertlm`, which owns the shared `libLiteRtLm`
native bundle and exposes the LiteRt interpreter FFI (`LiteRtBindings`) used here.

## Status

- **STT** works end-to-end for **moonshine-tiny** (raw-PCM seq2seq) via
  `LiteRtSttBackend`; `whisper`/`parakeet` (log-mel) profiles are follow-ons.
- **TTS** works end-to-end for **Matcha** (`litert-community/Matcha-TTS`, 22050 Hz)
  via `LiteRtTtsBackend` — a 3-graph LiteRT pipeline (encoder → CFM decoder →
  HiFi-GAN vocoder) producing 16-bit PCM; `kokoro`/`supertonic` are follow-ons.

Both backends are pure factories (`canHandle` always `true`) — the *model* is
selected per-install via `SttModelType` / `TtsModelType`, not the backend.

## Usage

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(
  sttBackends: [LiteRtSttBackend()],
  ttsBackends: [LiteRtTtsBackend()],
);

// Text-to-speech (Matcha): install the bundle once, then synthesize.
await FlutterGemma.installTts()
    .fromNetwork('https://huggingface.co/litert-community/Matcha-TTS/resolve/main/')
    .ofType(TtsModelType.matcha)
    .install();

final synth = await FlutterGemma.getActiveTts();
final pcm = await synth.synthesize('Hello world.'); // Uint8List, 16-bit PCM
print(synth.sampleRate); // 22050
await synth.close();
```

## Platforms

| Platform | STT | TTS |
|----------|-----|-----|
| Android / iOS | ✅ FFI | ✅ FFI |
| macOS / Linux / Windows | ✅ FFI | ✅ FFI |
| Web | 🚧 stub `UnsupportedError` | 🚧 stub `UnsupportedError` |

No `hook/build.dart` of its own — the native library is bundled by
`flutter_gemma_litertlm`'s Native Assets hook and shared transitively.
