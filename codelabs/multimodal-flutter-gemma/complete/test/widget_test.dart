import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_quickstart/capabilities.dart';
import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';
import 'package:gemma_quickstart/wav.dart';

void main() {
  // `isModelInstalled` is keyed by file name. `install()` skips bytes it
  // already has, so a name that drifts from its URL does not re-download — it
  // strands the app on a download screen the gate is never satisfied by.
  test('every model id matches the last segment of its URL', () {
    for (final model in Models.all) {
      expect(model.fileName, model.url.split('/').last, reason: model.label);
    }
  });

  // The two flags are what the app ANDs against the platform, so a typo here
  // would silently disable a modality the model has, or enable one it has not.
  test('the two models differ in exactly one modality', () {
    expect(Models.smolVlm2.supportsImage, isTrue);
    expect(Models.smolVlm2.supportsAudio, isFalse);
    expect(Models.gemma4.supportsImage, isTrue);
    expect(Models.gemma4.supportsAudio, isTrue);
  });

  // The whole point of the type: two independent answers, and a message that
  // names the one that said no. A single bool could not tell these apart.
  group('Capability reports which side refused', () {
    const modelReason = 'the model has no audio encoder';
    const platformReason = 'the platform cannot carry audio';

    Capability of({required bool byModel, required bool byPlatform}) =>
        Capability(
          byModel: byModel,
          byPlatform: byPlatform,
          modelReason: modelReason,
          platformReason: platformReason,
        );

    test('both yes: available, nothing to explain', () {
      final c = of(byModel: true, byPlatform: true);
      expect(c.available, isTrue);
      expect(c.blockedBecause, isNull);
    });

    test('the model said no', () {
      final c = of(byModel: false, byPlatform: true);
      expect(c.available, isFalse);
      expect(c.blockedBecause, modelReason);
    });

    test('the platform said no', () {
      final c = of(byModel: true, byPlatform: false);
      expect(c.available, isFalse);
      expect(c.blockedBecause, platformReason);
    });

    test('both said no — fixing either one alone changes nothing', () {
      final c = of(byModel: false, byPlatform: false);
      expect(c.available, isFalse);
      expect(c.blockedBecause, contains(modelReason));
      expect(c.blockedBecause, contains(platformReason));
    });
  });

  // Forty-four bytes the model has to be able to parse. A wrong length or a
  // wrong sample rate here is not a crash — it is a clip the model hears at
  // the wrong speed, which reads as a bad model.
  test('wavFromPcm16 writes a header the sizes agree with', () {
    final pcm = Uint8List.fromList(List<int>.filled(3200, 0x11));
    final wav = wavFromPcm16(pcm, sampleRate: 16000, channels: 1);
    final view = ByteData.sublistView(wav);

    expect(wav.length, 44 + pcm.length);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    // RIFF size counts everything after its own 8 bytes.
    expect(view.getUint32(4, Endian.little), 36 + pcm.length);
    expect(view.getUint16(20, Endian.little), 1); // uncompressed PCM
    expect(view.getUint16(22, Endian.little), 1); // mono
    expect(view.getUint32(24, Endian.little), 16000);
    expect(view.getUint32(28, Endian.little), 32000); // byte rate
    expect(view.getUint16(32, Endian.little), 2); // block align
    expect(view.getUint16(34, Endian.little), 16); // bits per sample
    expect(view.getUint32(40, Endian.little), pcm.length);
    expect(wav.sublist(44), pcm);
  });

  testWidgets('the download screen offers the model before any plugin call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(
          model: Models.gemma4,
          onInstalled: () {},
          onSwitch: (_) {},
        ),
      ),
    );
    expect(find.text('Gemma 4 E2B'), findsOneWidget);
    expect(find.text('Download model'), findsOneWidget);
  });

  // The way out of a 2.59 GB download has to exist BEFORE the download does.
  testWidgets('the setup screen offers the other model, with its cost', (
    tester,
  ) async {
    ModelChoice? switched;
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(
          model: Models.gemma4,
          onInstalled: () {},
          onSwitch: (m) => switched = m,
        ),
      ),
    );
    final other = find.textContaining('Use SmolVLM2 500M instead');
    expect(other, findsOneWidget);
    expect(find.textContaining('0.36 GB'), findsOneWidget);
    await tester.tap(other);
    expect(switched, same(Models.smolVlm2));
  });
}
