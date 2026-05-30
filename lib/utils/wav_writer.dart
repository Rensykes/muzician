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
  bytes.add(_u32(16)); // PCM fmt chunk size
  bytes.add(_u16(1)); // PCM format
  bytes.add(_u16(channels));
  bytes.add(_u32(sampleRate));
  bytes.add(_u32(byteRate));
  bytes.add(_u16(blockAlign));
  bytes.add(_u16(bitsPerSample));
  bytes.add(_ascii('data'));
  bytes.add(_u32(dataSize));
  bytes.add(
    samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes),
  );
  return bytes.toBytes();
}

/// Parses the RIFF/WAVE header of [wav] and returns the audio metadata.
///
/// Scans the RIFF chunk list rather than assuming a canonical
/// `RIFF | WAVE | fmt ` layout — the iOS `record` backend prepends `JUNK` or
/// `LIST` chunks before `fmt ` (legitimate per RIFF spec), which a strict
/// fixed-offset reader rejects.  Only PCM (and IEEE float as a passthrough on
/// the same fields) is supported.
WavHeader parseWavHeader(Uint8List wav) {
  if (wav.length < 12) {
    throw const FormatException('WAV too short');
  }
  final bd = ByteData.sublistView(wav);
  if (String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  int? dataSize;

  var cursor = 12;
  while (cursor + 8 <= wav.length) {
    final tag = String.fromCharCodes(wav.sublist(cursor, cursor + 4));
    final size = bd.getUint32(cursor + 4, Endian.little);
    final payloadStart = cursor + 8;
    if (tag == 'fmt ') {
      if (payloadStart + 16 > wav.length) {
        throw const FormatException('Truncated fmt chunk');
      }
      channels = bd.getUint16(payloadStart + 2, Endian.little);
      sampleRate = bd.getUint32(payloadStart + 4, Endian.little);
      bitsPerSample = bd.getUint16(payloadStart + 14, Endian.little);
    } else if (tag == 'data') {
      dataSize = size;
      if (sampleRate != null) break;
    }
    // RIFF chunks are word-aligned: payload is padded to an even length but
    // the size field reports the unpadded payload size.
    final padded = size + (size.isOdd ? 1 : 0);
    cursor = payloadStart + padded;
  }

  if (sampleRate == null || channels == null || bitsPerSample == null) {
    throw const FormatException('Missing fmt chunk');
  }
  if (dataSize == null) {
    throw const FormatException('Missing data chunk');
  }
  final bytesPerFrame = channels * (bitsPerSample ~/ 8);
  if (bytesPerFrame == 0 || sampleRate == 0) {
    throw const FormatException('Invalid WAV metadata');
  }
  final frames = dataSize ~/ bytesPerFrame;
  final durationMs = (frames * 1000) ~/ sampleRate;
  return WavHeader(
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
    durationMs: durationMs,
  );
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
