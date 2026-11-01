import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/guitar_sound.dart';
import 'package:muzician/utils/guitar_synth.dart';
import 'package:muzician/utils/playback_voice_spec.dart';

void main() {
  const strings = [
    (midi: 40, onsetMs: 0, durationMs: 250),
    (midi: 47, onsetMs: 12, durationMs: 238),
    (midi: 52, onsetMs: 24, durationMs: 100),
  ];

  group('guitar stroke', () {
    test('uses the synth stroke key and spans to the latest string end', () {
      final spec = PlaybackVoiceSpec.guitarStroke(
        strings,
        guitarTone: GuitarTone.distorted,
      );
      expect(spec.kind, PlaybackVoiceKind.guitarStroke);
      expect(
        spec.cacheKey,
        GuitarSynth.strokeCacheKey(strings, tone: GuitarTone.distorted),
      );
      expect(spec.durationMs, 250);
      expect(spec.strokeStrings, strings);
    });

    test('equal strokes are equal and differing ones are not', () {
      PlaybackVoiceSpec spec(List<GuitarStrokeString> s, GuitarTone tone) =>
          PlaybackVoiceSpec.guitarStroke(s, guitarTone: tone);
      expect(
        spec(strings, GuitarTone.clean),
        spec([...strings], GuitarTone.clean),
      );
      expect(
        spec(strings, GuitarTone.clean),
        isNot(spec(strings, GuitarTone.distorted)),
      );
      expect(
        spec(strings, GuitarTone.clean),
        isNot(spec(strings.reversed.toList(), GuitarTone.clean)),
      );
    });

    test('latest end wins over the last string when durations differ', () {
      final spec = PlaybackVoiceSpec.guitarStroke(const [
        (midi: 40, onsetMs: 0, durationMs: 300),
        (midi: 47, onsetMs: 12, durationMs: 50),
      ], guitarTone: GuitarTone.clean);
      expect(spec.durationMs, 300);
    });
  });
}
