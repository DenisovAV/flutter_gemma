---
title: Multimodal
description: Send image and audio input to vision/audio models like Gemma 4, Gemma3n, FastVLM, Qwen2-VL, SmolVLM2, and LLaVA-OneVision.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma supports **text + image** input (vision) and **audio** input with
the right models. Multimodal models require more memory and are recommended for
devices with 8GB+ RAM.

## Vision (image input)

Vision is supported by **Gemma 4 E2B/E4B**, **Gemma3n E2B/E4B**, **FastVLM 0.5B**
(desktop), and the community models **Qwen2-VL 2B**, **SmolVLM2 500M**, and
**LLaVA-OneVision 0.5B** (Android, iOS, Desktop). Gemma 4 / Gemma3n vision runs on
all four platforms (Android, iOS, Web, Desktop). On the `.litertlm` engine the
text decoder runs on your chosen backend (Metal / Vulkan / DX12 on GPU), while
the **vision encoder always runs on CPU by default** — the Metal/WebGPU delegates
can't prepare its ops — so image input works on a GPU text backend with no extra
config.

### Enabling vision

Set `supportImage: true` when creating the model:

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,   // drives the text decoder
  supportImage: true,
);
```

`preferredBackend` selects the text decoder's backend. The vision encoder runs on
CPU by default regardless (the Metal/WebGPU delegates can't prepare its
`STABLEHLO_COMPOSITE` ops — routing it to GPU used to hard-fail at model load;
`flutter_gemma_litertlm` 1.4.2 fixes this by defaulting the vision encoder to
CPU). To force GPU vision — only for a model whose vision section is built to
allow it — pass `preferredVisionBackend: PreferredBackend.gpu` to
`getActiveModel(...)`.

### Sending an image

```dart
// Text + Image
final message = Message.withImages(
  text: "What's in this image?",
  imageBytes: [imageBytes],
  isUser: true,
);

// Image only
final imageMessage = Message.imagesOnly(imageBytes: [imageBytes], isUser: true);

final chat = await model.createChat();
await chat.addQueryChunk(message);
final response = await chat.generateChatResponse();

// Check if a message contains an image
if (message.hasImage) {
  print('This message contains an image');
}
```

<Info>
The plugin automatically handles common image formats (JPEG, PNG, etc.) when
using `Message.withImages()` or `Message.withImage()`. The GPU backend speeds up
text decoding; image encoding still runs on CPU (audio encoding can be moved to
GPU — see below).
</Info>

## Audio (voice input)

Audio input works with **Gemma 4 E2B/E4B** and **Gemma3n E2B/E4B** models that
include the audio adapter.

| Platform | Audio support |
|---|---|
| Android | ✅ Full |
| iOS | ✅ Device only (Simulator is CPU-only / no GPU) |
| Desktop (macOS/Windows/Linux) | ✅ `.litertlm` only (via FFI) |
| Web | ❌ Not supported |

Enable audio with `supportAudio: true`:

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,        // text decoder
  supportImage: true,
  supportAudio: true,
  preferredAudioBackend: PreferredBackend.gpu,   // move the audio encoder to GPU
);
```

<Warning>
Audio input only works with `.litertlm` models that include the audio adapter.
MediaPipe `.task` models on web do not support audio. On macOS, Gemma 3n audio
runs roughly 2× faster on GPU than on CPU — but the audio encoder defaults to
CPU, so pass `preferredAudioBackend: PreferredBackend.gpu` (as above) to get that
speedup; `preferredBackend` alone only moves the text decoder.
</Warning>

## Web limitations

The web `.litertlm` path (`@litert-lm/core`, early preview) does **not** support
vision or audio yet — image inputs are dropped with a debug warning and there is
no audio executor in the JS API. For full vision on web, use **MediaPipe `.task`
web** models (which do support image input). See
[Troubleshooting](/docs/troubleshooting) for the full web `.litertlm` feature
matrix.

## Troubleshooting multimodal

- Ensure you're using a multimodal model (Gemma 4, Gemma3n E2B/E4B, FastVLM, Qwen2-VL, SmolVLM2, LLaVA-OneVision).
- Set `supportImage: true` when creating the model (and `supportAudio: true` for audio).
- Check device memory — multimodal models require more RAM.
- Use the GPU backend for faster text decoding. Image encoding runs on CPU by
  default; move audio encoding to GPU with `preferredAudioBackend: PreferredBackend.gpu`.
- If image input fails at model load on a GPU backend on an older release, upgrade
  to `flutter_gemma_litertlm` 1.4.2 — the vision encoder now defaults to CPU.
