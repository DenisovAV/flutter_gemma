import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gemma_speech/src/litert/log_mel_frontend.dart';
import 'package:flutter_gemma_speech/src/litert/mel_filter_assets.dart';
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

  group(
    'computeLogMelSpectrogram (golden vs Python openai-whisper reference)',
    () {
      test(
        'matches the Python reference within tolerance for a 1s 440Hz tone',
        () {
          final fixtureText = File(
            'test/fixtures/log_mel_golden_1s_440hz.json',
          ).readAsStringSync();
          final fixture = jsonDecode(fixtureText) as Map<String, dynamic>;
          final sampleRate = fixture['sampleRate'] as int;
          final n = fixture['samples'] as int;
          final toneHz = (fixture['toneHz'] as num).toDouble();
          final amplitude = (fixture['toneAmplitude'] as num).toDouble();
          final expected = (fixture['melFirstFlat'] as List)
              .map((v) => (v as num).toDouble())
              .toList();

          final pcm = Float32List(n);
          for (var i = 0; i < n; i++) {
            pcm[i] =
                amplitude * math.sin(2 * math.pi * toneHz * i / sampleRate);
          }

          final melFilters = loadMelFilterAsset('whisper_mel_80');
          final actual = computeLogMelSpectrogram(
            pcm,
            nFft: fixture['nFft'] as int,
            hopLength: fixture['hopLength'] as int,
            nMels: fixture['nMels'] as int,
            melFrames: fixture['melFrames'] as int,
            melFilters: melFilters,
            normalization: SttMelNormalization.whisper,
          );

          expect(actual.length, expected.length);
          var maxAbsDiff = 0.0;
          for (var i = 0; i < actual.length; i++) {
            final diff = (actual[i] - expected[i]).abs();
            if (diff > maxAbsDiff) maxAbsDiff = diff;
          }
          // Direct DFT vs torch's FFT + float32 vs float64 accumulation over 400
          // terms/bin; normalized values are roughly in [-1, ~1] after whisper's
          // (x+4)/4 scaling, so 1e-2 absolute is generous enough to tolerate
          // implementation-level float noise while still catching a genuinely
          // wrong STFT/filterbank/normalization (which would be off by >> 1e-2).
          expect(
            maxAbsDiff,
            lessThan(1e-2),
            reason: 'max abs diff: $maxAbsDiff',
          );
        },
      );
    },
  );
}
