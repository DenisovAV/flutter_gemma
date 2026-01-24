import 'dart:typed_data';

/// Utility class for audio format conversion.
///
/// Gemma 3n E4B requires: PCM 16kHz, 16-bit, mono
class AudioConverter {
  /// Target sample rate for Gemma 3n E4B
  static const int targetSampleRate = 16000;

  /// Bytes per sample (16-bit = 2 bytes)
  static const int bytesPerSample = 2;

  /// Convert PCM audio to 16kHz mono format.
  ///
  /// [pcmData] - Raw PCM data (16-bit signed, little-endian)
  /// [sourceSampleRate] - Original sample rate (e.g., 44100, 48000)
  /// [sourceChannels] - Number of channels (1 = mono, 2 = stereo)
  ///
  /// Returns PCM data at 16kHz, 16-bit, mono
  static Uint8List toPCM16kHzMono(
    Uint8List pcmData, {
    required int sourceSampleRate,
    int sourceChannels = 1,
  }) {
    // If already in target format, return as-is
    if (sourceSampleRate == targetSampleRate && sourceChannels == 1) {
      return pcmData;
    }

    // Convert bytes to 16-bit samples
    final samples = _bytesToSamples(pcmData);

    // Convert stereo to mono if needed
    final monoSamples = sourceChannels == 2
        ? _stereoToMono(samples)
        : samples;

    // Resample to 16kHz if needed
    final resampledSamples = sourceSampleRate != targetSampleRate
        ? _resample(monoSamples, sourceSampleRate, targetSampleRate)
        : monoSamples;

    // Convert back to bytes
    return _samplesToBytes(resampledSamples);
  }

  /// Extract raw PCM from WAV file data.
  ///
  /// Returns a record with PCM data, sample rate, and channels.
  static ({Uint8List pcmData, int sampleRate, int channels}) parseWav(
    Uint8List wavData,
  ) {
    // WAV header structure:
    // 0-3: "RIFF"
    // 4-7: file size
    // 8-11: "WAVE"
    // 12-15: "fmt "
    // 16-19: format chunk size
    // 20-21: audio format (1 = PCM)
    // 22-23: number of channels
    // 24-27: sample rate
    // 28-31: byte rate
    // 32-33: block align
    // 34-35: bits per sample
    // 36-39: "data"
    // 40-43: data chunk size
    // 44+: PCM data

    if (wavData.length < 44) {
      throw ArgumentError('Invalid WAV data: too short');
    }

    final byteData = ByteData.sublistView(wavData);

    // Verify RIFF header
    final riff = String.fromCharCodes(wavData.sublist(0, 4));
    if (riff != 'RIFF') {
      throw ArgumentError('Invalid WAV: missing RIFF header');
    }

    // Verify WAVE format
    final wave = String.fromCharCodes(wavData.sublist(8, 12));
    if (wave != 'WAVE') {
      throw ArgumentError('Invalid WAV: missing WAVE format');
    }

    // Parse format info
    final channels = byteData.getUint16(22, Endian.little);
    final sampleRate = byteData.getUint32(24, Endian.little);

    // Find data chunk (might not be at position 36)
    int dataOffset = 12;
    while (dataOffset < wavData.length - 8) {
      final chunkId = String.fromCharCodes(wavData.sublist(dataOffset, dataOffset + 4));
      final chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);

      if (chunkId == 'data') {
        final pcmStart = dataOffset + 8;
        final pcmData = wavData.sublist(pcmStart, pcmStart + chunkSize);
        return (pcmData: Uint8List.fromList(pcmData), sampleRate: sampleRate, channels: channels);
      }

      dataOffset += 8 + chunkSize;
      // Align to even byte
      if (chunkSize % 2 != 0) dataOffset++;
    }

    throw ArgumentError('Invalid WAV: data chunk not found');
  }

  /// Calculate audio duration from PCM data.
  ///
  /// [pcmData] - Raw PCM data
  /// [sampleRate] - Sample rate in Hz
  /// [channels] - Number of audio channels
  /// [bitsPerSample] - Bits per sample (default 16)
  static Duration calculateDuration(
    Uint8List pcmData, {
    required int sampleRate,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final totalSamples = pcmData.length ~/ (bytesPerSample * channels);
    final seconds = totalSamples / sampleRate;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Format duration as "mm:ss" string.
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Private helper methods

  static Int16List _bytesToSamples(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final samples = Int16List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  static Uint8List _samplesToBytes(Int16List samples) {
    final bytes = Uint8List(samples.length * 2);
    final byteData = ByteData.sublistView(bytes);
    for (var i = 0; i < samples.length; i++) {
      byteData.setInt16(i * 2, samples[i], Endian.little);
    }
    return bytes;
  }

  static Int16List _stereoToMono(Int16List stereoSamples) {
    final monoSamples = Int16List(stereoSamples.length ~/ 2);
    for (var i = 0; i < monoSamples.length; i++) {
      // Average left and right channels
      final left = stereoSamples[i * 2];
      final right = stereoSamples[i * 2 + 1];
      monoSamples[i] = ((left + right) ~/ 2).toInt();
    }
    return monoSamples;
  }

  static Int16List _resample(
    Int16List samples,
    int sourceSampleRate,
    int targetSampleRate,
  ) {
    final ratio = sourceSampleRate / targetSampleRate;
    final newLength = (samples.length / ratio).round();
    final resampled = Int16List(newLength);

    for (var i = 0; i < newLength; i++) {
      final srcIndex = (i * ratio).floor();
      final srcIndexNext = (srcIndex + 1).clamp(0, samples.length - 1);
      final fraction = (i * ratio) - srcIndex;

      // Linear interpolation
      final value = samples[srcIndex] * (1 - fraction) +
          samples[srcIndexNext] * fraction;
      resampled[i] = value.round().clamp(-32768, 32767);
    }

    return resampled;
  }
}
