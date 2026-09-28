import 'dart:typed_data';

/// Wraps raw 16-bit mono PCM in the 44-byte header that makes it a `.wav`.
///
/// `synthesize` returns bare samples — numbers, with nothing saying how fast to
/// play them. A player needs to be told: one channel, [sampleRate] samples per
/// second, 16 bits each. That is all a WAV header is.
Uint8List wavFromPcm16(Uint8List pcm, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  const blockAlign = channels * bitsPerSample ~/ 8;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // "RIFF"
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x57415645) // "WAVE"
    ..setUint32(12, 0x666d7420) // "fmt "
    ..setUint32(16, 16, Endian.little) // size of the fmt chunk
    ..setUint16(20, 1, Endian.little) // 1 = uncompressed PCM
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * blockAlign, Endian.little) // bytes per second
    ..setUint16(32, blockAlign, Endian.little)
    ..setUint16(34, bitsPerSample, Endian.little)
    ..setUint32(36, 0x64617461) // "data"
    ..setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
