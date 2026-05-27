/// Song Import Rules
/// Pure, UI-free helpers for importing instrument snapshots into song patterns.
library;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import 'piano_roll_import_rules.dart' as piano_roll_import_rules;

/// Converts an [InstrumentSnapshot] into a [NotePattern] suitable for placement
/// on a song note track.
///
/// For [PianoRollSnapshot], exact note timings (startTick, durationTicks) are
/// preserved, and the pattern's [NotePattern.lengthTicks] is derived from the
/// furthest note end rounded up to an even [songMeasureTicks] boundary.
///
/// For [PianoSnapshot] and [FretboardSnapshot], selected notes are mapped via
/// [piano_roll_import_rules.extractSnapshotImportMidis] with exact-pitch-class
/// mode enabled. The resulting MIDI stack is placed at tick 0 with
/// [fallbackLengthTicks] duration.
///
/// Other [InstrumentSnapshot] subtypes are treated like Piano/Fretboard: an
/// empty MIDI stack produces an empty pattern of [fallbackLengthTicks].
NotePattern notePatternFromSnapshot(
  InstrumentSnapshot snapshot, {
  required String patternId,
  required String patternName,
  required int songMeasureTicks,
  required int fallbackLengthTicks,
}) {
  if (snapshot is PianoRollSnapshot) {
    // Import exact notes from piano roll
    final notes = snapshot.notes.map((note) {
      return NotePatternNote(
        id: '${patternId}_${note['startTick']}_${note['midiNote']}',
        midiNote: note['midiNote'] as int,
        startTick: note['startTick'] as int,
        durationTicks: note['durationTicks'] as int,
      );
    }).toList();
    final furthestEndTick = notes.isEmpty
        ? fallbackLengthTicks
        : notes
              .map((n) => n.startTick + n.durationTicks)
              .reduce((a, b) => a > b ? a : b);
    final roundedLength =
        ((furthestEndTick + songMeasureTicks - 1) ~/ songMeasureTicks) *
        songMeasureTicks;
    return NotePattern(
      id: patternId,
      name: patternName,
      lengthTicks: roundedLength.clamp(songMeasureTicks, 512),
      notes: notes,
      pitchRangeStart: snapshot.pitchRangeStart,
      pitchRangeEnd: snapshot.pitchRangeEnd,
      snapTicks: snapshot.snapTicks,
      highlightedNotes: List<String>.from(snapshot.highlightedNotes),
    );
  }

  // For PianoSnapshot, FretboardSnapshot, and other subtypes: extract MIDI stack
  final midiStack =
      piano_roll_import_rules.extractSnapshotImportMidis(
        snapshot,
        exactPitchClassMode: true,
      ) ??
      const <int>[];
  return NotePattern(
    id: patternId,
    name: patternName,
    lengthTicks: fallbackLengthTicks,
    notes: [
      for (final midi in midiStack)
        NotePatternNote(
          id: '${patternId}_$midi',
          midiNote: midi,
          startTick: 0,
          durationTicks: fallbackLengthTicks,
        ),
    ],
    pitchRangeStart: 48,
    pitchRangeEnd: 84,
    snapTicks: 1,
    highlightedNotes: const [],
  );
}
