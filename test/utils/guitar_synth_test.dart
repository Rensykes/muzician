import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/guitar_sound.dart';
import 'package:muzician/utils/guitar_synth.dart';

List<double> samples(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  return [
    for (var i = 44; i < wav.length; i += 2)
      data.getInt16(i, Endian.little) / 32768,
  ];
}

void main() {
  for (final tone in GuitarTone.values) {
    test('${tone.name} keeps playable notes tuned across the fretboard', () {
      for (final midi in [40, 52, 64, 76, 88]) {
        final pcm = samples(GuitarSynth.renderNote(midi, tone: tone));
        final expectedPeriod =
            GuitarSynth.sampleRate / (440 * math.pow(2, (midi - 69) / 12));
        var bestLag = 0;
        var bestCorrelation = -double.infinity;
        for (
          var lag = (expectedPeriod * .9).floor();
          lag <= (expectedPeriod * 1.1).ceil();
          lag++
        ) {
          var correlation = 0.0;
          for (var i = 3000; i < 12000; i++) {
            correlation += pcm[i] * pcm[i + lag];
          }
          if (correlation > bestCorrelation) {
            bestCorrelation = correlation;
            bestLag = lag;
          }
        }
        expect(
          bestLag,
          closeTo(expectedPeriod, math.max(1, expectedPeriod * .02)),
          reason: '$tone MIDI $midi',
        );
      }
    });

    test(
      '${tone.name} chord has a bounded peak, requested gate and silent ends',
      () {
        final pcm = samples(
          GuitarSynth.renderChord(
            [40, 47, 52, 55, 59, 64],
            tone: tone,
            duration: const Duration(milliseconds: 250),
          ),
        );
        expect(pcm.length, GuitarSynth.sampleRate ~/ 4);
        expect(pcm.first, 0);
        expect(pcm.last, 0);
        expect(
          pcm.map((v) => v.abs()).reduce(math.max),
          inInclusiveRange(.05, .851),
        );
      },
    );
  }

  test(
    'distorted chord differs from clean and cache keys invalidate old WAVs',
    () {
      final clean = GuitarSynth.renderChord([40, 47, 52]);
      final distorted = GuitarSynth.renderChord([
        40,
        47,
        52,
      ], tone: GuitarTone.distorted);
      expect(distorted, isNot(clean));
      expect(GuitarSynth.noteCacheKey(40), contains('v3_clean_40'));
      expect(
        GuitarSynth.noteCacheKey(40, tone: GuitarTone.distorted),
        contains('v3_distorted_40'),
      );
    },
  );

  test(
    'simultaneous multi-lane chords retain voices beyond twelve strings',
    () {
      final firstTwelve = List<int>.filled(12, 40);
      expect(
        GuitarSynth.renderChord([...firstTwelve, 76]),
        isNot(GuitarSynth.renderChord(firstTwelve)),
      );
    },
  );

  test('strum preserves stroke offsets in its single PCM buffer', () {
    final pcm = samples(GuitarSynth.renderStrum([40, 47, 52, 55, 59, 64]));
    final expected =
        GuitarSynth.sampleRate *
        (GuitarSynth.previewDuration.inMilliseconds +
            5 * GuitarSynth.strumSpacing.inMilliseconds) ~/
        1000;
    expect(pcm.length, expected);
    expect(pcm.last, 0);
  });

  group('renderStroke', () {
    int sampleAt(int ms) => GuitarSynth.sampleRate * ms ~/ 1000;

    double energy(List<double> pcm, int fromMs, int toMs) {
      var sum = 0.0;
      for (var i = sampleAt(fromMs); i < sampleAt(toMs); i++) {
        sum += pcm[i].abs();
      }
      return sum;
    }

    test('places each string at its own onset inside one buffer', () {
      final pcm = samples(
        GuitarSynth.renderStroke(const [
          (midi: 40, onsetMs: 0, durationMs: 250),
          (midi: 47, onsetMs: 12, durationMs: 238),
          (midi: 52, onsetMs: 24, durationMs: 226),
        ]),
      );
      expect(pcm.length, sampleAt(250));
      expect(pcm.first, 0);
      expect(pcm.last, 0);
      expect(energy(pcm, 0, 12), greaterThan(0));
    });

    test('a lone late string is silent before its onset', () {
      final pcm = samples(
        GuitarSynth.renderStroke(const [
          (midi: 52, onsetMs: 24, durationMs: 100),
        ]),
      );
      expect(pcm.length, sampleAt(124));
      expect(energy(pcm, 0, 24), 0);
      expect(energy(pcm, 24, 124), greaterThan(0));
    });

    test('honors a shorter per-string duration by releasing that string', () {
      final clipped = samples(
        GuitarSynth.renderStroke(const [
          (midi: 40, onsetMs: 0, durationMs: 60),
          (midi: 64, onsetMs: 12, durationMs: 300),
        ]),
      );
      final full = samples(
        GuitarSynth.renderStroke(const [
          (midi: 40, onsetMs: 0, durationMs: 300),
          (midi: 64, onsetMs: 12, durationMs: 300),
        ]),
      );
      expect(clipped.length, full.length);
      // Identical until the clipped string's release begins.
      for (var i = 0; i < sampleAt(10); i++) {
        expect(clipped[i], closeTo(full[i], 1e-3));
      }
      expect(energy(clipped, 70, 300), lessThan(energy(full, 70, 300)));
    });

    test('is deterministic, bounded and total length is the latest end', () {
      const strings = [
        (midi: 40, onsetMs: 0, durationMs: 100),
        (midi: 47, onsetMs: 12, durationMs: 150),
        (midi: 52, onsetMs: 24, durationMs: 40),
      ];
      final wav = GuitarSynth.renderStroke(strings, tone: GuitarTone.distorted);
      expect(
        wav,
        GuitarSynth.renderStroke(strings, tone: GuitarTone.distorted),
      );
      final pcm = samples(wav);
      expect(pcm.length, sampleAt(12 + 150));
      expect(pcm.map((v) => v.abs()).reduce(math.max), lessThan(.851));
    });

    test('an empty stroke renders an empty WAV', () {
      expect(GuitarSynth.renderStroke(const []).length, 44);
    });

    test('cache key tracks tone, pitch order, onsets and durations', () {
      const strings = [
        (midi: 40, onsetMs: 0, durationMs: 100),
        (midi: 47, onsetMs: 12, durationMs: 90),
      ];
      final key = GuitarSynth.strokeCacheKey(strings);
      expect(key, contains('v3_clean'));
      expect(
        GuitarSynth.strokeCacheKey(strings, tone: GuitarTone.distorted),
        isNot(key),
      );
      expect(GuitarSynth.strokeCacheKey(strings.reversed.toList()), isNot(key));
      expect(
        GuitarSynth.strokeCacheKey([
          strings.first,
          (midi: 47, onsetMs: 12, durationMs: 80),
        ]),
        isNot(key),
      );
    });
  });
}
