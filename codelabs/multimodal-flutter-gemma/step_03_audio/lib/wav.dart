import 'dart:typed_data';

/// Wraps raw little-endian PCM16 samples in the 44-byte RIFF/WAVE header the
/// model's audio front end expects.
///
/// Why this exists at all: `record` can write a `.wav` file for you, but only
/// to a path — and getting a writable path on every platform means
/// `path_provider`, which imports `dart:io` and therefore cannot be compiled
/// for the web. `startStream` hands the samples straight to Dart instead, so
/// the clip never touches disk and the same code compiles on all six
/// platforms. The price is these forty-four bytes.
Uint8List wavFromPcm16(
  Uint8List pcm, {
  required int sampleRate,
  required int channels,
}) {
  const bitsPerSample = 16;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final byteRate = sampleRate * blockAlign;

  // A 16-bit sample is two bytes, and a RIFF data chunk is word-aligned, so a
  // trailing half sample is not representable. The recorder should never hand
  // one over, but a stream cut mid-sample would, and a header that claims a
  // length the data does not have is worse than a clip one sample shorter.
  if (pcm.length % blockAlign != 0) {
    pcm = Uint8List.sublistView(pcm, 0, pcm.length - pcm.length % blockAlign);
  }

  final header = ByteData(44);
  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      header.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  // Everything after this field: 44 - 8 header bytes, plus the samples.
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk length
  header.setUint16(20, 1, Endian.little); // 1 = uncompressed PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);

  return Uint8List(44 + pcm.length)
    ..setRange(0, 44, header.buffer.asUint8List())
    ..setRange(44, 44 + pcm.length, pcm);
}
