/// Shared music theory utilities used across fretboard and piano features.
library;

// ─── Note normalization ───────────────────────────────────────────────────────

const Map<String, String> _flatToSharp = {
  'Db': 'C#',
  'Eb': 'D#',
  'Fb': 'E',
  'Gb': 'F#',
  'Ab': 'G#',
  'Bb': 'A#',
  'Cb': 'B',
};

/// Converts a flat note name to its sharp equivalent (e.g. `Bb` → `A#`).
String toSharp(String note) => _flatToSharp[note] ?? note;

// ─── Chromatic scale ──────────────────────────────────────────────────────────

/// The 12 pitch classes using sharps, in ascending order from C.
const List<String> chromaticNotes = [
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

/// Maps each note name to its pitch-class index (0–11).
const Map<String, int> noteToPC = {
  'C': 0,
  'C#': 1,
  'D': 2,
  'D#': 3,
  'E': 4,
  'F': 5,
  'F#': 6,
  'G': 7,
  'G#': 8,
  'A': 9,
  'A#': 10,
  'B': 11,
};

/// Returns true when [noteName] has no accidental.
bool isNaturalNote(String noteName) =>
    !noteName.contains('#') && !noteName.contains('b');

// ─── Scale data ───────────────────────────────────────────────────────────────

/// UI grouping for scale types shown in pickers.
enum ScaleCategory { common, modes, extended }

/// Scale names and their display labels grouped by [ScaleCategory].
const scaleGroups = <ScaleCategory, List<(String name, String label)>>{
  ScaleCategory.common: [
    ('major', 'Major'),
    ('minor', 'Minor'),
    ('major pentatonic', 'Pent. Maj'),
    ('minor pentatonic', 'Pent. Min'),
    ('blues', 'Blues'),
  ],
  ScaleCategory.modes: [
    ('dorian', 'Dorian'),
    ('phrygian', 'Phrygian'),
    ('lydian', 'Lydian'),
    ('mixolydian', 'Mixolydian'),
    ('locrian', 'Locrian'),
  ],
  ScaleCategory.extended: [
    ('harmonic minor', 'Harm. Min'),
    ('melodic minor', 'Mel. Min'),
    ('whole tone', 'Whole Tone'),
    ('diminished', 'Diminished'),
  ],
};

/// Human-readable label for each [ScaleCategory].
const scaleCategoryLabels = <ScaleCategory, String>{
  ScaleCategory.common: 'Common',
  ScaleCategory.modes: 'Modes',
  ScaleCategory.extended: 'Extended',
};

/// Semitone intervals from the root for every supported scale type.
const scaleIntervals = <String, List<int>>{
  'major': [0, 2, 4, 5, 7, 9, 11],
  'minor': [0, 2, 3, 5, 7, 8, 10],
  'major pentatonic': [0, 2, 4, 7, 9],
  'minor pentatonic': [0, 3, 5, 7, 10],
  'blues': [0, 3, 5, 6, 7, 10],
  'dorian': [0, 2, 3, 5, 7, 9, 10],
  'phrygian': [0, 1, 3, 5, 7, 8, 10],
  'lydian': [0, 2, 4, 6, 7, 9, 11],
  'mixolydian': [0, 2, 4, 5, 7, 9, 10],
  'locrian': [0, 1, 3, 5, 6, 8, 10],
  'harmonic minor': [0, 2, 3, 5, 7, 8, 11],
  'melodic minor': [0, 2, 3, 5, 7, 9, 11],
  'whole tone': [0, 2, 4, 6, 8, 10],
  'diminished': [0, 2, 3, 5, 6, 8, 9, 11],
};

/// Returns the pitch classes of [scaleName] starting at [root].
///
/// Returns an empty list when [root] or [scaleName] is unknown.
List<String> getScaleNotes(String root, String scaleName) {
  final rootIdx = chromaticNotes.indexOf(root);
  if (rootIdx < 0) return [];
  final intervals = scaleIntervals[scaleName];
  if (intervals == null) return [];
  return intervals.map((i) => chromaticNotes[(rootIdx + i) % 12]).toList();
}

// ─── Chord data ───────────────────────────────────────────────────────────────

/// Semitone intervals from the root for every supported chord quality.
const chordIntervals = <String, List<int>>{
  '': [0, 4, 7],
  'm': [0, 3, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
  '5': [0, 7],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'm7b5': [0, 3, 6, 10],
  'add9': [0, 4, 7, 14],
  'maj9': [0, 4, 7, 11, 14],
  '6': [0, 4, 7, 9],
  'm6': [0, 3, 7, 9],
  'dim7': [0, 3, 6, 9],
  '7sus4': [0, 5, 7, 10],
};

/// Returns the pitch classes of a chord built on [root] with [quality].
///
/// Returns an empty list when [root] or [quality] is unknown.
List<String> getChordNotes(String root, String quality) {
  final intervals = chordIntervals[quality];
  if (intervals == null) return [];
  final rootIdx = noteToPC[root];
  if (rootIdx == null) return [];
  return intervals.map((i) => chromaticNotes[(rootIdx + i) % 12]).toList();
}

// ─── Detection helpers ────────────────────────────────────────────────────────

/// Returns the first chord whose tones exactly match [notes], or null.
///
/// Pass [qualitySymbols] to restrict detection to a subset of qualities
/// (e.g. the 9 qualities shown in the piano picker). Defaults to all
/// entries in [chordIntervals].
({String root, String quality})? detectFirstChord(
  List<String> notes, {
  List<String>? qualitySymbols,
}) {
  if (notes.length < 2) return null;
  final noteSet = notes.toSet();
  final symbols = qualitySymbols ?? chordIntervals.keys.toList();
  for (final root in chromaticNotes) {
    final rootIdx = noteToPC[root]!;
    for (final symbol in symbols) {
      final intervals = chordIntervals[symbol];
      if (intervals == null || intervals.length < 2) continue;
      final chordTones =
          intervals.map((i) => chromaticNotes[(rootIdx + i) % 12]).toSet();
      if (noteSet.every(chordTones.contains) &&
          chordTones.every(noteSet.contains)) {
        return (root: root, quality: symbol);
      }
    }
  }
  return null;
}

/// Detects matching chords and potential parent scales from [notes].
///
/// Returns up to 8 chord names (e.g. `'Cmaj7'`) and up to 8 scale names
/// (e.g. `'C major'`) that contain all [notes] as a subset.
({List<String> chords, List<String> scales}) detectChordsAndScales(
  List<String> notes,
) {
  if (notes.length < 2) return (chords: <String>[], scales: <String>[]);
  final noteSet = notes.toSet();

  const detectionQualities = [
    ('', [0, 4, 7]),
    ('m', [0, 3, 7]),
    ('7', [0, 4, 7, 10]),
    ('maj7', [0, 4, 7, 11]),
    ('m7', [0, 3, 7, 10]),
    ('dim', [0, 3, 6]),
    ('aug', [0, 4, 8]),
    ('sus2', [0, 2, 7]),
    ('sus4', [0, 5, 7]),
    ('m7b5', [0, 3, 6, 10]),
    ('add9', [0, 4, 7, 2]),
    ('maj9', [0, 4, 7, 11, 2]),
    ('6', [0, 4, 7, 9]),
    ('m6', [0, 3, 7, 9]),
    ('dim7', [0, 3, 6, 9]),
    ('7sus4', [0, 5, 7, 10]),
  ];

  const detectionScales = [
    ('major', [0, 2, 4, 5, 7, 9, 11]),
    ('minor', [0, 2, 3, 5, 7, 8, 10]),
    ('major pentatonic', [0, 2, 4, 7, 9]),
    ('minor pentatonic', [0, 3, 5, 7, 10]),
    ('blues', [0, 3, 5, 6, 7, 10]),
    ('dorian', [0, 2, 3, 5, 7, 9, 10]),
  ];

  final chords = <String>[];
  for (final root in chromaticNotes) {
    final rootIdx = noteToPC[root]!;
    for (final (symbol, intervals) in detectionQualities) {
      final chordTones =
          intervals.map((i) => chromaticNotes[(rootIdx + i) % 12]).toSet();
      if (noteSet.every(chordTones.contains) &&
          chordTones.every(noteSet.contains)) {
        chords.add('$root${symbol.isEmpty ? '' : symbol}');
      }
    }
  }

  final scales = <String>[];
  for (final root in chromaticNotes) {
    final rootIdx = noteToPC[root]!;
    for (final (name, intervals) in detectionScales) {
      final scaleTones =
          intervals.map((i) => chromaticNotes[(rootIdx + i) % 12]).toSet();
      if (noteSet.every(scaleTones.contains)) {
        scales.add('$root $name');
      }
    }
  }

  return (chords: chords.take(8).toList(), scales: scales.take(8).toList());
}
