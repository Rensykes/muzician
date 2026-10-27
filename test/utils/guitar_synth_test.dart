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
}
