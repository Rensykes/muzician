import 'package:flutter/material.dart';
import '../models/save_system.dart';
import '../utils/note_utils.dart';

enum SaveCardLabelKind { chord, scale, notes, highlight }

class SaveCardLabel {
  final SaveCardLabelKind kind;
  final String? text; // chord symbol, scale name, or 'Highlight'
  final List<String> notes; // populated only for kind == notes
  const SaveCardLabel(this.kind, {this.text, this.notes = const []});
}

/// Derives a glanceable identity for a save card from data already on the
/// snapshot. Resolution order: chord, scale, notes, then a literal
/// "Highlight" fallback for selections with no derivable chord/scale.
SaveCardLabel saveCardLabel(InstrumentSnapshot snapshot) {
  final chord = snapshot.pendingChord;
  if (chord != null) {
    return SaveCardLabel(SaveCardLabelKind.chord, text: chord.symbol);
  }
  final scale = snapshot.pendingScale;
  if (scale != null) {
    return SaveCardLabel(
      SaveCardLabelKind.scale,
      text: '${scale.root} ${scale.scaleName}',
    );
  }
  if (snapshot.selectedNotes.isNotEmpty) {
    return SaveCardLabel(
      SaveCardLabelKind.notes,
      notes: snapshot.selectedNotes,
    );
  }
  return const SaveCardLabel(SaveCardLabelKind.highlight, text: 'Highlight');
}

/// True when any pitch class on the snapshot falls outside the supplied
/// project scale. Returns `false` when no project key is configured or the
/// snapshot has no notes to evaluate.
bool snapshotOffKey(
  InstrumentSnapshot snapshot, {
  required String? scaleRoot,
  required String? scaleName,
}) {
  if (scaleRoot == null || scaleName == null) return false;
  final scalePcs = getScaleNotes(scaleRoot, scaleName).toSet();
  if (scalePcs.isEmpty) return false;
  for (final n in snapshot.selectedNotes) {
    if (!scalePcs.contains(n)) return true;
  }
  final chord = snapshot.pendingChord;
  if (chord != null) {
    for (final n in getChordNotes(chord.root, chord.quality)) {
      if (!scalePcs.contains(n)) return true;
    }
  }
  return false;
}

/// Material icon for the snapshot's instrument, used by the card.
IconData saveInstrumentIcon(String instrument) {
  switch (instrument) {
    case 'piano':
      return Icons.piano;
    case 'piano_roll':
      return Icons.grid_on;
    case 'song':
      return Icons.queue_music;
    case 'songwriter':
      return Icons.library_music;
    case 'fretboard':
    default:
      return Icons.music_note;
  }
}
