---
name: flutter-gemma-speech
description: Use when adding speech to a flutter_gemma app — transcription (moonshine/Whisper/Parakeet), synthesis (Matcha/Qwen3/Inflect), or the VoiceSession loop. Audio must be 16 kHz mono 16-bit PCM, and the Whisper output language is a property of a transcription rather than of the loaded model.
---

# Speech with flutter_gemma_speech

## Register the backend first

STT is opt-in. Core registers nothing:

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(
  sttBackends: [LiteRtSttBackend()],   // transcription
  ttsBackends: [LiteRtTtsBackend()],   // synthesis
);
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

## Text-to-speech

```dart
await FlutterGemma.installTts()
    .fromNetwork('https://huggingface.co/litert-community/Matcha-TTS/resolve/main/')
    .ofType(TtsModelType.matcha)
    .install();

final synth = await FlutterGemma.getActiveTts();
try {
  final pcm = await synth.synthesize('Hello world.');   // Uint8List, 16-bit PCM
  print(synth.sampleRate);                              // 22050 for Matcha
} finally {
  await synth.close();
}
```

`sampleRate` differs per model — read it rather than assuming, or playback is
pitched wrong.

| `TtsModelType` | Languages | Notes |
| --- | --- | --- |
| `matcha` | its bundle's locale | fast, no runtime language parameter |
| `qwen3` | many, selectable | pass `language:` to `getActiveTts` |
| `inflect` | English only | ~90x real time on CPU |

## TTS language fails LOUD, unlike STT

`getActiveTts` returns a process-wide singleton, and asking an existing
synthesizer for a different language **throws** a `StateError` telling you to
`close()` first. That is deliberate: reusing it would emit wrong-language audio
with no error.

```dart
final en = await FlutterGemma.getActiveTts(language: 'english');
await en.close();                                   // required
final de = await FlutterGemma.getActiveTts(language: 'german');
```

Note the asymmetry with STT, which retargets silently and cheaply instead: a
Whisper decoder prompt is rebuilt per transcription, a TTS voice is not. Values
here are full lowercase names (`'english'`, `'german'`), not the ISO codes STT
uses.

## Voice loop

`VoiceSession` chains STT to an LLM to TTS for one push-to-talk turn, with
barge-in.

```dart
final session = VoiceSession.fromChat(
  recognizer: await FlutterGemma.getActiveStt(language: 'de'),
  chat: chat,
  synthesizer: await FlutterGemma.getActiveTts(),
);

await for (final event in session.runTurn(pcm16kMono)) {
  switch (event) {
    case VoiceTranscriptEvent(:final text):            // show it
    case VoiceReplyTextEvent(:final chunk):            // stream it
    case VoiceReplyAudioEvent(:final pcm, :final sampleRate):  // play it
    case VoiceTurnInterruptedEvent():                  // stop the player
    case VoiceTurnCompleteEvent():
    case VoiceErrorEvent():
  }
}
```

The session inherits the recognizer's current language, so set it before
starting. A chat with tools is supported — pass `onToolCall`; a tools-enabled
chat arriving without a handler throws.
