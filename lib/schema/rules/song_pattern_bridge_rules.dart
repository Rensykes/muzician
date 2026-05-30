/// Song Pattern Bridge Rules
/// Conversions between NotePattern (song domain) and PianoRollState (editor domain).
library;

import 'dart:math';
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'piano_roll_rules.dart' as pr_rules;

/// Converts a [NotePattern] into a [PianoRollState] suitable for seeding an
/// isolated piano-roll editor.
///
/// If [songHighlightedNotes] is non-null and non-empty it overrides the
/// pattern's own `highlightedNotes` — used by the Song workspace so every
/// note pattern inherits the song-level scale.  When the song has no scale,
/// the pattern's own highlight set is preserved as a fallback.
PianoRollState pianoRollStateFromNotePattern(
  NotePattern pattern, {
  required int tempo,
  required TimeSignature timeSignature,
  List<String>? songHighlightedNotes,
  String? songKey,
}) {
  final measureTicks = pr_rules.ticksPerMeasure(timeSignature);
  final totalMeasures = max(
    1,
    (pattern.lengthTicks + measureTicks - 1) ~/ measureTicks,
  ).clamp(1, 32);

  final notes = pattern.notes.map((n) {
    return PianoRollNote(
      id: n.id,
      midiNote: n.midiNote,
      pitchClass: pr_rules.midiToPitchClass(n.midiNote),
      noteWithOctave: pr_rules.midiToNoteWithOctave(n.midiNote),
      startTick: n.startTick,
      durationTicks: n.durationTicks,
    );
  }).toList();

  final highlighted =
      (songHighlightedNotes != null && songHighlightedNotes.isNotEmpty)
      ? List<String>.from(songHighlightedNotes)
      : List<String>.from(pattern.highlightedNotes);

  return PianoRollState(
    config: PianoRollConfig(
      tempo: tempo.clamp(pr_rules.minTempo, pr_rules.maxTempo),
      key: songKey,
      timeSignature: timeSignature,
      totalMeasures: totalMeasures,
    ),
    notes: notes,
    pitchRangeStart: pattern.pitchRangeStart,
    pitchRangeEnd: pattern.pitchRangeEnd,
    selectedColumnTick: null,
    selectedNoteIds: const <String>{},
    snapTicks: pattern.snapTicks,
    highlightedNotes: highlighted,
    latestImportedRange: null,
  );
}

/// Converts a [PianoRollState] back into a [NotePattern], stripping derived
/// fields (`pitchClass`, `noteWithOctave`) that are stored only in the editor.
///
/// The pattern's [NotePattern.lengthTicks] keeps at least the previous saved
/// length so trailing space and empty patterns are preserved, while still
/// extending when edited notes reach further right.
/// When the host (Song workspace) injects a song-scale highlight that doesn't
/// belong to the pattern, pass the pattern's original highlight set via
/// [highlightedNotesOverride] so the saved pattern keeps its own fallback
/// rather than being overwritten with the inherited song scale.
NotePattern notePatternFromPianoRollState(
  PianoRollState state, {
  required String patternId,
  required String patternName,
  required int minimumLengthTicks,
  List<String>? highlightedNotesOverride,
}) {
  final notes = state.notes.map((n) {
    return NotePatternNote(
      id: n.id,
      midiNote: n.midiNote,
      startTick: n.startTick,
      durationTicks: n.durationTicks,
    );
  }).toList();

  final furthestEndTick = notes.isEmpty
      ? 0
      : notes.map((n) => n.startTick + n.durationTicks).reduce(max);
  final lengthTicks = max(minimumLengthTicks, furthestEndTick);

  return NotePattern(
    id: patternId,
    name: patternName,
    lengthTicks: lengthTicks,
    notes: notes,
    pitchRangeStart: state.pitchRangeStart,
    pitchRangeEnd: state.pitchRangeEnd,
    snapTicks: state.snapTicks,
    highlightedNotes: List<String>.from(
      highlightedNotesOverride ?? state.highlightedNotes,
    ),
  );
}
