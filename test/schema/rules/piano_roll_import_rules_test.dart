import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/schema/rules/piano_roll_import_rules.dart';

void main() {
  // ── bestMidiInRangeForPitchClass ──────────────────────────────────────────

  group('bestMidiInRangeForPitchClass', () {
    test('finds closest C in range centred on middle', () {
      // pc=0 (C), range 48-60, centre 54 → C3(48) dist 6, C4(60) dist 6 → pick 48
      final result = bestMidiInRangeForPitchClass(0, 48, 60);
      expect(result, 48);
    });

    test('finds closest E when anchor is below', () {
      // pc=4 (E), range 48-60, centre 54 → E3(52) dist 2, E4(64 out of range) → 52
      final result = bestMidiInRangeForPitchClass(4, 48, 60);
      expect(result, 52);
    });

    test('returns null when pitch class is not in range', () {
      // pc=4 (E), range 53-54 → no E in this narrow range → null
      final result = bestMidiInRangeForPitchClass(4, 53, 54);
      expect(result, isNull);
    });

    test('centers around explicit anchor when provided', () {
      // pc=0 (C), range 48-72, anchor 72 → closest to C5(72) is 72
      final result = bestMidiInRangeForPitchClass(0, 48, 72, anchor: 72);
      expect(result, 72);
    });

    test('works at bottom of MIDI range', () {
      final result = bestMidiInRangeForPitchClass(0, 21, 30);
      expect(result, 24); // C1 = 24
    });
  });

  // ── buildChordStackMidis ──────────────────────────────────────────────────

  group('buildChordStackMidis', () {
    test('C major triad centres around C4', () {
      // G3 (55) is closer to anchor 60 than G4 (67)
      final midis = buildChordStackMidis('C', '', 60, 48, 72);
      expect(midis, [60, 64, 55]); // C4 E4 G3
    });

    test('Cm7 centres around C3', () {
      // G2(43) closer to 48 than G3(55), Bb2(46) closer than Bb3(58)
      final midis = buildChordStackMidis('C', 'm7', 48, 36, 60);
      expect(midis, [48, 51, 43, 46]); // C3 Eb3 G2 Bb2
    });

    test('returns empty when root is unknown', () {
      final midis = buildChordStackMidis('Z', '', 60, 48, 72);
      expect(midis, isEmpty);
    });

    test('returns empty when quality is unknown', () {
      final midis = buildChordStackMidis('C', 'unknown', 60, 48, 72);
      expect(midis, isEmpty);
    });

    test('dim7 chord with wide voicing', () {
      // Gb → 54 is encountered before 66 (tie dist 6 to anchor 60)
      final midis = buildChordStackMidis('C', 'dim7', 60, 48, 84);
      expect(midis, [60, 63, 54, 57]); // C4 Eb4 Gb3 A3
    });

    test('add9 chord (octave-spanning interval)', () {
      // add9 = [0, 4, 7, 14] — 14 mod 12 = 2 → D
      // G3(55) closer to 60 than G4(67), D3(62) closer than D2(50)
      final midis = buildChordStackMidis('C', 'add9', 60, 48, 84);
      expect(midis, [60, 64, 55, 62]); // C4 E4 G3 D3
    });
  });

  // ── extractSnapshotImportMidis - exact mode (FretboardSnapshot) ───────────

  group('extractSnapshotImportMidis - exact FretboardSnapshot', () {
    test('extracts exact MIDI from fretboard cells within range', () {
      // Standard tuning E2(40) A2(45) D3(50) G3(55) B3(59) E4(64)
      // Fretted at fret 0 (open) gives those MIDI values exactly
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [
          const FretCoordinate(
            stringIndex: 5,
            fret: 0,
            noteName: 'E',
          ), // low E → 40
          const FretCoordinate(
            stringIndex: 4,
            fret: 0,
            noteName: 'A',
          ), // A → 45
          const FretCoordinate(
            stringIndex: 3,
            fret: 0,
            noteName: 'D',
          ), // D → 50
        ],
        selectedNotes: ['E', 'A', 'D'],
        viewMode: FretboardViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 40,
        hi: 60,
      );
      expect(midis, [40, 45, 50]);
    });

    test('filters out cells with MIDI outside range', () {
      // high E at fret 0 = 64, outside 40-60 range
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [
          const FretCoordinate(stringIndex: 5, fret: 0, noteName: 'E'), // 40
          const FretCoordinate(stringIndex: 0, fret: 0, noteName: 'E'), // 64
        ],
        selectedNotes: ['E'],
        viewMode: FretboardViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 40,
        hi: 60,
      );
      expect(midis, [40]);
    });

    test('returns empty for unknown tuning', () {
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [
          const FretCoordinate(stringIndex: 99, fret: 0, noteName: 'C'),
        ],
        selectedNotes: ['C'],
        viewMode: FretboardViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 21,
        hi: 108,
      );
      expect(midis, isEmpty);
    });

    test('returns empty for empty cells', () {
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [],
        selectedNotes: [],
        viewMode: FretboardViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 21,
        hi: 108,
      );
      expect(midis, isEmpty);
    });
  });

  // ── extractSnapshotImportMidis - exact mode (PianoSnapshot) ───────────────

  group('extractSnapshotImportMidis - exact PianoSnapshot', () {
    test('extracts exact MIDI from piano keys within range', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: [
          const PianoCoordinate(keyIndex: 0, midiNote: 60, noteName: 'C'),
          const PianoCoordinate(keyIndex: 4, midiNote: 64, noteName: 'E'),
          const PianoCoordinate(keyIndex: 7, midiNote: 67, noteName: 'G'),
        ],
        selectedNotes: ['C', 'E', 'G'],
        viewMode: PianoViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 48,
        hi: 72,
      );
      expect(midis, [60, 64, 67]);
    });

    test('filters out keys outside range', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key88,
        selectedKeys: [
          const PianoCoordinate(keyIndex: 0, midiNote: 36, noteName: 'C'),
          const PianoCoordinate(keyIndex: 1, midiNote: 60, noteName: 'C'),
        ],
        selectedNotes: ['C'],
        viewMode: PianoViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 50,
        hi: 72,
      );
      expect(midis, [60]); // 36 is filtered out
    });

    test('returns empty for empty keys', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: [],
        selectedNotes: [],
        viewMode: PianoViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: true,
        lo: 21,
        hi: 108,
      );
      expect(midis, isEmpty);
    });
  });

  // ── extractSnapshotImportMidis - pitch-class mode ─────────────────────────

  group('extractSnapshotImportMidis - pitch-class mode', () {
    test('maps unique pitch classes to nearest MIDI in range', () {
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [],
        selectedNotes: ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: false,
        lo: 48,
        hi: 72,
      );
      // C=0, E=4, G=7. Range 48-72, centre 60.
      // Closest to 60: C=60, E=64, G=55 (G3 closer than G4)
      expect(midis, [60, 64, 55]);
    });

    test('returns empty for snap with no selected notes', () {
      final snap = PianoSnapshot(
        currentRange: PianoRangeName.key61,
        selectedKeys: [],
        selectedNotes: [],
        viewMode: PianoViewMode.exact,
      );

      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: false,
        lo: 21,
        hi: 108,
      );
      expect(midis, isEmpty);
    });

    test('skips pitch classes not available in range', () {
      final snap = FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: [],
        selectedNotes: ['C', 'F#'],
        viewMode: FretboardViewMode.exact,
      );

      // Range 60-61: only MIDI 60=C4 and 61=C#4. F#6 not in this narrow range.
      final midis = extractSnapshotImportMidis(
        snap,
        exactPitchClassMode: false,
        lo: 60,
        hi: 61,
      );
      expect(midis, [60]); // only C is available
    });
  });
}
