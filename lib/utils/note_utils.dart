/// Shared music theory utilities used across fretboard and piano features.
library;

import '../models/harmonic_analysis.dart';

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

int _compareChordResults(ChordDetectionResult a, ChordDetectionResult b) {
  final aSlash = a.bass == null ? 0 : 1;
  final bSlash = b.bass == null ? 0 : 1;
  if (aSlash != bSlash) return aSlash.compareTo(bSlash);
  if (a.root != b.root) {
    return chromaticNotes
        .indexOf(a.root)
        .compareTo(chromaticNotes.indexOf(b.root));
  }
  return a.quality.compareTo(b.quality);
}

int _compareScaleResults(
  ScaleDetectionResult a,
  ScaleDetectionResult b,
  int selectedPitchClassCount,
) {
  final aExtra = scaleIntervals[a.scaleName]!.length - selectedPitchClassCount;
  final bExtra = scaleIntervals[b.scaleName]!.length - selectedPitchClassCount;
  if (aExtra != bExtra) return aExtra.compareTo(bExtra);

  int categoryIndex(String name) {
    for (final entry in scaleGroups.entries) {
      if (entry.value.any((s) => s.$1 == name)) return entry.key.index;
    }
    return ScaleCategory.values.length;
  }

  final aCategory = categoryIndex(a.scaleName);
  final bCategory = categoryIndex(b.scaleName);
  if (aCategory != bCategory) return aCategory.compareTo(bCategory);

  if (a.root != b.root) {
    return chromaticNotes
        .indexOf(a.root)
        .compareTo(chromaticNotes.indexOf(b.root));
  }
  return a.scaleName.compareTo(b.scaleName);
}

/// Detects chords from exact MIDI notes with optional slash-chord detection.
List<ChordDetectionResult> detectChordResultsFromExactNotes(
  List<ExactSelectionNote> notes, {
  List<String>? qualitySymbols,
}) {
  if (notes.length < 2) return const [];

  final sorted = [...notes]..sort((a, b) => a.midiNote.compareTo(b.midiNote));
  final pitchClasses = sorted.map((note) => note.pitchClass).toSet();
  final bass = sorted.first.pitchClass;
  final symbols = qualitySymbols ?? chordIntervals.keys.toList();
  final results = <ChordDetectionResult>[];

  for (final root in chromaticNotes) {
    final rootIndex = noteToPC[root]!;
    for (final quality in symbols) {
      final intervals = chordIntervals[quality];
      if (intervals == null) continue;
      final tones = intervals
          .map((interval) => chromaticNotes[(rootIndex + interval) % 12])
          .toSet();
      if (tones.length != pitchClasses.length) continue;
      if (!pitchClasses.every(tones.contains)) continue;
      results.add(
        ChordDetectionResult(
          root: root,
          quality: quality,
          bass: bass == root ? null : bass,
        ),
      );
    }
  }

  results.sort(_compareChordResults);
  return results;
}

/// Detects parent scales from exact MIDI notes using the full scale catalog.
List<ScaleDetectionResult> detectScaleResultsFromExactNotes(
  List<ExactSelectionNote> notes,
) {
  if (notes.length < 2) return const [];
  final pitchClasses = notes.map((note) => note.pitchClass).toSet();
  final results = <ScaleDetectionResult>[];

  for (final root in chromaticNotes) {
    for (final scaleName in scaleIntervals.keys) {
      final scaleTones = getScaleNotes(root, scaleName).toSet();
      if (pitchClasses.every(scaleTones.contains)) {
        results.add(ScaleDetectionResult(root: root, scaleName: scaleName));
      }
    }
  }

  results.sort((a, b) => _compareScaleResults(a, b, pitchClasses.length));
  return results;
}

/// Formats a canonical sharp root as a flat label for display (e.g. `A#` → `Bb`).
String formatRootChoiceLabel(String canonicalRoot) => switch (canonicalRoot) {
  'A#' => 'Bb',
  'C#' => 'Db',
  'D#' => 'Eb',
  'G#' => 'Ab',
  _ => canonicalRoot,
};

/// Formats a MIDI note as a display label with octave, preserving the same
/// accidental style used by root-choice UI (e.g. `61` -> `Db4`).
String formatMidiNoteLabel(int midi) {
  final pitchClass = chromaticNotes[((midi % 12) + 12) % 12];
  final octave = (midi ~/ 12) - 1;
  return '${formatRootChoiceLabel(pitchClass)}$octave';
}

/// Formats a [ChordDetectionResult] as a human-readable chord symbol
/// (e.g. `Cmaj7` or `C/E`).
String formatChordSymbol(ChordDetectionResult result) {
  final root = formatRootChoiceLabel(result.root);
  final bass = result.bass == null ? null : formatRootChoiceLabel(result.bass!);
  return bass == null
      ? '$root${result.quality}'
      : '$root${result.quality}/$bass';
}

/// Formats a [ScaleDetectionResult] as a human-readable label
/// (e.g. `C major` or `Eb dorian`).
String formatScaleLabel(ScaleDetectionResult result) =>
    '${formatRootChoiceLabel(result.root)} ${result.scaleName}';

/// Internal helper that detects chords from a set of pitch-class names.
List<ChordDetectionResult> _detectChordResultsFromPitchClasses(
  Set<String> pitchClasses, {
  List<String>? qualitySymbols,
}) {
  final symbols = qualitySymbols ?? chordIntervals.keys.toList();
  final results = <ChordDetectionResult>[];

  for (final root in chromaticNotes) {
    final rootIndex = noteToPC[root]!;
    for (final quality in symbols) {
      final intervals = chordIntervals[quality];
      if (intervals == null) continue;
      final chordTones = intervals
          .map((interval) => chromaticNotes[(rootIndex + interval) % 12])
          .toSet();
      if (chordTones.length != pitchClasses.length) continue;
      if (!pitchClasses.every(chordTones.contains)) continue;
      results.add(ChordDetectionResult(root: root, quality: quality));
    }
  }

  results.sort(_compareChordResults);
  return results;
}

/// Returns the first chord whose tones exactly match [notes], or null.
///
/// Pass [qualitySymbols] to restrict detection to a subset of qualities
/// (e.g. the 9 qualities shown in the piano picker). Defaults to all
/// entries in [chordIntervals].
({String root, String quality})? detectFirstChord(
  List<String> notes, {
  List<String>? qualitySymbols,
}) {
  final results = _detectChordResultsFromPitchClasses(
    notes.toSet(),
    qualitySymbols: qualitySymbols,
  );
  final first = results.isEmpty ? null : results.first;
  return first == null ? null : (root: first.root, quality: first.quality);
}

/// Detects matching chords and potential parent scales from [notes].
///
/// Returns up to 8 chord names (e.g. `'Cmaj7'`) and up to 8 scale names
/// (e.g. `'C major'`) that contain all [notes] as a subset.
({List<String> chords, List<String> scales}) detectChordsAndScales(
  List<String> notes,
) {
  final pitchClasses = notes.toSet();
  final chordResults = _detectChordResultsFromPitchClasses(pitchClasses);
  final scaleResults = detectScaleResultsFromExactNotes([
    for (final note in pitchClasses)
      ExactSelectionNote(midiNote: noteToPC[note]!, pitchClass: note),
  ]);
  return (
    chords: chordResults
        .take(8)
        .map((result) => '${result.root}${result.quality}')
        .toList(),
    scales: scaleResults
        .take(8)
        .map((result) => '${result.root} ${result.scaleName}')
        .toList(),
  );
}
