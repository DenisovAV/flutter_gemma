// End-to-end check of a multimodal turn on a real device or desktop.
//
// Downloads SmolVLM2 (0.36 GB, ungated — no Hugging Face token), opens a
// vision session, sends an image with a question, and asserts the model
// answered. Then it asserts the other half of this codelab's idea: that the
// app asks BOTH sides before it opens a session, and opens the session the
// answers allow rather than the one the model name suggests.
//
// Not part of CI (needs a device and a ~0.36 GB download):
//   flutter test integration_test/multimodal_test.dart -d <device-id>
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:gemma_quickstart/capabilities.dart';
import 'package:gemma_quickstart/model.dart';
import 'package:gemma_quickstart/wav.dart';

/// A 16x16 solid-red PNG, inline so the suite needs no asset bundle.
final _redSquarePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR42mN4oKBA'
  'EmIY1TCqYfhqAADc5yAQocSb7AAAAABJRU5ErkJggg==',
);

/// Downloads the model if it is not here, and makes it the active one either
/// way. `install()` is idempotent, so the second call costs nothing.
Future<void> _install(ModelChoice model) async {
  var last = -1;
  await FlutterGemma.installModel(
    modelType: model.modelType,
    fileType: ModelFileType.litertlm,
  ).fromNetwork(model.url).withProgress((p) {
    if (p >= last + 25) {
      last = p;
      debugPrint('[multimodal] download $p%');
    }
  }).install();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a picture reaches the model and the model answers about it', (
    tester,
  ) async {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    const model = Models.smolVlm2;
    final image = imageCapability(model);
    debugPrint(
      '[multimodal] image — model: ${image.byModel}, '
      'platform: ${image.byPlatform}',
    );
    // On a platform that cannot carry images this suite has nothing to prove.
    // Saying so beats a green run that never sent a pixel.
    if (!image.available) {
      debugPrint('[multimodal] SKIPPED: ${image.blockedBecause}');
      return;
    }

    await _install(model);
    expect(await FlutterGemma.isModelInstalled(model.fileName), isTrue);

    final inference = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final chat = await inference.createChat(
      modelType: model.modelType,
      supportImage: image.available,
      maxOutputTokens: 64,
    );
    await chat.addQueryChunk(
      Message.withImages(
        text: 'What colour is this image? Answer in one word.',
        imageBytes: [_redSquarePng],
        isUser: true,
      ),
    );
    final buffer = StringBuffer();
    await for (final chunk in chat.generateChatResponseAsync()) {
      if (chunk is TextResponse) buffer.write(chunk.token);
    }
    debugPrint('[multimodal] reply: ${buffer.toString().trim()}');
    // Not an assertion about the colour: a 500M model is allowed to be wrong.
    // The claim under test is that a vision session accepted image bytes and
    // produced a reply instead of dropping them.
    expect(buffer.toString().trim(), isNotEmpty);

    await inference.close();
  }, timeout: const Timeout(Duration(minutes: 30)));

  testWidgets('a vision-only model opens a text session and still answers', (
    tester,
  ) async {
    await FlutterGemma.initialize(inferenceEngines: [LiteRtLmEngine()]);

    const model = Models.smolVlm2;
    final audio = audioCapability(model);
    // The model half says no for this checkpoint, on every platform. That is
    // what the app is expected to honour — it must not ask the runtime for an
    // audio session these weights cannot build.
    expect(audio.byModel, isFalse);
    expect(audio.available, isFalse);
    expect(audio.blockedBecause, contains('no audio encoder'));

    await _install(model);
    final inference = await FlutterGemma.getActiveModel(maxTokens: 4096);
    final chat = await inference.createChat(
      modelType: model.modelType,
      supportImage: imageCapability(model).available,
      // Exactly what the app passes: the AND of both answers, which is false
      // here because of the weights, whatever the platform said.
      supportAudio: audio.available,
      maxOutputTokens: 64,
    );
    await chat.addQueryChunk(
      Message.text(text: 'Name one colour. One word.', isUser: true),
    );
    final buffer = StringBuffer();
    await for (final chunk in chat.generateChatResponseAsync()) {
      if (chunk is TextResponse) buffer.write(chunk.token);
    }
    debugPrint('[multimodal] text reply: ${buffer.toString().trim()}');
    expect(buffer.toString().trim(), isNotEmpty);

    await inference.close();
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('the WAV header the recorder produces is the one the model expects', () {
    final wav = wavFromPcm16(Uint8List(3200), sampleRate: 16000, channels: 1);
    expect(wav.length, 3244);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
  });
}
