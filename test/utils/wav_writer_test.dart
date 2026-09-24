import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  group('WAV writer', () {
    test('writeWavPcm16Mono produces a parseable header', () {
      final samples = Int16List.fromList(List<int>.filled(44100, 0));
      final bytes = writeWavPcm16Mono(samples, sampleRate: 44100);

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

      final header = parseWavHeader(bytes);
      expect(header.sampleRate, 44100);
      expect(header.channels, 1);
      expect(header.bitsPerSample, 16);
      expect(header.durationMs, 1000);
    });

    test('parseWavHeader rejects non-WAV bytes', () {
      final bogus = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      expect(() => parseWavHeader(bogus), throwsA(isA<FormatException>()));
    });

    test('parseWavHeader tolerates a JUNK chunk before fmt', () {
      // Mirrors the layout the iOS `record` backend produces: a JUNK
      // alignment-pad chunk between `WAVE` and `fmt `.  A strict fixed-offset
      // reader would reject this.
      final samples = Int16List.fromList(List<int>.filled(4410, 0));
      final canonical = writeWavPcm16Mono(samples, sampleRate: 44100);

      const junkPayloadSize = 36;
      final junk = BytesBuilder();
      junk.add(canonical.sublist(0, 12)); // RIFF | size | WAVE
      junk.add('JUNK'.codeUnits);
      final junkSize = ByteData(4)
        ..setUint32(0, junkPayloadSize, Endian.little);
      junk.add(junkSize.buffer.asUint8List());
      junk.add(List<int>.filled(junkPayloadSize, 0));
      junk.add(canonical.sublist(12)); // remaining fmt + data chunks

      final header = parseWavHeader(junk.toBytes());
      expect(header.sampleRate, 44100);
      expect(header.channels, 1);
      expect(header.bitsPerSample, 16);
      expect(header.durationMs, 100);
    });

    test('parseWavHeader handles odd-sized chunk padding', () {
      // RIFF requires payloads to be word-aligned: an odd-sized chunk is
      // followed by a single pad byte that is not counted by the size field.
      final samples = Int16List.fromList(List<int>.filled(4410, 0));
      final canonical = writeWavPcm16Mono(samples, sampleRate: 44100);

      const oddPayloadSize = 7;
      final padded = BytesBuilder();
      padded.add(canonical.sublist(0, 12));
      padded.add('JUNK'.codeUnits);
      final junkSize = ByteData(4)..setUint32(0, oddPayloadSize, Endian.little);
      padded.add(junkSize.buffer.asUint8List());
      padded.add(List<int>.filled(oddPayloadSize, 0));
      padded.add(<int>[0]); // pad byte
      padded.add(canonical.sublist(12));

      final header = parseWavHeader(padded.toBytes());
      expect(header.sampleRate, 44100);
      expect(header.durationMs, 100);
    });

    test('strict PCM16 parser returns the sample payload location', () {
      final source = Int16List.fromList([0, 1200, -2300]);
      final bytes = writeWavPcm16Mono(source, sampleRate: 44100);
      final data = parsePcm16Wav(bytes);

      expect(data.sampleRate, 44100);
      expect(data.channels, 1);
      expect(data.frameCount, 3);
      expect(decodePcm16Samples(bytes, data), source);
    });

    test(
      'strict PCM16 parser rejects invalid format metadata and RIFF sizes',
      () {
        final source = Int16List.fromList([0, 1200]);
        final canonical = writeWavPcm16Mono(source, sampleRate: 44100);

        final compressed = Uint8List.fromList(canonical);
        ByteData.sublistView(compressed).setUint16(20, 3, Endian.little);
        expect(() => parsePcm16Wav(compressed), throwsFormatException);

        final invalidRate = Uint8List.fromList(canonical);
        ByteData.sublistView(invalidRate).setUint32(24, 7999, Endian.little);
        expect(() => parsePcm16Wav(invalidRate), throwsFormatException);

        final invalidChannels = Uint8List.fromList(canonical);
        ByteData.sublistView(invalidChannels).setUint16(22, 3, Endian.little);
        expect(() => parsePcm16Wav(invalidChannels), throwsFormatException);

        final invalidLength = Uint8List.fromList(canonical);
        ByteData.sublistView(invalidLength).setUint32(4, 0, Endian.little);
        expect(() => parsePcm16Wav(invalidLength), throwsFormatException);
      },
    );
  });
}
