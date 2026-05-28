import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/schema/rules/song_pattern_bridge_rules.dart' as bridge;

void main() {
  test('pianoRollStateFromNotePattern preserves notes and range', () {
    const pattern = NotePattern(
      id: 'pattern1',
      name: 'Lead',
      lengthTicks: 16,
      notes: [
        NotePatternNote(id: 'n1', midiNote: 60, startTick: 0, durationTicks: 4),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      snapTicks: 2,
      highlightedNotes: ['C'],
    );
    final state = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: 120,
      timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
    );
    expect(state.notes.single.midiNote, 60);
    expect(state.snapTicks, 2);
    expect(state.highlightedNotes, ['C']);
    expect(state.pitchRangeStart, 48);
  });

  test('notePatternFromPianoRollState strips derived pitch fields', () {
    final state = PianoRollState(
      config: const PianoRollConfig(
        tempo: 120,
        key: null,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 1,
      ),
      notes: const [
        PianoRollNote(
          id: 'n1',
          midiNote: 64,
          pitchClass: 'E',
          noteWithOctave: 'E4',
          startTick: 2,
          durationTicks: 6,
        ),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      selectedNoteIds: {},
      snapTicks: 4,
      highlightedNotes: ['E'],
      latestImportedRange: null,
    );
    final pattern = bridge.notePatternFromPianoRollState(
      state,
      patternId: 'pattern2',
      patternName: 'Converted',
      minimumLengthTicks: 1,
    );
    expect(pattern.notes.single.midiNote, 64);
    expect(pattern.notes.single.startTick, 2);
    expect(pattern.notes.single.durationTicks, 6);
    expect(pattern.lengthTicks, 8);
  });

  test('round-trip preserves note data', () {
    const pattern = NotePattern(
      id: 'p1',
      name: 'Test',
      lengthTicks: 16,
      notes: [
        NotePatternNote(id: 'n1', midiNote: 72, startTick: 4, durationTicks: 8),
      ],
      pitchRangeStart: 40,
      pitchRangeEnd: 90,
      snapTicks: 4,
      highlightedNotes: ['C', 'E'],
    );
    final state = bridge.pianoRollStateFromNotePattern(
      pattern,
      tempo: 140,
      timeSignature: const TimeSignature(beatsPerMeasure: 3, beatUnit: 4),
    );
    final roundTripped = bridge.notePatternFromPianoRollState(
      state,
      patternId: 'p1',
      patternName: 'Test',
      minimumLengthTicks: pattern.lengthTicks,
    );
    expect(roundTripped.notes.single.midiNote, 72);
    expect(roundTripped.notes.single.startTick, 4);
    expect(roundTripped.lengthTicks, 16);
  });

  test('preserves empty pattern length on save', () {
    final state = PianoRollState(
      config: const PianoRollConfig(
        tempo: 120,
        key: null,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 1,
      ),
      notes: const [],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      selectedNoteIds: {},
      snapTicks: 1,
      highlightedNotes: [],
      latestImportedRange: null,
    );

    final pattern = bridge.notePatternFromPianoRollState(
      state,
      patternId: 'empty',
      patternName: 'Empty',
      minimumLengthTicks: 16,
    );

    expect(pattern.lengthTicks, 16);
  });

  test('preserves trailing space when notes end before saved length', () {
    final state = PianoRollState(
      config: const PianoRollConfig(
        tempo: 120,
        key: null,
        timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 1,
      ),
      notes: const [
        PianoRollNote(
          id: 'n1',
          midiNote: 60,
          pitchClass: 'C',
          noteWithOctave: 'C4',
          startTick: 0,
          durationTicks: 4,
        ),
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      selectedNoteIds: {},
      snapTicks: 1,
      highlightedNotes: [],
      latestImportedRange: null,
    );

    final pattern = bridge.notePatternFromPianoRollState(
      state,
      patternId: 'spaced',
      patternName: 'Spaced',
      minimumLengthTicks: 16,
    );

    expect(pattern.lengthTicks, 16);
  });
}
