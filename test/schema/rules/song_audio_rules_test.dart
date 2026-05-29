import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_audio_rules.dart';

void main() {
  group('audioClipLengthTicks', () {
    const ts44 = TimeSignature(beatsPerMeasure: 4, beatUnit: 4);

    test('at 60 BPM, 4 ticks per beat, 1000 ms == 4 ticks', () {
      const cfg = SongProjectConfig(
        tempo: 60,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      const asset = AudioAsset(
        id: 'x',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), 4);
    });

    test('at 120 BPM, 1000 ms == 8 ticks', () {
      const cfg = SongProjectConfig(
        tempo: 120,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      const asset = AudioAsset(
        id: 'x',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), 8);
    });

    test('clamps to minimum of 1 tick for very short audio', () {
      const cfg = SongProjectConfig(
        tempo: 120,
        timeSignature: ts44,
        totalMeasures: 4,
      );
      const asset = AudioAsset(
        id: 'x',
        durationMs: 5,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      );
      expect(audioClipLengthTicks(asset, cfg), greaterThanOrEqualTo(1));
    });
  });

  group('audioTickToMs', () {
    test('at 60 BPM, tick 4 (4 ticks per beat) is 1000 ms', () {
      const cfg = SongProjectConfig(
        tempo: 60,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      );
      expect(audioTickToMs(4, cfg), 1000);
    });
  });

  group('computePeaksFromInt16', () {
    test('downsamples to requested bin count', () {
      final samples = Int16List.fromList(
        List<int>.filled(1000, 32767),
      );
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
}
