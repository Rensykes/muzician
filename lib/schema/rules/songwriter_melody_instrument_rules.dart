/// Playability and physical-position rules for Writer melody patterns.
library;

import '../../models/fretboard.dart';
import '../../models/harmony_lane_instrument.dart';
import '../../models/piano.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import 'fretboard_rules.dart' show tunings;
import 'piano_rules.dart' show pianoRanges;

/// Enumerates every physical fretboard position that produces [midiNote] for
/// the current tuning, capo, and fret count.
List<FretboardNotePosition> fretboardPositionsForMidi({
  required int midiNote,
  required FretboardState state,
}) {
  final tuning = tunings[state.currentTuning];
  if (tuning == null) return const [];
  final positions = <FretboardNotePosition>[];
  for (
    var stringIndex = 0;
    stringIndex < tuning.strings.length;
    stringIndex++
  ) {
    final openMidi = tuning.strings[stringIndex].midiNote;
    final fret = midiNote - openMidi;
    if (fret < state.capo || fret > state.numFrets) continue;
    positions.add(FretboardNotePosition(stringIndex: stringIndex, fret: fret));
  }
  return positions;
}

/// Whether [position] is on the current fretboard and produces [midiNote].
bool isValidFretboardNotePosition({
  required int midiNote,
  required FretboardNotePosition position,
  required FretboardState state,
}) {
  final tuning = tunings[state.currentTuning];
  if (tuning == null ||
      position.stringIndex < 0 ||
      position.stringIndex >= tuning.strings.length ||
      position.fret < state.capo ||
      position.fret > state.numFrets) {
    return false;
  }
  return tuning.strings[position.stringIndex].midiNote + position.fret ==
      midiNote;
}

/// MIDI pitches available in the selected Piano range.
Set<int> playablePianoMidis(PianoRangeName rangeName) {
  final range = pianoRanges[rangeName];
  if (range == null) return const {};
  return {for (var midi = range.startMidi; midi <= range.endMidi; midi++) midi};
}

/// MIDI pitches available on the selected Fretboard under the current tuning,
/// capo, and fret count.
Set<int> playableFretboardMidis(FretboardState state) {
  final tuning = tunings[state.currentTuning];
  if (tuning == null) return const {};
  return {
    for (final string in tuning.strings)
      for (var fret = state.capo; fret <= state.numFrets; fret++)
        string.midiNote + fret,
  };
}

/// True when the selected instrument can play every note in [pattern].
bool canOpenOnInstrument({
  required NotePattern pattern,
  required HarmonyLaneInstrument instrument,
  required PianoRangeName pianoRange,
  required FretboardState fretboard,
}) {
  final playable = instrument == HarmonyLaneInstrument.piano
      ? playablePianoMidis(pianoRange)
      : playableFretboardMidis(fretboard);
  return pattern.notes.every((note) => playable.contains(note.midiNote));
}

/// Drops deleted, pitch-changed, or currently unplayable fret positions while
/// preserving positions whose note ID and MIDI pitch remain valid.
Map<String, FretboardNotePosition> reconcileFretboardPositions({
  required NotePattern pattern,
  required Map<String, FretboardNotePosition> positions,
  required FretboardState state,
}) {
  final notesById = {for (final note in pattern.notes) note.id: note};
  return {
    for (final entry in positions.entries)
      if (notesById[entry.key] case final note?)
        if (isValidFretboardNotePosition(
          midiNote: note.midiNote,
          position: entry.value,
          state: state,
        ))
          entry.key: entry.value,
  };
}
