---
name: flutter-gemma-speech-stt
description: Use when transcribing audio with flutter_gemma_speech — installing an STT model, choosing between moonshine/Whisper/Parakeet, or setting the output language. Whisper is multilingual and the language is a per-transcription property, not a property of the loaded model.
---

# Speech-to-text with flutter_gemma_speech

## Register the backend first

STT is opt-in. Core registers nothing:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(sttBackends: [LiteRtSttBackend()]);
```

Native only — Android, iOS, macOS, Windows, Linux. The web arm is a stub that
throws `UnsupportedError`.

## Pick the model deliberately

| `SttModelType` | Input | Languages | Notes |
| --- | --- | --- | --- |
| `moonshine` | raw 16 kHz PCM | the language it hears | ~104 MB, 5 s window, fastest |
| `whisper` | log-mel | 99, selectable | tiny / base, 30 s window |
| `parakeet` | log-mel | English only | CTC 0.6B, 2.35 GB f32, desktop |

Only Whisper has a selectable output language. The other two transcribe
whatever they hear and **reject** a language argument rather than ignoring it.

## Install and transcribe

```dart
await FlutterGemma.installStt()
    .modelFromNetwork('https://huggingface.co/litert-community/whisper-tiny/resolve/main/whisper_tiny_30s_f32.tflite')
    .tokenizerFromNetwork('https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json')
    .ofType(SttModelType.whisper)
    .install();

final recognizer = await FlutterGemma.getActiveStt();
try {
  // pcm: 16 kHz mono 16-bit little-endian PCM — the data chunk of a WAV,
  // or frames from a recorder. NOT the WAV file itself.
  final transcript = await recognizer.transcribe(pcm);
} finally {
  await recognizer.close();
}
```

An STT model needs **two** files, a model and a tokenizer, and they usually come
from different repos: the LiteRT conversion of the weights, and the original
publisher's `tokenizer.json`.

## The output language is per transcription

This is the part that is easy to model wrongly. The language is one token in
Whisper's decoder seed prompt, and that prompt is rebuilt on every
transcription. Changing it costs a map lookup — it never reloads the model and
never invalidates a recognizer you are holding.

```dart
// A default for this recognizer.
final stt = await FlutterGemma.getActiveStt(language: 'de');
final german = await stt.transcribe(germanPcm);

// One call in another language — same recognizer, nothing reloaded.
final french = await stt.transcribe(frenchPcm, language: 'fr');
```

`getActiveStt` returns a process-wide singleton, and calling it again with a new
`language` retargets that recognizer. You never need to `close()` just to change
language.

Codes are Whisper's own, without the delimiters — `'en'`, `'de'`, `'uk'`, any of
the 99 — and the default is `'en'`.

## Language decides the OUTPUT, not comprehension

The shipped Whisper checkpoints are the multilingual ones (no `.en` suffix), so
the weights understand the audio either way. The token only decides what the
model writes. Measured on one German clip, same audio and build, one token
apart:

```
'en' -> " This weather is very beautiful and the sun is shining."
'de' -> " Das Wetter ist heute sehr schön und die Sonne scheint."
```

So asking for the wrong language does not garble the output — it translates,
fluently and without any error. If a user reports "it always answers in
English", the language was never applied; it is not a model failure.

## Bad values throw, they are never ignored

- A malformed code (`'de-DE'`, `'DE'`, `'german'`, `''`) is rejected before the
  model is loaded.
- A well-formed code the installed checkpoint does not have (`'zz'`) is rejected
  against that checkpoint's own tokenizer, with the valid set named in the
  error.
- Any language on `moonshine` or `parakeet` throws `ArgumentError` — those
  models have no language token to set.

Catch `ArgumentError` around a user-supplied language. Do not fall back to a
default silently; the whole design here exists because a silently ignored
language is indistinguishable from success.

## Requirements

- Audio must be **16 kHz mono 16-bit little-endian PCM**. Resample first; there
  is no conversion inside the package.
- Clips are padded or trimmed to the model's fixed window (moonshine 5 s,
  Whisper 30 s). Longer audio needs chunking by the caller.
- Transcription runs in a background isolate, so it does not block the UI.
- `flutter_gemma_speech` requires a matching core — check its `flutter_gemma`
  constraint. A core too old accepts `language:` and drops it.

## Voice loop

`VoiceSession` chains STT to an LLM to TTS for a push-to-talk turn. It inherits
the recognizer's current language, so set it before starting the session:

```dart
final session = VoiceSession.fromChat(
  recognizer: await FlutterGemma.getActiveStt(language: 'de'),
  chat: chat,
  synthesizer: await FlutterGemma.getActiveTts(),
);
await for (final event in session.runTurn(pcm)) { /* … */ }
```
