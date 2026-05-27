/// Piano Roll Stack Builder Rules.
///
/// Pure music-theory functions for:
/// 1. Canonical stack generation with inversions
/// 2. Chord recognition from MIDI notes
/// 3. Custom-voicing detection
/// 4. Max-note enforcement (10)
/// 5. Continuous canonical retargeting (preserving note count and register)
library;

import '../../models/piano_roll_stack_builder.dart';
import '../../utils/note_utils.dart';
import 'piano_roll_rules.dart' as pr_rules;

// ─── Recognition ─────────────────────────────────────────────────────────────

/// Attempts to recognize [midiNotes] as a chord, returning the detected
/// root, quality, inversion index, and whether the voicing is non-canonical.
///
/// Returns an unrecognized result when fewer than 2 notes are provided or
/// when the pitch-class set does not match any known chord quality.
PianoRollStackRecognition recognizeStack(List<int> midiNotes) {
  if (midiNotes.length < 2) {
    return const PianoRollStackRecognition();
  }

  final uniquePcs = midiNotes
      .map((m) => pr_rules.midiToPitchClass(m))
      .toSet()
      .toList();
  final detected = detectFirstChord(uniquePcs);

  if (detected == null) {
    return const PianoRollStackRecognition();
  }

  // Determine inversion from the lowest MIDI note.
  // The bass note's position in the chord's tertian order gives the inversion.
  final lowestMidi = midiNotes.reduce((a, b) => a < b ? a : b);
  final lowestPc = pr_rules.midiToPitchClass(lowestMidi);
  final chordNotes = getChordNotes(detected.root, detected.quality);
  final inversionIndex = chordNotes.indexOf(lowestPc);

  // A voicing is "custom" when notes are doubled (more MIDI notes than unique
  // pitch classes), indicating a non-canonical arrangement.
  final hasDuplicates = midiNotes.length != uniquePcs.length;

  return PianoRollStackRecognition(
    recognizedRoot: detected.root,
    recognizedQuality: detected.quality,
    recognizedInversionIndex: inversionIndex >= 0 ? inversionIndex : 0,
    isRecognized: true,
    isCustomVoicing: hasDuplicates,
  );
}

// ─── Canonical generation ────────────────────────────────────────────────────

/// Generates a canonical (close-position) chord stack.
///
/// [root] is the chord root name (e.g. 'C').
/// [quality] is the chord quality key (e.g. '' for major, 'm' for minor).
/// [inversionIndex] determines which chord tone is the bass
///   (0 = root position, 1 = first inversion, etc.).
/// [noteCount] controls the total number of MIDI notes produced.
/// [anchorMidi] provides a reference pitch to determine the starting octave;
///   defaults to middle C (60).
///
/// The returned list is always strictly ascending.
List<int> generateCanonicalStack({
  required String root,
  required String quality,
  required int inversionIndex,
  required int noteCount,
  int? anchorMidi,
}) {
  final chordNames = getChordNotes(root, quality);
  if (chordNames.isEmpty) return [];

  // Convert note names to pitch-class integers (0-11).
  final tonePcs = chordNames.map((name) => noteToPC[name]!).toList();

  // Rotate the pitch-class list so the inversion bass comes first.
  // e.g. C major root [0,4,7] → 1st inv [4,7,0], 2nd inv [7,0,4].
  if (inversionIndex > 0 && inversionIndex < tonePcs.length) {
    final rotated = <int>[];
    for (var i = inversionIndex; i < tonePcs.length; i++) {
      rotated.add(tonePcs[i]);
    }
    for (var i = 0; i < inversionIndex; i++) {
      rotated.add(tonePcs[i]);
    }
    tonePcs
      ..clear()
      ..addAll(rotated);
  }

  // Determine the starting octave from the anchor.
  final anchor = anchorMidi ?? 60;
  var currentOctave = anchor ~/ 12;

  final result = <int>[];
  var prevMidi = -1;

  for (var i = 0; i < noteCount; i++) {
    final pc = tonePcs[i % tonePcs.length];

    // Place the pitch class in the current octave.
    var midi = currentOctave * 12 + pc;

    // Ensure ascending order — bump by octaves until above the previous note.
    while (midi <= prevMidi) {
      midi += 12;
    }

    currentOctave = midi ~/ 12;
    result.add(midi);
    prevMidi = midi;
  }

  return result;
}

// ─── Max note enforcement ────────────────────────────────────────────────────

/// Clamps [midiNotes] to at most [maxNotes] (default 10).
///
/// Returns a new list; the input is never mutated.
List<int> enforceMaxNotes(List<int> midiNotes, {int maxNotes = 10}) {
  if (midiNotes.length <= maxNotes) return [...midiNotes];
  return midiNotes.sublist(0, maxNotes);
}

// ─── Continuous retargeting ──────────────────────────────────────────────────

/// Generates a canonical stack for [root]/[quality]/[inversionIndex] while
/// preserving the note count and approximate register of [currentMidiNotes].
///
/// Uses the average MIDI of the current notes as the anchor so the new stack
/// lands in a similar pitch range.
List<int> retargetCanonicalStack({
  required List<int> currentMidiNotes,
  required String root,
  required String quality,
  required int inversionIndex,
}) {
  if (currentMidiNotes.isEmpty) return [];
  final anchor =
      currentMidiNotes.reduce((a, b) => a + b) ~/ currentMidiNotes.length;
  return generateCanonicalStack(
    root: root,
    quality: quality,
    inversionIndex: inversionIndex,
    noteCount: currentMidiNotes.length,
    anchorMidi: anchor,
  );
}
