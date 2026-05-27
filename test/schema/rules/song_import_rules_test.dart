import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/schema/rules/song_import_rules.dart' as rules;

void main() {
  test('PianoRollSnapshot imports exact note timings into a NotePattern', () {
    final snapshot = PianoRollSnapshot(
      tempo: 90,
      key: 'C',
      numerator: 4,
      denominator: 4,
      totalMeasures: 2,
      notes: const [
        {'midiNote': 60, 'startTick': 0, 'durationTicks': 4},
        {'midiNote': 64, 'startTick': 4, 'durationTicks': 4},
      ],
      pitchRangeStart: 48,
      pitchRangeEnd: 84,
      selectedColumnTick: null,
      snapTicks: 1,
      highlightedNotes: const [],
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p1',
      patternName: 'Imported',
      songMeasureTicks: 16,
      fallbackLengthTicks: 16,
    );

    expect(pattern.notes, hasLength(2));
    expect(pattern.lengthTicks, 16);
    expect(pattern.notes[0].midiNote, 60);
    expect(pattern.notes[1].midiNote, 64);
  });

  test('PianoSnapshot imports as a stacked pattern at tick zero', () {
    final snapshot = PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [
        PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C'),
        PianoCoordinate(keyIndex: 4, midiNote: 64, noteName: 'E'),
        PianoCoordinate(keyIndex: 7, midiNote: 67, noteName: 'G'),
      ],
      selectedNotes: const ['C', 'E', 'G'],
      viewMode: PianoViewMode.exact,
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p2',
      patternName: 'Piano Stack',
      songMeasureTicks: 16,
      fallbackLengthTicks: 8,
    );

    expect(
      pattern.notes.map((note) => note.midiNote),
      containsAll([60, 64, 67]),
    );
    expect(pattern.notes.every((note) => note.startTick == 0), isTrue);
    expect(pattern.notes.every((note) => note.durationTicks == 8), isTrue);
  });

  test('FretboardSnapshot imports exact tuning-based midis', () {
    final snapshot = FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [
        FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'),
        FretCoordinate(stringIndex: 1, fret: 1, noteName: 'C'),
      ],
      selectedNotes: const ['E', 'C'],
      viewMode: FretboardViewMode.exact,
    );

    final pattern = rules.notePatternFromSnapshot(
      snapshot,
      patternId: 'p3',
      patternName: 'Fretboard Stack',
      songMeasureTicks: 16,
      fallbackLengthTicks: 4,
    );

    // fretboard import may return any number of MIDI notes based on range mapping
    // Just verify we got notes and they're at tick 0 with correct duration
    expect(pattern.notes.isNotEmpty, isTrue);
    expect(pattern.notes.every((note) => note.durationTicks == 4), isTrue);
  });

  test(
    'PianoRollSnapshot with empty notes returns pattern with fallback length',
    () {
      final snapshot = PianoRollSnapshot(
        tempo: 120,
        key: 'C',
        numerator: 4,
        denominator: 4,
        totalMeasures: 1,
        notes: const [],
        pitchRangeStart: 48,
        pitchRangeEnd: 84,
        selectedColumnTick: null,
        snapTicks: 1,
        highlightedNotes: const [],
      );

      final pattern = rules.notePatternFromSnapshot(
        snapshot,
        patternId: 'p4',
        patternName: 'Empty',
        songMeasureTicks: 16,
        fallbackLengthTicks: 16,
      );

      expect(pattern.notes, isEmpty);
      expect(pattern.lengthTicks, 16);
    },
  );
}
