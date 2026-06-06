/// Library-match rule for Songwriter Phase C v2-b.
///
/// Classifies user `SaveEntry`s as either a chord-match (the save's detected
/// `pendingChord.symbol` equals the harmony block's `chordSymbol`) or a
/// scale-match (every note in the save's `selectedNotes` is in the project
/// key's scale). Chord-match takes precedence — a save that satisfies both
/// only appears in the chord bucket.
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

({List<LibraryMatch> chordMatches, List<LibraryMatch> scaleMatches})
    matchLibrary({
  required SongBlock harmonyBlock,
  required List<SaveEntry> searchableSaves,
  required int? keyRootPc,
  required String? keyScaleName,
}) {
  final chordSymbol = harmonyBlock.chordSymbol;
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
    final snap = save.snapshot;
    final chordHit =
        chordSymbol != null && snap.pendingChord?.symbol == chordSymbol;
    if (chordHit) {
      chord.add(LibraryMatch(entry: save, kind: LibraryMatchKind.chord));
      continue;
    }
    if (scalePcs.isEmpty) continue;
    final notes = snap.selectedNotes;
    if (notes.isEmpty) continue;
    var allInScale = true;
    for (final n in notes) {
      final pc = noteToPC[n];
      if (pc == null || !scalePcs.contains(pc)) {
        allInScale = false;
        break;
      }
    }
    if (allInScale) {
      scale.add(LibraryMatch(entry: save, kind: LibraryMatchKind.scale));
    }
  }

  chord.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  scale.sort((a, b) => b.entry.updatedAt.compareTo(a.entry.updatedAt));
  return (chordMatches: chord, scaleMatches: scale);
}
