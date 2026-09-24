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

/// Validated location and format information for a little-endian PCM16 WAV.
class Pcm16WavData {
  final int sampleRate;
  final int channels;
  final int dataOffset;
  final int dataLength;
  final int frameCount;

  const Pcm16WavData({
    required this.sampleRate,
    required this.channels,
    required this.dataOffset,
    required this.dataLength,
    required this.frameCount,
  });

  int get durationMs => (frameCount * 1000) ~/ sampleRate;
}

/// Parses a strict PCM16 RIFF/WAVE file for offline mixdown.
///
/// Unlike [parseWavHeader], this validates the format tag, channel count,
/// sample rate, block alignment, byte rate, chunk bounds, and RIFF length.
/// RIFF chunks before and after `fmt ` / `data` are accepted when well formed.
Pcm16WavData parsePcm16Wav(
  Uint8List wav, {
  int minSampleRate = 8000,
  int maxSampleRate = 96000,
}) {
  if (wav.length < 12) throw const FormatException('WAV is too short');
  final bd = ByteData.sublistView(wav);
  if (_readAscii(wav, 0, 4) != 'RIFF' || _readAscii(wav, 8, 4) != 'WAVE') {
    throw const FormatException('Expected a RIFF/WAVE file');
  }

  final riffEnd = 8 + bd.getUint32(4, Endian.little);
  if (riffEnd != wav.length || riffEnd < 12) {
    throw const FormatException('RIFF length does not match the file');
  }

  int? sampleRate;
  int? channels;
  int? byteRate;
  int? blockAlign;
  int? formatTag;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;
  var cursor = 12;
  while (cursor < riffEnd) {
    if (cursor + 8 > riffEnd) {
      throw const FormatException('Truncated WAV chunk header');
    }
    final tag = _readAscii(wav, cursor, 4);
    final size = bd.getUint32(cursor + 4, Endian.little);
    final payloadStart = cursor + 8;
    final payloadEnd = payloadStart + size;
    if (payloadEnd > riffEnd) {
      throw const FormatException('WAV chunk exceeds the RIFF boundary');
    }

    if (tag == 'fmt ') {
      if (formatTag != null) {
        throw const FormatException('WAV has multiple fmt chunks');
      }
      if (size < 16) throw const FormatException('Truncated fmt chunk');
      formatTag = bd.getUint16(payloadStart, Endian.little);
      channels = bd.getUint16(payloadStart + 2, Endian.little);
      sampleRate = bd.getUint32(payloadStart + 4, Endian.little);
      byteRate = bd.getUint32(payloadStart + 8, Endian.little);
      blockAlign = bd.getUint16(payloadStart + 12, Endian.little);
      bitsPerSample = bd.getUint16(payloadStart + 14, Endian.little);
    } else if (tag == 'data') {
      if (dataOffset != null) {
        throw const FormatException('WAV has multiple data chunks');
      }
      dataOffset = payloadStart;
      dataLength = size;
    }

    final nextChunk = payloadEnd + (size.isOdd ? 1 : 0);
    if (nextChunk > riffEnd) {
      throw const FormatException(
        'WAV chunk padding exceeds the RIFF boundary',
      );
    }
    cursor = nextChunk;
  }

  if (formatTag == null || sampleRate == null || channels == null) {
    throw const FormatException('WAV is missing its fmt chunk');
  }
  if (dataOffset == null || dataLength == null) {
    throw const FormatException('WAV is missing its data chunk');
  }
  if (formatTag != 1 || bitsPerSample != 16) {
    throw const FormatException('WAV must use uncompressed PCM16 audio');
  }
  if (channels != 1 && channels != 2) {
    throw const FormatException('WAV must have one or two channels');
  }
  if (sampleRate < minSampleRate || sampleRate > maxSampleRate) {
    throw FormatException(
      'WAV sample rate must be between $minSampleRate and $maxSampleRate Hz',
    );
  }
  final expectedBlockAlign = channels * 2;
  if (blockAlign != expectedBlockAlign ||
      byteRate != sampleRate * expectedBlockAlign) {
    throw const FormatException('WAV block alignment or byte rate is invalid');
  }
  if (dataLength % expectedBlockAlign != 0) {
    throw const FormatException('WAV data does not contain complete frames');
  }

  return Pcm16WavData(
    sampleRate: sampleRate,
    channels: channels,
    dataOffset: dataOffset,
    dataLength: dataLength,
    frameCount: dataLength ~/ expectedBlockAlign,
  );
}

/// Decodes validated interleaved PCM16 samples from [wav].
Int16List decodePcm16Samples(Uint8List wav, Pcm16WavData data) {
  final sampleCount = data.frameCount * data.channels;
  final out = Int16List(sampleCount);
  final view = ByteData.sublistView(wav);
  for (var i = 0; i < sampleCount; i++) {
    out[i] = view.getInt16(data.dataOffset + i * 2, Endian.little);
  }
  return out;
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

String _readAscii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

List<int> _u16(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
