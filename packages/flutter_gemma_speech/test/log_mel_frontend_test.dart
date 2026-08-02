import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gemma_speech/src/litert/log_mel_frontend.dart';
import 'package:flutter_test/flutter_test.dart';

int _argmaxOf(List<double> values) {
  var bestIndex = 0;
  var bestValue = values[0];
  for (var i = 1; i < values.length; i++) {
    if (values[i] > bestValue) {
      bestValue = values[i];
      bestIndex = i;
    }
  }
  return bestIndex;
}

void main() {
  group('applyHannWindow', () {
    test('endpoints are near zero, center is near one (periodic Hann)', () {
      final w = applyHannWindow(Float32List(400)..fillRange(0, 400, 1.0));
      expect(w.length, 400);
      expect(w[0], closeTo(0.0, 1e-6));
      expect(w[200], closeTo(1.0, 0.02));
    });
  });

  group('powerSpectrum', () {
    test(
      'peaks at the correct bin for a pure 2000 Hz tone at 16 kHz, nFft=400',
      () {
        const nFft = 400;
        const sampleRate = 16000;
        const freqHz = 2000.0; // expected bin = freqHz * nFft / sampleRate = 50
        final frame = Float32List(nFft);
        for (var n = 0; n < nFft; n++) {
          frame[n] = math.sin(2 * math.pi * freqHz * n / sampleRate);
        }
        final windowed = applyHannWindow(frame);
        final power = powerSpectrum(windowed, nFft);
        expect(power.length, nFft ~/ 2 + 1);
        expect(_argmaxOf(power), 50);
      },
    );

    test('DC input concentrates all energy in bin 0', () {
      final frame = Float32List(400)..fillRange(0, 400, 1.0);
      final power = powerSpectrum(frame, 400); // no window, pure DC
      expect(_argmaxOf(power), 0);
      expect(power[0], greaterThan(power[1] * 100));
    });
  });
}
