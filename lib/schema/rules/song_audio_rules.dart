/// Pure functions linking audio assets to the project's tick grid.
library;

import 'dart:math' as math;

import '../../models/piano_roll.dart';
import '../../models/song_project.dart';
import 'song_rules.dart' show songTicksPerMeasure;

int _ticksPerBeat(TimeSignature ts) => ts.beatUnit == 8 ? 2 : 4;

/// Returns the grid length, in ticks, that the given asset should occupy at
/// the project's current tempo.  Audio always plays at native rate, so the
/// real duration is the source of truth and this is a derived view.
int audioClipLengthTicks(AudioAsset asset, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final ticks =
      (asset.durationMs / 1000.0) * beatsPerSecond * ticksPerBeat;
  return math.max(1, ticks.round());
}

/// Returns the wall-clock time, in milliseconds since transport start, of the
/// given absolute tick at the project's current tempo.
int audioTickToMs(int tick, SongProjectConfig config) {
  final beatsPerSecond = config.tempo / 60.0;
  final ticksPerBeat = _ticksPerBeat(config.timeSignature);
  final beats = tick / ticksPerBeat;
  return (beats / beatsPerSecond * 1000.0).round();
}

/// Ensures the project's total measure count covers the given end tick — same
/// behaviour as the note/drum side, exposed here so the audio paths do not
/// need to import `song_rules` directly.
int requiredMeasuresForEndTick(int endTick, SongProjectConfig config) {
  final perMeasure = songTicksPerMeasure(config.timeSignature);
  return math.max(config.totalMeasures, (endTick / perMeasure).ceil());
}
