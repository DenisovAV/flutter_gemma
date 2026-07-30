# flutter_gemma_speech

On-device speech for [flutter_gemma](https://pub.dev/packages/flutter_gemma) — STT,
TTS, and a `VoiceSession` voice loop — via the LiteRT C API + `dart:ffi`. Opt-in
package: add it only if your app needs speech-to-text, text-to-speech, or a
push-to-talk voice loop.

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

## Voice loop

`VoiceSession` chains STT → LLM → TTS into one push-to-talk turn with barge-in.
`VoiceSession.fromChat` wraps an `InferenceChat` (which must have no tools —
route tool use to `VoiceSession.custom` + `AgentLoop` instead); `runTurn` takes
recorded PCM and streams back `VoiceEvent`s.

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
// Barge-in: await session.interrupt();
```

`VoiceSession` owns no microphone or player — the app captures PCM
(`package:record`) and plays the reply (`pcmToWav` + `package:just_audio`),
exactly as the example `stt_screen`/`tts_screen` do.

## Platforms

| Platform | STT | TTS |
|----------|-----|-----|
| Android / iOS | ✅ FFI | ✅ FFI |
| macOS / Linux / Windows | ✅ FFI | ✅ FFI |
| Web | 🚧 stub `UnsupportedError` | 🚧 stub `UnsupportedError` |

No `hook/build.dart` of its own — the native library is bundled by
`flutter_gemma_litertlm`'s Native Assets hook and shared transitively.
