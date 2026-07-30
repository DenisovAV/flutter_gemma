---
title: Speech
description: On-device speech for flutter_gemma — transcribe audio and synthesize speech fully offline (moonshine-tiny STT + Matcha TTS) via the LiteRT C API and dart:ffi.
image: https://fluttergemma.dev/images/og-image.png
---

`flutter_gemma_speech` is an opt-in satellite package that adds **on-device
speech** — speech-to-text and text-to-speech — to flutter_gemma. It runs
**selectable** models locally through the LiteRT C API + `dart:ffi` — no cloud,
no streaming a mic to a server.
You choose the model with `SttModelType` / `TtsModelType` and a profile-driven,
model-agnostic pipeline resolves the matching runtime, so it isn't tied to one
model. **moonshine** (a raw-PCM seq2seq STT model) and **Matcha** (TTS) work
end-to-end today; Whisper / Parakeet STT profiles and kokoro / supertonic TTS
voices are follow-ons.

<Info>
Speech is a separate package so apps that don't need it don't ship the model or
the extra native surface. It depends on <code>flutter_gemma_litertlm</code>,
which owns the shared <code>libLiteRtLm</code> native bundle — no separate
native download.
</Info>

## Install

Add the core and the speech package. `flutter_gemma_speech` pulls in
`flutter_gemma_litertlm` (which owns the shared `libLiteRtLm` native bundle)
transitively — you don't add it yourself unless you also run `.litertlm`
inference.

```
dependencies:
  flutter_gemma: ^1.4.1
  flutter_gemma_speech: ^0.4.0
```

## Register the backend

STT is opt-in: pass `LiteRtSttBackend()` to `initialize()`. The backend is a
pure factory — the *model* is chosen per-install via `SttModelType`, not by the
backend.

```dart
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_speech/flutter_gemma_speech.dart';

await FlutterGemma.initialize(
  sttBackends: const [LiteRtSttBackend()],
);
```

## Install a model + transcribe

Install moonshine-tiny (model + tokenizer) once, then transcribe raw PCM. The
recognizer is created lazily by `getActiveStt()`.

```dart
// One-time install (downloads to the app's local storage).
await FlutterGemma.installStt()
    .modelFromNetwork(
      'https://huggingface.co/litert-community/moonshine-tiny/resolve/main/moonshine_tiny_5s_f32.tflite',
    )
    .tokenizerFromNetwork(
      'https://huggingface.co/UsefulSensors/moonshine/resolve/main/ctranslate2/tiny/tokenizer.json',
    )
    .ofType(SttModelType.moonshine)
    .install();

final recognizer = await FlutterGemma.getActiveStt();

// pcm: 16 kHz mono 16-bit little-endian PCM bytes (Uint8List) — e.g. the data
// chunk of a WAV, or frames from a recorder. moonshine-tiny handles up to ~5 s.
final transcript = await recognizer.transcribe(pcm);
print(transcript); // "She had ... watch for all year."

await recognizer.close();
```

The moonshine repos are public, so no HuggingFace token is required. For gated
models pass a token to `initialize(huggingFaceToken: ...)` or per source
(`.modelFromNetwork(url, token: ...)`).

## Audio format

`transcribe()` takes **raw 16 kHz mono 16-bit little-endian PCM** (`Uint8List`)
— moonshine-tiny consumes samples directly, with no mel frontend. If you start
from a WAV file, skip the 44-byte header and pass the data chunk; if you capture
from a recorder, configure it for 16 kHz / mono / 16-bit PCM.

## Text-to-speech (Matcha)

TTS is opt-in the same way: pass `LiteRtTtsBackend()` to `initialize()`, then
install a voice and synthesize. **Matcha** (`litert-community/Matcha-TTS`) runs a
3-graph LiteRT pipeline (text-encoder → CFM decoder → HiFi-GAN vocoder) fully
on-device and returns 16-bit PCM at 22050 Hz.

```dart
await FlutterGemma.initialize(
  ttsBackends: const [LiteRtTtsBackend()],
);

// One-time install of the Matcha bundle (downloads to the app's local storage).
await FlutterGemma.installTts()
    .fromNetwork('https://huggingface.co/litert-community/Matcha-TTS/resolve/main/')
    .ofType(TtsModelType.matcha)
    .install();

final synth = await FlutterGemma.getActiveTts();
final pcm = await synth.synthesize('Hello world.'); // Uint8List, 16-bit PCM
// Wrap with a 44-byte WAV header (synth.sampleRate == 22050, mono) to play it.
await synth.close();
```

The Matcha repo is public, so no HuggingFace token is required. Synthesis is
deterministic on a given arch — byte-identical on arm64, with imperceptible
low-float-bit divergence on x86_64.

## Voice loop

`VoiceSession` chains STT → LLM → TTS into one push-to-talk turn — transcribe,
generate a chat reply, synthesize it — streamed back as `VoiceEvent`s. Build
one with `VoiceSession.fromChat`, which wraps an `InferenceChat` (it must have
no tools — route tool use through `VoiceSession.custom` + `AgentLoop` instead).

```dart
final recognizer = await FlutterGemma.getActiveStt();
final synthesizer = await FlutterGemma.getActiveTts();
final chat = await (await FlutterGemma.getActiveModel(maxTokens: 1024))
    .createChat(tokenBuffer: 256, maxOutputTokens: 128); // no tools, short replies

final session = VoiceSession.fromChat(
  recognizer: recognizer, chat: chat, synthesizer: synthesizer);

await for (final event in session.runTurn(pcm16kMono)) {
  switch (event) {
    case VoiceTranscriptEvent(:final text): /* show */
    case VoiceReplyTextEvent(:final chunk): /* stream */
    case VoiceReplyAudioEvent(:final pcm, :final sampleRate): /* play */
    case VoiceTurnInterruptedEvent(): /* stop player */
    case VoiceTurnCompleteEvent(): case VoiceErrorEvent(): break;
  }
}
```

`VoiceSession` owns no microphone or player — the app captures and plays PCM
itself, same as the STT/TTS sections above. For barge-in, call
`await session.interrupt()` while a turn is in flight: it stops generation,
bounded-drains the reply stream, and the turn ends with a
`VoiceTurnInterruptedEvent` instead of `VoiceTurnCompleteEvent`.

## Platform support

| Platform | Support |
|---|---|
| Android | ✅ FFI |
| iOS | ✅ FFI |
| macOS | ✅ FFI |
| Windows | ✅ FFI |
| Linux | ✅ FFI |
| Web | 🚧 follow-on (the web arm is a stub that throws `UnsupportedError`) |

On Android, STT (like everything backed by `libLiteRtLm`) is **arm64-only** and
requires **minSdk 30** — see
[Installation → Android architecture](/docs/installation#android-architecture-support).

## Model support

| Model | Task | Input | Status |
|---|---|---|---|
| **moonshine-tiny** | STT | raw PCM (seq2seq) | ✅ end-to-end |
| **Matcha** | TTS | text (Glow-TTS + CFM) | ✅ end-to-end |
| Whisper / Parakeet | STT | log-mel | 🚧 profile follow-on |
| kokoro / supertonic | TTS | text | 🚧 voice follow-on |

Both pipelines are profile-driven (`SttModelProfile` / `TtsModelProfile`), so
adding a new model family is a new profile rather than a new backend.
