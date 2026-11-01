import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/utils/timbre_synth.dart';

void main() {
  for (final sound in [
    PianoRollSound.organ,
    PianoRollSound.synthLead,
    PianoRollSound.bell,
  ]) {
    test('${sound.name} renders a bounded, audible, fading note', () {
      final samples = TimbreSynth.render(sound, 60);
      expect(samples.length, TimbreSynth.sampleRate * 700 ~/ 1000);
      final peak = samples.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
      expect(peak, inInclusiveRange(4000, 32767));
      final tail = samples.sublist(samples.length - 200);
      expect(
        tail.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m),
        lessThan(peak ~/ 4),
      );
    });
  }

  test('rendering differs between timbres and pitches', () {
    expect(
      TimbreSynth.render(PianoRollSound.organ, 60),
      isNot(equals(TimbreSynth.render(PianoRollSound.bell, 60))),
    );
    expect(
      TimbreSynth.render(PianoRollSound.organ, 60),
      isNot(equals(TimbreSynth.render(PianoRollSound.organ, 64))),
    );
  });

  test('piano and guitar sounds are not handled by the synth', () {
    expect(
      () => TimbreSynth.render(PianoRollSound.piano, 60),
      throwsArgumentError,
    );
  });
}
