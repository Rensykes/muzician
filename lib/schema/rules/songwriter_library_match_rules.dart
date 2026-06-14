/// Library-match rule for Songwriter Phase C v2-b.
///
/// Classifies user `SaveEntry`s as either a **chord-match** (the save's note
/// set, reduced to pitch classes, exactly equals the harmony block's chord
/// tones — octave- and repetition-agnostic) or a **scale-match** (every note
/// in the save is in the project key's scale). Chord-match takes precedence —
/// a save that satisfies both only appears in the chord bucket.
library;

import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';

enum LibraryMatchKind { chord, scale }

class LibraryMatch {
  const LibraryMatch({required this.entry, required this.kind});
  final SaveEntry entry;
  final LibraryMatchKind kind;
}

/// Pitch class (0–11) of a note name, tolerant of an octave suffix
/// (`'C'`, `'C4'`, `'F#3'` all map). Returns null for unknown names.
int? _pcOf(String name) {
  // Strip a trailing octave number (and any sign) so 'C4'/'C-1' → 'C'.
  var head = name;
  while (head.isNotEmpty &&
      (head.codeUnitAt(head.length - 1) ^ 0x30) <= 9) {
    head = head.substring(0, head.length - 1);
  }
  if (head.endsWith('-')) head = head.substring(0, head.length - 1);
  return noteToPC[head];
}

/// Pitch-class set of a list of note names (octave / repetition collapsed).
Set<int> _pcSet(Iterable<String> notes) {
  final out = <int>{};
  for (final n in notes) {
    final pc = _pcOf(n);
    if (pc != null) out.add(pc);
  }
  return out;
}

({List<LibraryMatch> chordMatches, List<LibraryMatch> scaleMatches})
matchLibrary({
  required SongBlock harmonyBlock,
  required List<SaveEntry> searchableSaves,
  required int? keyRootPc,
  required String? keyScaleName,
}) {
  // The chord's target pitch-class set, from the block's chord notes (falling
  // back to root + quality intervals when the block carries no note names).
  var chordPcs = _pcSet(harmonyBlock.chordNotes);
  if (chordPcs.isEmpty &&
      harmonyBlock.chordRootPc != null &&
      harmonyBlock.chordQuality != null) {
    final intervals = chordIntervals[harmonyBlock.chordQuality];
    if (intervals != null) {
      chordPcs = {
        for (final i in intervals) (harmonyBlock.chordRootPc! + i) % 12,
      };
    }
  }

  final scalePcs = <int>{};
  if (keyRootPc != null && keyScaleName != null) {
    final intervals = scaleIntervals[keyScaleName];
    if (intervals != null) {
      for (final i in intervals) {
        scalePcs.add((keyRootPc + i) % 12);
      }
    }
  }

  final chord = <LibraryMatch>[];
  final scale = <LibraryMatch>[];
  for (final save in searchableSaves) {
    final notes = save.snapshot.selectedNotes;
    if (notes.isEmpty) continue;
    final savePcs = _pcSet(notes);

    // Chord-match: the save's pitch-class set is exactly the chord's tones.
    if (chordPcs.isNotEmpty &&
        savePcs.length == chordPcs.length &&
        savePcs.containsAll(chordPcs)) {
      chord.add(LibraryMatch(entry: save, kind: LibraryMatchKind.chord));
      continue;
    }

    // Scale-match: every note fits the project key's scale.
    if (scalePcs.isEmpty) continue;
    if (savePcs.every(scalePcs.contains)) {
      scale.add(LibraryMatch(entry: save, kind: LibraryMatchKind.scale));
    }
  }

  chord.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  scale.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  return (chordMatches: chord, scaleMatches: scale);
}
