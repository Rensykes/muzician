import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/schema/rules/mono_pitch_rules.dart' as rules;

void main() {
  group('mono pitch rules', () {
    test('maps 440 Hz to MIDI 69', () {
      expect(rules.frequencyToMidi(440.0), 69);
      expect(rules.frequencyToMidi(40.0), isNull);
      expect(rules.midiToNoteLabel(69), 'A4');
    });

    test('segments one stable note and ignores a short silence gap', () {
      const frames = <PitchFrame>[
        PitchFrame(timestampMs: 0, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.8, confidence: 0.97, isSilence: false),
        PitchFrame(timestampMs: 60, frequencyHz: 440, midiNote: 69, centsOffset: 0, amplitude: 0.8, confidence: 0.97, isSilence: false),
        PitchFrame(timestampMs: 120, frequencyHz: 0, midiNote: null, centsOffset: 0, amplitude: 0.02, confidence: 0, isSilence: true),
        PitchFrame(timestampMs: 180, frequencyHz: 441, midiNote: 69, centsOffset: 3, amplitude: 0.8, confidence: 0.96, isSilence: false),
        PitchFrame(timestampMs: 240, frequencyHz: 441, midiNote: 69, centsOffset: 3, amplitude: 0.8, confidence: 0.96, isSilence: false),
      ];

      final notes = rules.segmentStableNotes(frames);

      expect(notes, hasLength(1));
      expect(notes.single.midiNote, 69);
      expect(notes.single.startMs, 0);
      expect(notes.single.endMs, 240);
    });

    test('quantizes timestamps into piano roll ticks', () {
      const notes = [
        DetectedMonoNote(startMs: 0, endMs: 260, midiNote: 69, confidence: 0.95),
      ];

      final imported = rules.quantizeNotesToTicks(
        notes: notes,
        anchorTick: 8,
        tempo: 120,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        snapTicks: 2,
      );

      expect(imported.single.startTick, 8);
      expect(imported.single.durationTicks, greaterThanOrEqualTo(2));
    });
  });
}
