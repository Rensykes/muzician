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
  });
}
