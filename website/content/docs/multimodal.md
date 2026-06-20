---
title: Multimodal
description: Send image and audio input to vision/audio models like Gemma 4, Gemma3n, and FastVLM.
image: https://fluttergemma.dev/images/og-image.png
---

flutter_gemma supports **text + image** input (vision) and **audio** input with
the right models. Multimodal models require more memory and are recommended for
devices with 8GB+ RAM.

## Vision (image input)

Vision is supported by **Gemma 4 E2B/E4B**, **Gemma3n E2B/E4B**, and **FastVLM
0.5B** (desktop). On all four platforms (Android, iOS, Web, Desktop) image input
is supported — verified on macOS Metal and Linux Vulkan with Gemma 4 + Gemma 3n.

### Enabling vision

Set `supportImage: true` when creating the model:

```dart
final model = await FlutterGemma.getActiveModel(
  maxTokens: 4096,
  preferredBackend: PreferredBackend.gpu,
  supportImage: true,
);
```

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
using `Message.withImages()` or `Message.withImage()`. Use the GPU backend for
better performance with multimodal models.
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
  preferredBackend: PreferredBackend.gpu,
  supportImage: true,
  supportAudio: true,
);
```

<Warning>
Audio input only works with `.litertlm` models that include the audio adapter.
MediaPipe `.task` models on web do not support audio. On macOS, Gemma 3n audio on
GPU is roughly 2× faster than on CPU.
</Warning>

## Web limitations

The web `.litertlm` path (`@litert-lm/core`, early preview) does **not** support
vision or audio yet — image inputs are dropped with a debug warning and there is
no audio executor in the JS API. For full vision on web, use **MediaPipe `.task`
web** models (which do support image input). See
[Troubleshooting](/docs/troubleshooting) for the full web `.litertlm` feature
matrix.

## Troubleshooting multimodal

- Ensure you're using a multimodal model (Gemma 4, Gemma3n E2B/E4B, FastVLM).
- Set `supportImage: true` when creating the model (and `supportAudio: true` for audio).
- Check device memory — multimodal models require more RAM.
- Use the GPU backend for better performance.
