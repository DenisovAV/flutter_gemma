import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_gemma_builtin_ai/flutter_gemma_builtin_ai.dart';
import 'package:flutter_gemma_builtin_ai/pigeon.g.dart';
import 'package:flutter_test/flutter_test.dart';

const _prefix = 'dev.flutter.pigeon.flutter_gemma_builtin_ai.BuiltInAiService';

/// Registers a mock handler for a pigeon host method. [reply] returns the value
/// list to encode (pigeon wraps a plain success as `[value]`, an error as
/// `[code, message, details]`).
void _mockHost(String method, List<Object?> Function(Object? args) reply) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('$_prefix.$method', (ByteData? message) async {
        final args = BuiltInAiService.pigeonChannelCodec.decodeMessage(message);
        return BuiltInAiService.pigeonChannelCodec.encodeMessage(reply(args));
      });
}

void _clearHost(String method) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('$_prefix.$method', null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _clearHost('checkAvailability');
    _clearHost('downloadFeature');
  });

  group('availability() maps every wire value', () {
    final cases = <AvailabilityStatus, BuiltInAiAvailability>{
      AvailabilityStatus.available: BuiltInAiAvailability.available,
      AvailabilityStatus.downloadable: BuiltInAiAvailability.downloadable,
      AvailabilityStatus.downloading: BuiltInAiAvailability.downloading,
      AvailabilityStatus.unavailableDeviceUnsupported:
          BuiltInAiAvailability.unavailableDeviceUnsupported,
      AvailabilityStatus.unavailableOsTooOld:
          BuiltInAiAvailability.unavailableOsTooOld,
      AvailabilityStatus.unavailableDisabled:
          BuiltInAiAvailability.unavailableDisabled,
      AvailabilityStatus.unavailableOther:
          BuiltInAiAvailability.unavailableOther,
    };

    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () async {
        _mockHost('checkAvailability', (_) => [entry.key]);
        expect(await BuiltInAi.availability(), entry.value);
      });
    }
  });

  test(
    'ensureReady completes immediately when available (no download)',
    () async {
      var downloadCalled = false;
      _mockHost('checkAvailability', (_) => [AvailabilityStatus.available]);
      _mockHost('downloadFeature', (_) {
        downloadCalled = true;
        return [null];
      });

      await BuiltInAi.ensureReady();
      expect(downloadCalled, isFalse);
    },
  );

  test('ensureReady throws BuiltInAiUnavailableException on disabled without '
      'downloading', () async {
    var downloadCalled = false;
    _mockHost(
      'checkAvailability',
      (_) => [AvailabilityStatus.unavailableDisabled],
    );
    _mockHost('downloadFeature', (_) {
      downloadCalled = true;
      return [null];
    });

    await expectLater(
      BuiltInAi.ensureReady(),
      throwsA(
        isA<BuiltInAiUnavailableException>().having(
          (e) => e.status,
          'status',
          BuiltInAiAvailability.unavailableDisabled,
        ),
      ),
    );
    expect(downloadCalled, isFalse);
  });

  test('ensureReady downloads then resolves when availability flips to '
      'available', () async {
    var checkCount = 0;
    var downloadCalled = false;
    _mockHost('checkAvailability', (_) {
      checkCount++;
      // First probe: downloadable. After download: available.
      return [
        checkCount == 1
            ? AvailabilityStatus.downloadable
            : AvailabilityStatus.available,
      ];
    });
    _mockHost('downloadFeature', (_) {
      downloadCalled = true;
      return [null];
    });

    await BuiltInAi.ensureReady();
    expect(downloadCalled, isTrue);
    expect(checkCount, greaterThanOrEqualTo(2));
  });

  // Regression for the Firebase Test Lab hang: on a fresh device the AICore
  // download queue may never grant a slot, so the native downloadFeature() Flow
  // emits nothing and its pigeon reply never arrives, while checkAvailability
  // stays `downloadable`. ensureReady must be bounded by its own timeout and
  // throw TimeoutException — NOT block forever on the download call.
  test('ensureReady times out (does not hang) when download never completes '
      'and availability never flips', () async {
    // downloadFeature that NEVER replies — simulates the stuck AICore queue.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          '$_prefix.downloadFeature',
          (ByteData? message) => Completer<ByteData?>().future, // never completes
        );
    _mockHost('checkAvailability', (_) => [AvailabilityStatus.downloadable]);

    await expectLater(
      BuiltInAi.ensureReady(timeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
