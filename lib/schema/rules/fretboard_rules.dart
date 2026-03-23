/// Fretboard Schema Rules
/// Validation logic, tuning presets, and note calculation helpers.
library;

import '../../models/fretboard.dart';

// ─── Chromatic Scales ─────────────────────────────────────────────────────────

const chromaticSharp = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

const chromaticFlat = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

const positionMarkerFrets = [3, 5, 7, 9, 12];
const doubleMarkerFret = 12;

// ─── Note Helpers ─────────────────────────────────────────────────────────────

String getPitchClassAtFret(int openMidi, int fret) {
  final midi = openMidi + fret;
  final pc = ((midi % 12) + 12) % 12;
  return chromaticSharp[pc];
}

String getNoteWithOctaveAtFret(int openMidi, int fret) {
  final midi = openMidi + fret;
  final octave = (midi ~/ 12) - 1;
  final pc = ((midi % 12) + 12) % 12;
  return '${chromaticSharp[pc]}$octave';
}

bool isNaturalNote(String noteName) {
  return !noteName.contains('#') && !noteName.contains('b');
}

bool isValidPitchClass(String note) {
  return chromaticSharp.contains(note) || chromaticFlat.contains(note);
}

// ─── Tunings ──────────────────────────────────────────────────────────────────

final tunings = <TuningName, Tuning>{
  // Standard
  TuningName.standard: Tuning(
    name: TuningName.standard,
    displayName: 'EADGBE',
    category: TuningCategory.standard,
    strings: [
      StringTuning(stringNumber: 1, note: 'E4', midiNote: 64),
      StringTuning(stringNumber: 2, note: 'B3', midiNote: 59),
      StringTuning(stringNumber: 3, note: 'G3', midiNote: 55),
      StringTuning(stringNumber: 4, note: 'D3', midiNote: 50),
      StringTuning(stringNumber: 5, note: 'A2', midiNote: 45),
      StringTuning(stringNumber: 6, note: 'E2', midiNote: 40),
    ],
  ),
  TuningName.dropD: Tuning(
    name: TuningName.dropD,
    displayName: 'Drop D',
    category: TuningCategory.standard,
    strings: [
      StringTuning(stringNumber: 1, note: 'E4', midiNote: 64),
      StringTuning(stringNumber: 2, note: 'B3', midiNote: 59),
      StringTuning(stringNumber: 3, note: 'G3', midiNote: 55),
      StringTuning(stringNumber: 4, note: 'D3', midiNote: 50),
      StringTuning(stringNumber: 5, note: 'A2', midiNote: 45),
      StringTuning(stringNumber: 6, note: 'D2', midiNote: 38),
    ],
  ),
  // Metal
  TuningName.ebStandard: Tuning(
    name: TuningName.ebStandard,
    displayName: 'Eb Standard',
    category: TuningCategory.metal,
    strings: [
      StringTuning(stringNumber: 1, note: 'Eb4', midiNote: 63),
      StringTuning(stringNumber: 2, note: 'Bb3', midiNote: 58),
      StringTuning(stringNumber: 3, note: 'Gb3', midiNote: 54),
      StringTuning(stringNumber: 4, note: 'Db3', midiNote: 49),
      StringTuning(stringNumber: 5, note: 'Ab2', midiNote: 44),
      StringTuning(stringNumber: 6, note: 'Eb2', midiNote: 39),
    ],
  ),
  TuningName.dStandard: Tuning(
    name: TuningName.dStandard,
    displayName: 'D Standard',
    category: TuningCategory.metal,
    strings: [
      StringTuning(stringNumber: 1, note: 'D4', midiNote: 62),
      StringTuning(stringNumber: 2, note: 'A3', midiNote: 57),
      StringTuning(stringNumber: 3, note: 'F3', midiNote: 53),
      StringTuning(stringNumber: 4, note: 'C3', midiNote: 48),
      StringTuning(stringNumber: 5, note: 'G2', midiNote: 43),
      StringTuning(stringNumber: 6, note: 'D2', midiNote: 38),
    ],
  ),
  TuningName.dropC: Tuning(
    name: TuningName.dropC,
    displayName: 'Drop C',
    category: TuningCategory.metal,
    strings: [
      StringTuning(stringNumber: 1, note: 'D4', midiNote: 62),
      StringTuning(stringNumber: 2, note: 'A3', midiNote: 57),
      StringTuning(stringNumber: 3, note: 'F3', midiNote: 53),
      StringTuning(stringNumber: 4, note: 'C3', midiNote: 48),
      StringTuning(stringNumber: 5, note: 'G2', midiNote: 43),
      StringTuning(stringNumber: 6, note: 'C2', midiNote: 36),
    ],
  ),
  TuningName.dropB: Tuning(
    name: TuningName.dropB,
    displayName: 'Drop B',
    category: TuningCategory.metal,
    strings: [
      StringTuning(stringNumber: 1, note: 'C#4', midiNote: 61),
      StringTuning(stringNumber: 2, note: 'G#3', midiNote: 56),
      StringTuning(stringNumber: 3, note: 'E3', midiNote: 52),
      StringTuning(stringNumber: 4, note: 'B2', midiNote: 47),
      StringTuning(stringNumber: 5, note: 'F#2', midiNote: 42),
      StringTuning(stringNumber: 6, note: 'B1', midiNote: 35),
    ],
  ),
  // Midwest Emo
  TuningName.openD: Tuning(
    name: TuningName.openD,
    displayName: 'Open D',
    category: TuningCategory.midwestEmo,
    strings: [
      StringTuning(stringNumber: 1, note: 'D4', midiNote: 62),
      StringTuning(stringNumber: 2, note: 'A3', midiNote: 57),
      StringTuning(stringNumber: 3, note: 'F#3', midiNote: 54),
      StringTuning(stringNumber: 4, note: 'D3', midiNote: 50),
      StringTuning(stringNumber: 5, note: 'A2', midiNote: 45),
      StringTuning(stringNumber: 6, note: 'D2', midiNote: 38),
    ],
  ),
  TuningName.openG: Tuning(
    name: TuningName.openG,
    displayName: 'Open G',
    category: TuningCategory.midwestEmo,
    strings: [
      StringTuning(stringNumber: 1, note: 'D4', midiNote: 62),
      StringTuning(stringNumber: 2, note: 'B3', midiNote: 59),
      StringTuning(stringNumber: 3, note: 'G3', midiNote: 55),
      StringTuning(stringNumber: 4, note: 'D3', midiNote: 50),
      StringTuning(stringNumber: 5, note: 'G2', midiNote: 43),
      StringTuning(stringNumber: 6, note: 'D2', midiNote: 38),
    ],
  ),
  TuningName.dadgad: Tuning(
    name: TuningName.dadgad,
    displayName: 'DADGAD',
    category: TuningCategory.midwestEmo,
    strings: [
      StringTuning(stringNumber: 1, note: 'D4', midiNote: 62),
      StringTuning(stringNumber: 2, note: 'A3', midiNote: 57),
      StringTuning(stringNumber: 3, note: 'G3', midiNote: 55),
      StringTuning(stringNumber: 4, note: 'D3', midiNote: 50),
      StringTuning(stringNumber: 5, note: 'A2', midiNote: 45),
      StringTuning(stringNumber: 6, note: 'D2', midiNote: 38),
    ],
  ),
  TuningName.facgce: Tuning(
    name: TuningName.facgce,
    displayName: 'FACGCE',
    category: TuningCategory.midwestEmo,
    strings: [
      StringTuning(stringNumber: 1, note: 'E4', midiNote: 64),
      StringTuning(stringNumber: 2, note: 'C4', midiNote: 60),
      StringTuning(stringNumber: 3, note: 'G3', midiNote: 55),
      StringTuning(stringNumber: 4, note: 'C3', midiNote: 48),
      StringTuning(stringNumber: 5, note: 'A2', midiNote: 45),
      StringTuning(stringNumber: 6, note: 'F2', midiNote: 41),
    ],
  ),
};

// ─── Validation ───────────────────────────────────────────────────────────────

({bool valid, List<String> errors}) validateTuning(Tuning tuning) {
  final errors = <String>[];
  if (tuning.strings.length != 6) {
    errors.add(
      'Tuning must have exactly 6 strings, got ${tuning.strings.length}',
    );
  }
  for (final s in tuning.strings) {
    final noteWithoutOctave = s.note.replaceAll(RegExp(r'\d'), '');
    if (!isValidPitchClass(noteWithoutOctave)) {
      errors.add('String ${s.stringNumber}: invalid note "${s.note}"');
    }
    if (s.midiNote < 28 || s.midiNote > 88) {
      errors.add(
        'String ${s.stringNumber}: MIDI note ${s.midiNote} out of guitar range (28–88)',
      );
    }
  }
  return (valid: errors.isEmpty, errors: errors);
}

// ─── Default State ────────────────────────────────────────────────────────────

FretboardState getDefaultFretboardState() => const FretboardState(
  currentTuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  highlightedNotes: [],
  selectedNotes: [],
  selectedCells: [],
  viewMode: FretboardViewMode.pitchClass,
  inputMode: FretboardInputMode.free,
);
