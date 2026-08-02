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

  group('stftFrames', () {
    test('produces exactly melFrames windows of length nFft', () {
      final pcm = Float32List(16000); // 1 s @ 16 kHz
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = math.sin(2 * math.pi * 440.0 * i / 16000);
      }
      final frames = stftFrames(pcm, nFft: 400, hopLength: 160, melFrames: 100);
      expect(frames.length, 100);
      for (final f in frames) {
        expect(f.length, 400);
      }
    });

    test(
      'first frame is centered on sample 0 via reflect padding (not zero padding)',
      () {
        // A short DC clip: reflect-padding a constant signal reproduces the
        // same constant (unlike zero-padding, which would introduce an edge
        // discontinuity) -- the first NFT/2 samples of frame 0 mirror-image the
        // clip's own start, so for a constant signal frame 0 is uniformly 1.0
        // pre-window.
        final pcm = Float32List(16000)..fillRange(0, 16000, 1.0);
        final frames = stftFrames(pcm, nFft: 400, hopLength: 160, melFrames: 1);
        final windowed = frames[0];
        // frames[0] is already Hann-windowed (per stftFrames' contract), and
        // the periodic Hann window is exactly zero at index 0 regardless of
        // padding strategy, so index 0 can't discriminate reflect- vs
        // zero-padding. Index 100 sits inside the reflect-padded prefix
        // (indices 0..199) away from that edge zero: a zero-padded
        // implementation would show 0.0 there, while reflect-padding mirrors
        // the clip's own 1.0s into that region.
        expect(windowed[100], isNot(0.0));
      },
    );
  });
}
