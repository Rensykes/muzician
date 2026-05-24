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
        PitchFrame(
          timestampMs: 0,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.8,
          confidence: 0.97,
          isSilence: false,
        ),
        PitchFrame(
          timestampMs: 60,
          frequencyHz: 440,
          midiNote: 69,
          centsOffset: 0,
          amplitude: 0.8,
          confidence: 0.97,
          isSilence: false,
        ),
        PitchFrame(
          timestampMs: 120,
          frequencyHz: 0,
          midiNote: null,
          centsOffset: 0,
          amplitude: 0.02,
          confidence: 0,
          isSilence: true,
        ),
        PitchFrame(
          timestampMs: 180,
          frequencyHz: 441,
          midiNote: 69,
          centsOffset: 3,
          amplitude: 0.8,
          confidence: 0.96,
          isSilence: false,
        ),
        PitchFrame(
          timestampMs: 240,
          frequencyHz: 441,
          midiNote: 69,
          centsOffset: 3,
          amplitude: 0.8,
          confidence: 0.96,
          isSilence: false,
        ),
      ];

      final notes = rules.segmentStableNotes(frames);

      expect(notes, hasLength(1));
      expect(notes.single.midiNote, 69);
      expect(notes.single.startMs, 0);
      expect(notes.single.endMs, 240);
    });

    test('quantizes timestamps into piano roll ticks', () {
      const notes = [
        DetectedMonoNote(
          startMs: 0,
          endMs: 260,
          midiNote: 69,
          confidence: 0.95,
        ),
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

    test(
      'trims overlapping imported hum notes into a monophonic two-note sequence',
      () {
        final imported = [
          const QuantizedHumNote(
            midiNote: 69,
            startTick: 8,
            durationTicks: 4,
          ),
          const QuantizedHumNote(
            midiNote: 71,
            startTick: 10,
            durationTicks: 4,
          ),
        ];

        final normalized = rules.normalizeQuantizedHumNotesMonophonically(
          imported,
        );

        expect(normalized, hasLength(2));
        expect(normalized[0].midiNote, 69);
        expect(normalized[0].startTick, 8);
        expect(normalized[0].durationTicks, 2);
        expect(normalized[1].midiNote, 71);
        expect(normalized[1].startTick, 10);
        expect(normalized[1].durationTicks, 4);
      },
    );

    test(
      'drops the earlier imported hum note when two notes quantize to the same tick',
      () {
        final imported = [
          const QuantizedHumNote(
            midiNote: 69,
            startTick: 12,
            durationTicks: 2,
          ),
          const QuantizedHumNote(
            midiNote: 71,
            startTick: 12,
            durationTicks: 3,
          ),
        ];

        final normalized = rules.normalizeQuantizedHumNotesMonophonically(
          imported,
        );

        expect(normalized, hasLength(1));
        expect(normalized.single.midiNote, 71);
        expect(normalized.single.startTick, 12);
        expect(normalized.single.durationTicks, 3);
      },
    );

    test(
      'sorts imported hum notes by start tick before monophonic normalization',
      () {
        final imported = [
          const QuantizedHumNote(
            midiNote: 71,
            startTick: 10,
            durationTicks: 4,
          ),
          const QuantizedHumNote(
            midiNote: 69,
            startTick: 8,
            durationTicks: 4,
          ),
        ];

        final normalized = rules.normalizeQuantizedHumNotesMonophonically(
          imported,
        );

        expect(normalized, hasLength(2));
        expect(normalized[0].midiNote, 69);
        expect(normalized[0].startTick, 8);
        expect(normalized[0].durationTicks, 2);
        expect(normalized[1].midiNote, 71);
        expect(normalized[1].startTick, 10);
        expect(normalized[1].durationTicks, 4);
      },
    );
  });
}
