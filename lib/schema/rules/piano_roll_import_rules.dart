/// Piano Roll Import Rules
/// Pure, UI-free helpers for stack building and snapshot import mapping.
///
/// Used by piano roll widgets (stack selector, save stack loader) to build
/// MIDI note stacks and import snapshots from other instruments.
library;

import '../../models/save_system.dart';
import '../../schema/rules/fretboard_rules.dart' as fret_rules;
import '../../utils/note_utils.dart';

// ─── Pitch-class → MIDI mapping ──────────────────────────────────────────────

/// Picks the best MIDI note for [pc] (0–11) within [lo]…[hi] closest to the
/// range's centre, or closest to [anchor] when provided. Returns `null` when
/// no MIDI note in the range matches [pc].
///
/// Example: `bestMidiInRangeForPitchClass(0, 48, 72)` → 60 (C4, centre of C3–C5)
int? bestMidiInRangeForPitchClass(int pc, int lo, int hi, {int? anchor}) {
  final target = anchor ?? ((lo + hi) / 2).round();
  int? best;
  var bestDist = 999999;
  for (var midi = lo; midi <= hi; midi++) {
    if ((midi % 12) != pc) continue;
    final dist = (midi - target).abs();
    if (dist < bestDist) {
      best = midi;
      bestDist = dist;
    }
  }
  return best;
}

// ─── Chord-stack building ────────────────────────────────────────────────────

/// Builds a chord stack of MIDI notes for [root] + [quality] centred around
/// [anchorMidi] and clamped to [lo]…[hi]. Returns the resulting MIDI notes.
///
/// Pitch-class notes are computed via [getChordNotes] from `note_utils.dart`.
/// Each note is mapped to the nearest valid MIDI in the range using
/// [bestMidiInRangeForPitchClass].
List<int> buildChordStackMidis(
  String root,
  String quality,
  int anchorMidi,
  int lo,
  int hi,
) {
  final notes = getChordNotes(root, quality);
  if (notes.isEmpty) return [];
  return notes
      .map((pcName) {
        final pc = noteToPC[pcName];
        if (pc == null) return null;
        return bestMidiInRangeForPitchClass(pc, lo, hi, anchor: anchorMidi);
      })
      .whereType<int>()
      .toList();
}

// ─── Snapshot import ─────────────────────────────────────────────────────────

/// Extracts MIDI notes from an [InstrumentSnapshot] for import into the piano
/// roll.
///
/// When [exactPitchClassMode] is `true` (the default), exact positions are
/// used: [FretboardSnapshot] computes MIDI from the saved tuning + string +
/// fret, and [PianoSnapshot] reads `midiNote` directly from each selected key.
/// Both are filtered to [lo]…[hi].
///
/// When [exactPitchClassMode] is `false`, only unique pitch classes from
/// `selectedNotes` are mapped to their nearest MIDI notes within [lo]…[hi]
/// (centred on the middle of the range).
///
/// Full [PianoRoll] snapshots are not handled here — they will be handled
/// separately in a later task.
List<int>? extractSnapshotImportMidis(
  InstrumentSnapshot snapshot, {
  bool? exactPitchClassMode,
  int? lo,
  int? hi,
}) {
  final exact = exactPitchClassMode ?? true;
  final rangeStart = lo ?? 21;
  final rangeEnd = hi ?? 108;

  if (exact) {
    if (snapshot is FretboardSnapshot) {
      final tuning = fret_rules.tunings[snapshot.tuning];
      if (tuning == null) return [];
      return snapshot.selectedCells
          .where((c) => c.stringIndex < tuning.strings.length)
          .map((c) => tuning.strings[c.stringIndex].midiNote + c.fret)
          .where((m) => m >= rangeStart && m <= rangeEnd)
          .toList();
    } else if (snapshot is PianoSnapshot) {
      return snapshot.selectedKeys
          .map((k) => k.midiNote)
          .where((m) => m >= rangeStart && m <= rangeEnd)
          .toList();
    }
    return [];
  }

  // pitch-class mode
  final pcs = snapshot.selectedNotes.toSet();
  if (pcs.isEmpty) return [];
  return pcs
      .map((pcName) {
        final pc = noteToPC[pcName];
        if (pc == null) return null;
        return bestMidiInRangeForPitchClass(pc, rangeStart, rangeEnd);
      })
      .whereType<int>()
      .toList();
}
