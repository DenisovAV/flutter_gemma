import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_quickstart/capabilities.dart';
import 'package:gemma_quickstart/download_page.dart';
import 'package:gemma_quickstart/model.dart';

void main() {
  // `isModelInstalled` is keyed by file name. `install()` skips bytes it
  // already has, so a name that drifts from its URL does not re-download — it
  // strands the app on a download screen the gate is never satisfied by.
  test('every model id matches the last segment of its URL', () {
    for (final model in [Models.smolVlm2]) {
      expect(model.fileName, model.url.split('/').last, reason: model.label);
    }
  });

  // The whole point of the type: two independent answers, and a message that
  // names the one that said no. A single bool could not tell these apart.
  group('Capability reports which side refused', () {
    const modelReason = 'the model has no vision encoder';
    const platformReason = 'the platform cannot carry images';

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

  testWidgets('the download screen offers the model before any plugin call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadPage(model: Models.smolVlm2, onInstalled: () {}),
      ),
    );
    expect(find.text('SmolVLM2 500M'), findsOneWidget);
    expect(find.text('Download model'), findsOneWidget);
  });
}
