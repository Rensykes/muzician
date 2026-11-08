import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/audio_rules.dart';

void main() {
  group('computePeaksFromInt16', () {
    test('downsamples to requested bin count', () {
      final samples = Int16List.fromList(List<int>.filled(1000, 32767));
      final peaks = computePeaksFromInt16(samples, targetBins: 100);
      expect(peaks.length, 100);
      expect(peaks.every((p) => p == 255), isTrue);
    });

    test('silence produces zero peaks', () {
      final samples = Int16List.fromList(List<int>.filled(1000, 0));
      final peaks = computePeaksFromInt16(samples, targetBins: 50);
      expect(peaks.every((p) => p == 0), isTrue);
    });

    test('returns at least 1 bin for non-empty input', () {
      final samples = Int16List.fromList([1000, -1000]);
      final peaks = computePeaksFromInt16(samples, targetBins: 50);
      expect(peaks, isNotEmpty);
    });
  });

  group('downmixToMono', () {
    test('averages stereo channel pairs into mono frames', () {
      // Interleaved L,R per frame: (100,200) -> 150, (-100,-300) -> -200.
      final stereo = Int16List.fromList([100, 200, -100, -300]);
      final mono = downmixToMono(stereo, 2);
      expect(mono, orderedEquals(<int>[150, -200]));
    });

    test('returns the buffer unchanged for mono input', () {
      final samples = Int16List.fromList([1, 2, 3]);
      expect(downmixToMono(samples, 1), same(samples));
    });

    test('drops a trailing partial frame (length not a channel multiple)', () {
      // 5 samples across 2 channels -> 2 full frames; the lone sample is cut.
      final stereo = Int16List.fromList([10, 20, 30, 40, 50]);
      final mono = downmixToMono(stereo, 2);
      expect(mono, orderedEquals(<int>[15, 35]));
    });

    test('empty input stays empty', () {
      expect(downmixToMono(Int16List(0), 2), isEmpty);
    });
  });
}
