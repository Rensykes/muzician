/// Pure clip-split rules: slice a note/drum pattern at a local tick into two
/// independent patterns (the store turns these into unique clips).
library;

import '../../models/song_project.dart';

/// Splits [pattern] at local [tick] into left ([0, tick)) and right
/// ([tick, length)) patterns with the given ids.
///
/// A note straddling the boundary is cut in two: the left keeps the head,
/// the right starts at 0 with the remainder. Returns null when [tick] is not
/// strictly inside the pattern.
({NotePattern left, NotePattern right})? splitNotePattern(
  NotePattern pattern,
  int tick, {
  required String leftId,
  required String rightId,
}) {
  if (tick <= 0 || tick >= pattern.lengthTicks) return null;

  final leftNotes = <NotePatternNote>[];
  final rightNotes = <NotePatternNote>[];
  for (final note in pattern.notes) {
    final end = note.startTick + note.durationTicks;
    if (end <= tick) {
      leftNotes.add(note);
    } else if (note.startTick >= tick) {
      rightNotes.add(
        note.copyWith(id: '${note.id}.r', startTick: note.startTick - tick),
      );
    } else {
      // Straddling: head stays left, tail moves right.
      leftNotes.add(
        note.copyWith(id: '${note.id}.l', durationTicks: tick - note.startTick),
      );
      rightNotes.add(
        note.copyWith(id: '${note.id}.r', startTick: 0, durationTicks: end - tick),
      );
    }
  }

  return (
    left: pattern.copyWith(
      id: leftId,
      name: '${pattern.name} ◂',
      lengthTicks: tick,
      notes: leftNotes,
    ),
    right: pattern.copyWith(
      id: rightId,
      name: '${pattern.name} ▸',
      lengthTicks: pattern.lengthTicks - tick,
      notes: rightNotes,
    ),
  );
}

/// Drum equivalent of [splitNotePattern]; hits are instantaneous so they
/// partition cleanly. Lanes that end up empty are dropped.
({DrumPattern left, DrumPattern right})? splitDrumPattern(
  DrumPattern pattern,
  int tick, {
  required String leftId,
  required String rightId,
}) {
  if (tick <= 0 || tick >= pattern.lengthTicks) return null;

  final leftLanes = <DrumLaneSequence>[];
  final rightLanes = <DrumLaneSequence>[];
  for (final lane in pattern.lanes) {
    final leftTicks = [
      for (final t in lane.activeTicks)
        if (t < tick) t,
    ];
    final rightTicks = [
      for (final t in lane.activeTicks)
        if (t >= tick) t - tick,
    ];
    if (leftTicks.isNotEmpty) {
      leftLanes.add(lane.copyWith(activeTicks: leftTicks));
    }
    if (rightTicks.isNotEmpty) {
      rightLanes.add(lane.copyWith(activeTicks: rightTicks));
    }
  }

  return (
    left: pattern.copyWith(
      id: leftId,
      name: '${pattern.name} ◂',
      lengthTicks: tick,
      lanes: leftLanes,
    ),
    right: pattern.copyWith(
      id: rightId,
      name: '${pattern.name} ▸',
      lengthTicks: pattern.lengthTicks - tick,
      lanes: rightLanes,
    ),
  );
}
