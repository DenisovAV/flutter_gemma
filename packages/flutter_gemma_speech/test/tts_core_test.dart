// Pure-Dart coverage of TtsCore's non-native helper math: searchSortedRight
// (Glow-TTS length-regulator lookup), tSin (CFM decoder timestep embedding),
// and nextGaussian's determinism under a fixed seed. No native FFI call is
// made anywhere in this file (TtsCore.load/LiteRtBindings.open are never
// invoked) — mirrors stt_pipeline_test.dart's "no native in unit tests"
// constraint. These pin the exact values ported from `matcha_synth.dart` so
// a future refactor can't silently drift the math the Phase-3 golden
// depends on.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gemma_speech/src/litert/tts_core.dart'
    show nextGaussian, searchSortedRight, tSin, ttsCfmSeed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('searchSortedRight', () {
    test('finds the leftmost bucket where cum[i-1] <= v < cum[i]', () {
      final cum = Float64List.fromList([1.0, 3.0, 3.0, 6.0, 10.0]);
      expect(searchSortedRight(cum, 0.0), 0);
      expect(searchSortedRight(cum, 1.0), 1);
      expect(searchSortedRight(cum, 2.5), 1);
      // Ties (3.0 appears twice) land past both equal entries — side='right'.
      expect(searchSortedRight(cum, 3.0), 3);
      expect(searchSortedRight(cum, 9.9), 4);
    });

    test('a value at or past the last cumulative sum returns length', () {
      final cum = Float64List.fromList([2.0, 4.0]);
      expect(searchSortedRight(cum, 4.0), 2);
      expect(searchSortedRight(cum, 100.0), 2);
    });

    test('a value below the first bucket returns 0', () {
      final cum = Float64List.fromList([5.0, 8.0]);
      expect(searchSortedRight(cum, -1.0), 0);
    });
  });

  group('tSin', () {
    test('default half=80 produces a length-160 embedding', () {
      final emb = tSin(0.0);
      expect(emb.length, 160);
    });

    test('t=0.0: sin half is all zeros, cos half is all ones', () {
      final emb = tSin(0.0, half: 4);
      expect(emb.length, 8);
      for (var i = 0; i < 4; i++) {
        expect(emb[i], closeTo(0.0, 1e-9));
      }
      for (var i = 4; i < 8; i++) {
        expect(emb[i], closeTo(1.0, 1e-9));
      }
    });

    test('first sin/cos pair matches the raw sinusoid at t=1.0', () {
      // half=80: e[0] = 1000 * t * exp(0) = 1000 * t.
      final emb = tSin(1.0);
      expect(emb[0], closeTo(math.sin(1000.0), 1e-6));
      expect(emb[80], closeTo(math.cos(1000.0), 1e-6));
    });
  });

  group('nextGaussian', () {
    test('ttsCfmSeed is the documented fixed seed', () {
      expect(ttsCfmSeed, 1234);
    });

    test('is deterministic: same seed produces the same sequence', () {
      final a = math.Random(ttsCfmSeed);
      final b = math.Random(ttsCfmSeed);
      final seqA = List.generate(20, (_) => nextGaussian(a));
      final seqB = List.generate(20, (_) => nextGaussian(b));
      expect(seqA, seqB);
    });

    test('produces finite, non-constant samples', () {
      final rnd = math.Random(ttsCfmSeed);
      final samples = List.generate(50, (_) => nextGaussian(rnd));
      expect(samples.every((s) => s.isFinite), isTrue);
      expect(samples.toSet().length, greaterThan(1));
    });
  });
}
