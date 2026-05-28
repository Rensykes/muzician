/// Song Pattern Bridge Rules
/// Conversions between NotePattern (song domain) and PianoRollState (editor domain).
library;

import 'dart:math';
import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'piano_roll_rules.dart' as pr_rules;

/// Converts a [NotePattern] into a [PianoRollState] suitable for seeding an
/// isolated piano-roll editor.
PianoRollState pianoRollStateFromNotePattern(
  NotePattern pattern, {
  required int tempo,
  required TimeSignature timeSignature,
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

  return PianoRollState(
    config: PianoRollConfig(
      tempo: tempo.clamp(pr_rules.minTempo, pr_rules.maxTempo),
      key: null,
      timeSignature: timeSignature,
      totalMeasures: totalMeasures,
    ),
    notes: notes,
    pitchRangeStart: pattern.pitchRangeStart,
    pitchRangeEnd: pattern.pitchRangeEnd,
    selectedColumnTick: null,
    selectedNoteIds: const <String>{},
    snapTicks: pattern.snapTicks,
    highlightedNotes: List<String>.from(pattern.highlightedNotes),
    latestImportedRange: null,
  );
}

/// Converts a [PianoRollState] back into a [NotePattern], stripping derived
/// fields (`pitchClass`, `noteWithOctave`) that are stored only in the editor.
///
/// The pattern's [NotePattern.lengthTicks] keeps at least the previous saved
/// length so trailing space and empty patterns are preserved, while still
/// extending when edited notes reach further right.
NotePattern notePatternFromPianoRollState(
  PianoRollState state, {
  required String patternId,
  required String patternName,
  required int minimumLengthTicks,
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
    highlightedNotes: List<String>.from(state.highlightedNotes),
  );
}
