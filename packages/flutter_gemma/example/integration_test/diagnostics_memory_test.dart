// Device test for flutter_gemma_diagnostics: proves the numbers are real on an
// actual Android or iOS process, which host tests cannot do for iOS at all.
//
//   flutter test integration_test/diagnostics_memory_test.dart -d <device-id>
//
// No setUp, on purpose (Rule 6b): anything that can fail sits inside the test
// body, so a failure is reported as a failure.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma_diagnostics/flutter_gemma_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports both values on a real device', (tester) async {
    expect(FlutterGemmaDiagnostics.isSupported, isTrue);

    final snapshot = await FlutterGemmaDiagnostics.memorySnapshot();
    // ignore: avoid_print
    print('diagnostics snapshot on ${Platform.operatingSystem}: $snapshot');

    expect(snapshot.anonymousBytes, isNotNull);
    expect(snapshot.anonymousBytes, greaterThan(0));
    // availableBytes is legitimately null on the iOS simulator (no jetsam
    // limit), so only a real device is held to it.
    if (Platform.isAndroid || !_isIosSimulator) {
      expect(snapshot.availableBytes, isNotNull);
      expect(snapshot.availableBytes, greaterThan(0));
    }
  });

  testWidgets('anonymousBytes rises by what the app actually allocates', (
    tester,
  ) async {
    const size = 256 * 1024 * 1024;
    final before =
        (await FlutterGemmaDiagnostics.memorySnapshot()).anonymousBytes!;

    // Zeroed pages are not resident until written, so touch every one.
    final block = Uint8List(size)..fillRange(0, size, 1);
    final after =
        (await FlutterGemmaDiagnostics.memorySnapshot()).anonymousBytes!;

    // ignore: avoid_print
    print('anonymousBytes delta after writing 256 MiB: ${after - before}');
    expect(block[size - 1], 1); // keep `block` alive past the second read
    expect(after - before, greaterThanOrEqualTo(size * 3 ~/ 4));
  });
}

/// The iOS simulator runs the app as a macOS process and sets this variable.
bool get _isIosSimulator =>
    Platform.isIOS && Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
