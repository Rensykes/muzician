/// Minimal WAV PCM 16-bit utilities.  Used by the audio recorder when
/// finalising a take, and by the repository when probing imported files.
library;

import 'dart:typed_data';

class WavHeader {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int durationMs;

  const WavHeader({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.durationMs,
  });
}

/// Wraps mono PCM 16-bit samples in a canonical RIFF/WAVE container.
Uint8List writeWavPcm16Mono(Int16List samples, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;

  final bytes = BytesBuilder();
  bytes.add(_ascii('RIFF'));
  bytes.add(_u32(fileSize));
  bytes.add(_ascii('WAVE'));
  bytes.add(_ascii('fmt '));
  bytes.add(_u32(16));            // PCM fmt chunk size
  bytes.add(_u16(1));             // PCM format
  bytes.add(_u16(channels));
  bytes.add(_u32(sampleRate));
  bytes.add(_u32(byteRate));
  bytes.add(_u16(blockAlign));
  bytes.add(_u16(bitsPerSample));
  bytes.add(_ascii('data'));
  bytes.add(_u32(dataSize));
  bytes.add(samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  ));
  return bytes.toBytes();
}

/// Parses the RIFF/WAVE header at the start of [wav] and returns the audio
/// metadata.  Only PCM is supported (most recordings from `record` are PCM).
WavHeader parseWavHeader(Uint8List wav) {
  if (wav.length < 44) {
    throw const FormatException('WAV too short');
  }
  final bd = ByteData.sublistView(wav);
  if (String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }
  if (String.fromCharCodes(wav.sublist(12, 16)) != 'fmt ') {
    throw const FormatException('Missing fmt chunk at canonical offset');
  }
  final channels = bd.getUint16(22, Endian.little);
  final sampleRate = bd.getUint32(24, Endian.little);
  final bitsPerSample = bd.getUint16(34, Endian.little);

  var cursor = 36;
  while (cursor + 8 <= wav.length) {
    final tag = String.fromCharCodes(wav.sublist(cursor, cursor + 4));
    final size = bd.getUint32(cursor + 4, Endian.little);
    if (tag == 'data') {
      final bytesPerFrame = channels * (bitsPerSample ~/ 8);
      if (bytesPerFrame == 0 || sampleRate == 0) {
        throw const FormatException('Invalid WAV metadata');
      }
      final frames = size ~/ bytesPerFrame;
      final durationMs = (frames * 1000) ~/ sampleRate;
      return WavHeader(
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
        durationMs: durationMs,
      );
    }
    cursor += 8 + size;
  }
  throw const FormatException('Missing data chunk');
}

List<int> _ascii(String s) => s.codeUnits;

List<int> _u16(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
