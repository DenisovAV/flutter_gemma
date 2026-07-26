---
title: Speech-to-Text
description: On-device speech-to-text for flutter_gemma — transcribe audio fully offline with moonshine-tiny via the LiteRT C API and dart:ffi.
image: https://fluttergemma.dev/images/og-image.png
---

`flutter_gemma_speech` is an opt-in satellite package that adds **on-device
speech-to-text** to flutter_gemma. It runs a **selectable** ASR model locally
through the LiteRT C API + `dart:ffi` — no cloud, no streaming a mic to a server.
You choose the model with `SttModelType` and a profile-driven, model-agnostic
pipeline resolves the matching runtime, so it isn't tied to one model.
**moonshine** (a raw-PCM seq2seq model) works end-to-end today; Whisper /
Parakeet (log-mel) profiles and text-to-speech are follow-ons.

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
  flutter_gemma: ^1.4.0
  flutter_gemma_speech: ^0.1.0
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

| Model | Input | Status |
|---|---|---|
| **moonshine-tiny** | raw PCM (seq2seq) | ✅ end-to-end |
| Whisper | log-mel | 🚧 profile follow-on |
| Parakeet | log-mel | 🚧 profile follow-on |

The pipeline is profile-driven (`SttModelProfile.forType(...)`), so adding a new
model family is a new profile rather than a new backend.
