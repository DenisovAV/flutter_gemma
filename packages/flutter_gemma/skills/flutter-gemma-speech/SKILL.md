---
name: flutter-gemma-speech
description: Use when adding speech to a flutter_gemma app — speech-to-text (transcribe a voice note, dictation, Whisper, moonshine, Parakeet), text-to-speech (Matcha, Qwen3-TTS, Inflect), or a push-to-talk voice assistant with VoiceSession. Also use when transcripts come back in English for non-English audio, synthesized audio plays at the wrong pitch, or getActiveTts throws a StateError about the language. For LLM text generation, use flutter-gemma-inference.
---

# Speech with flutter_gemma_speech

## Rules

1. Audio input is 16 kHz, mono, 16-bit little-endian PCM. Not a WAV file (strip its 44-byte header), not 44.1 or 48 kHz. Nothing is resampled for you.
2. Play synthesized audio at `synth.sampleRate`. It differs per model.
3. Only Whisper has a selectable output language. moonshine-tiny and Parakeet are English-only, and passing a language to them throws `ArgumentError`.
4. STT language: set a default with `getActiveStt(language:)` or override one call with `transcribe(pcm, language:)`. Nothing reloads.
5. TTS language: `close()` the synthesizer first. Asking a live synthesizer for another language throws `StateError`.
6. Android needs `minSdk 30`. There is no web support — the web backends throw `UnsupportedError`.
7. Close recognizers and synthesizers.

## Setup

```dart
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(
  sttBackends: [LiteRtSttBackend()],
  ttsBackends: [LiteRtTtsBackend()],
);
```

## Speech-to-text

An STT model is two files — the model and its tokenizer — usually from different repos.

```dart
await FlutterGemma.installStt()
    .modelFromNetwork('https://huggingface.co/litert-community/whisper-tiny/resolve/main/whisper_tiny_30s_f32.tflite')
    .tokenizerFromNetwork('https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json')
    .ofType(SttModelType.whisper)
    .install();

final recognizer = await FlutterGemma.getActiveStt(language: 'de');
try {
  final german = await recognizer.transcribe(germanPcm);
  final french = await recognizer.transcribe(frenchPcm, language: 'fr');
} finally {
  await recognizer.close();
}
```

| `SttModelType` | Languages | Window |
| --- | --- | --- |
| `moonshine` | English | 5 s |
| `whisper` | 99, selectable, default `'en'` | 30 s |
| `parakeet` | English | 5 s, desktop only (2.35 GB) |

Longer audio has to be split by the caller.

## Traps

**Transcript comes back in English**
- Symptom: German audio, fluent English text, no error.
- Cause: Whisper's language token decides the output language, not what it understands — with `'en'` it translates. moonshine only ever produces English.
- Fix: use Whisper and pass `language:`.

**A language is rejected**
- Whisper codes are bare and lowercase: `'de'`, not `'de-DE'`, `'DE'` or `'german'`. Malformed codes throw `ArgumentError` from `getActiveStt`.
- A well-formed code the installed checkpoint lacks (e.g. `'zz'`) throws `ArgumentError` from `transcribe`.

## Text-to-speech

```dart
await FlutterGemma.installTts()
    .fromNetwork('https://huggingface.co/litert-community/Matcha-TTS/resolve/main/')
    .ofType(TtsModelType.matcha)
    .install();

final synth = await FlutterGemma.getActiveTts();
try {
  final audio = await synth.synthesize('Hello world.'); // 16-bit PCM
  final rate = synth.sampleRate;                        // 22050 for Matcha
} finally {
  await synth.close();
}
```

| `TtsModelType` | Languages |
| --- | --- |
| `matcha` | fixed by the installed bundle |
| `qwen3` | `chinese`, `english`, `german`, `italian`, `portuguese`, `spanish`, `japanese`, `korean`, `french`, `russian`, or `auto` |
| `inflect` | English |

`supertonic` and `kokoro` are in the enum but throw `UnimplementedError` — do not use them.

Switching the Qwen3 language — full lowercase names, not ISO codes:

```dart
final english = await FlutterGemma.getActiveTts(language: 'english');
await english.close();
final german = await FlutterGemma.getActiveTts(language: 'german');
```

## Voice assistant

`VoiceSession` runs one push-to-talk turn: transcribe, generate, speak, with barge-in. It uses the recognizer's current language.

```dart
final voice = VoiceSession.fromChat(
  recognizer: await FlutterGemma.getActiveStt(language: 'de'),
  chat: chat,
  synthesizer: await FlutterGemma.getActiveTts(),
);

await for (final event in voice.runTurn(pcm16kMono)) {
  switch (event) {
    case VoiceTranscriptEvent(:final text):
      print('heard: $text');
    case VoiceReplyTextEvent(:final chunk):
      stdout.write(chunk);
    case VoiceReplyAudioEvent(:final sampleRate):
      print('audio at $sampleRate Hz');
    case VoiceTurnInterruptedEvent():
      print('interrupted — stop the player');
    case VoiceTurnCompleteEvent():
      print('done');
    case VoiceErrorEvent(:final error):
      print('failed: $error');
  }
}
```

A chat created with tools also needs `onToolCall:` — without it `fromChat` throws.
