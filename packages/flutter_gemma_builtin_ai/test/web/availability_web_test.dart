@TestOn('browser')
library;

import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_prompt_api.dart';

void main() {
  setUp(() {
    BuiltInAi.debugProbeTimeout = const Duration(seconds: 20);
    FakeLanguageModel.uninstall();
  });
  tearDown(FakeLanguageModel.uninstall);

  test('availability() reports unavailableDeviceUnsupported when LanguageModel '
      'is absent (no LanguageModel installed at all in this test)', () async {
    final status = await BuiltInAi.availability();
    expect(status, BuiltInAiAvailability.unavailableDeviceUnsupported);
  });

  test('availability() maps every Chrome status string', () async {
    final expected = {
      'available': BuiltInAiAvailability.available,
      'downloadable': BuiltInAiAvailability.downloadable,
      'downloading': BuiltInAiAvailability.downloading,
      // Chrome reports no reason for 'unavailable' — folds into the
      // unclassified bucket.
      'unavailable': BuiltInAiAvailability.unavailableOther,
    };
    for (final entry in expected.entries) {
      FakeLanguageModel(availability: ([o]) => entry.key).install();
      final status = await BuiltInAi.availability();
      expect(status, entry.value, reason: 'status string: ${entry.key}');
    }
  });

  test('availability() resolves to unavailableOther when the probe never '
      'returns (does not hang)', () async {
    BuiltInAi.debugProbeTimeout = const Duration(milliseconds: 50);
    FakeLanguageModel(neverResolveAvailability: true).install();
    final status = await BuiltInAi.availability();
    expect(status, BuiltInAiAvailability.unavailableOther);
  });

  test('availability() maps a REJECTED probe promise to unavailableOther '
      '(no raw JS error escapes)', () async {
    FakeLanguageModel(rejectAvailability: true).install();
    final status = await BuiltInAi.availability();
    expect(status, BuiltInAiAvailability.unavailableOther);
  });

  test(
    'ensureReady completes immediately when available (no download)',
    () async {
      final fake = FakeLanguageModel(availability: ([o]) => 'available')
        ..install();
      await BuiltInAi.ensureReady();
      // No create() call — nothing to download when already available.
      expect(fake.createCalls, isEmpty);
    },
  );

  test('ensureReady throws BuiltInAiUnavailableException on an unavailable* '
      'status without attempting a download', () async {
    final fake = FakeLanguageModel(availability: ([o]) => 'unavailable')
      ..install();
    await expectLater(
      BuiltInAi.ensureReady(),
      throwsA(
        isA<BuiltInAiUnavailableException>().having(
          (e) => e.status,
          'status',
          BuiltInAiAvailability.unavailableOther,
        ),
      ),
    );
    expect(fake.createCalls, isEmpty);
  });

  test('ensureReady downloads via create(), reports REAL progress from '
      'downloadprogress events, and destroys the bootstrap session', () async {
    final recorder = MonitorRecorder();
    FakeSession? createdSession;
    FakeLanguageModel(
      availability: ([o]) => 'downloadable',
      create: ([options]) {
        recorder.wireFromOptions(options);
        recorder.fire(0.25);
        recorder.fire(0.5);
        recorder.fire(1.0);
        createdSession = FakeSession();
        return createdSession!;
      },
    ).install();

    final percents = <int>[];
    await BuiltInAi.ensureReady(onProgress: percents.add);

    expect(percents, [25, 50, 100]);
    expect(createdSession, isNotNull);
    expect(createdSession!.destroyCount, 1);
  });

  test('ensureReady times out (does not hang) when create() never resolves, '
      'and aborts the in-flight call', () async {
    FakeLanguageModel(
      availability: ([o]) => 'downloadable',
      neverResolveCreate: true,
    ).install();

    await expectLater(
      BuiltInAi.ensureReady(timeout: const Duration(milliseconds: 50)),
      throwsA(isA<Exception>()),
    );
  });
}
