// Pure-Dart, deterministic whisper-style log-mel spectrogram frontend. Every
// parameter (nFft, hopLength, nMels, melFrames) comes from the profile — this
// file has no whisper-specific constants, so a future log-mel family
// (parakeet) can reuse it with different sizes. `nFft=400` is not a power of
// two (400 = 2^4*5^2), so this uses a direct DFT rather than a radix-2 FFT —
// see docs/superpowers/notes/whisper-stt-spike-findings.md for the measured
// performance; swap to a mixed-radix/Bluestein FFT only if that is
// unacceptable (YAGNI per the design spec).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Periodic Hann window of length [n] (matches `torch.hann_window(n)`'s
/// default `periodic=True`, the convention whisper's log-mel export uses):
/// `w[i] = 0.5 - 0.5*cos(2*pi*i/n)`.
Float32List applyHannWindow(Float32List frame) {
  final n = frame.length;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
    out[i] = frame[i] * w;
  }
  return out;
}

/// Direct DFT power spectrum `|X_k|^2` for `k` in `0..nFft/2` (the
/// non-redundant half of a real-input FFT, matching the mel filterbank's
/// `[nMels, nFft/2+1]` shape). O(nFft * nFft/2) per frame — acceptable at
/// whisper's `nFft=400`; see the file header for the FFT-swap escape hatch.
Float32List powerSpectrum(Float32List windowedFrame, int nFft) {
  final nBins = nFft ~/ 2 + 1;
  final power = Float32List(nBins);
  for (var k = 0; k < nBins; k++) {
    var re = 0.0, im = 0.0;
    final angleStep = -2 * math.pi * k / nFft;
    for (var t = 0; t < nFft; t++) {
      final angle = angleStep * t;
      re += windowedFrame[t] * math.cos(angle);
      im += windowedFrame[t] * math.sin(angle);
    }
    power[k] = re * re + im * im;
  }
  return power;
}

int _reflectIndex(int i, int n) {
  if (i < 0) return -i;
  if (i >= n) return 2 * (n - 1) - i;
  return i;
}

/// Reflect-pads [x] by [padAmount] samples on both sides (numpy/torch
/// 'reflect' mode: mirrors around the edge sample without repeating it).
/// Safe for a single reflection as long as `padAmount < x.length`, which
/// holds for every profile this frontend supports (`nFft/2=200 << 480000`).
Float32List _reflectPad(Float32List x, int padAmount) {
  final n = x.length;
  final out = Float32List(n + 2 * padAmount);
  for (var i = -padAmount; i < n + padAmount; i++) {
    out[i + padAmount] = x[_reflectIndex(i, n)];
  }
  return out;
}

/// Frame [paddedPcm] into exactly [melFrames] Hann-windowed windows of
/// length [nFft], hopping by [hopLength], center-aligned via reflect
/// padding of `nFft~/2` on both sides (matches `torch.stft(..., center=
/// True)`, which whisper's log-mel export uses). `torch.stft` yields
/// `1 + paddedPcm.length/hopLength` frames; whisper's export drops the
/// LAST one (`stft[..., :-1]`) to land exactly on [melFrames] — this
/// function returns only the kept [melFrames], already windowed.
List<Float32List> stftFrames(
  Float32List paddedPcm, {
  required int nFft,
  required int hopLength,
  required int melFrames,
}) {
  final padded = _reflectPad(paddedPcm, nFft ~/ 2);
  final frames = <Float32List>[];
  for (var f = 0; f < melFrames; f++) {
    final base = f * hopLength;
    final raw = Float32List.sublistView(padded, base, base + nFft);
    frames.add(applyHannWindow(raw));
  }
  return frames;
}
