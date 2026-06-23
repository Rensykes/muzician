/// Piano Roll Playback Timing Rules
///
/// Pure helpers for tick/duration math, note grouping, and playback bounds.
/// All functions are deterministic and testable without any Riverpod wiring.
library;

import '../../models/piano_roll.dart';
import '../../models/piano_roll_playback.dart';
import 'piano_roll_rules.dart' as pr;

/// Returns the tick where playback should start.
///
/// Uses the user-selected column if present; falls back to tick 0.
int resolvePlaybackStartTick(PianoRollState state) =>
    state.selectedColumnTick ?? 0;

/// Returns the exclusive end tick for playback — the full timeline end.
int resolvePlaybackEndTick(PianoRollState state) =>
    pr.totalTicks(state.config.timeSignature, state.config.totalMeasures);

/// Returns milliseconds per single tick at the given [tempo] (in BPM).
///
/// Formula: `60000 / tempo / ticksPerQuarter`
/// where [pr.ticksPerQuarter] is 4 (sixteenth-note grid).
double millisecondsPerTick(int tempo) => 60000 / tempo / pr.ticksPerQuarter;

/// Wall-clock [Duration] of a single tick at [tempo] BPM, microsecond-precise.
///
/// Microsecond precision (rather than rounding to whole milliseconds) keeps a
/// transport from accruing a constant tempo offset at tempos that don't divide
/// evenly — e.g. 140 BPM is 107.14µs/tick, not 107ms. Multiply by a tick count
/// for a span: `tickDuration(tempo) * ticks`.
Duration tickDuration(int tempo) =>
    Duration(microseconds: (millisecondsPerTick(tempo) * 1000).round());

/// Groups [notes] into a sorted list of [PianoRollPlaybackEvent]s.
///
/// * Only notes whose [PianoRollNote.startTick] >= [startTick] are included.
/// * Notes at the same tick are merged into one event with sorted, de-duplicated
///   MIDI note numbers.
/// * Events are returned in ascending tick order.
List<PianoRollPlaybackEvent> groupPlaybackEvents(
  List<PianoRollNote> notes,
  int startTick,
) {
  // Collect distinct MIDI note numbers per tick, filtering by startTick.
  final tickMap = <int, Set<int>>{};
  for (final note in notes) {
    if (note.startTick >= startTick) {
      tickMap.putIfAbsent(note.startTick, () => {}).add(note.midiNote);
    }
  }

  // Sort ticks ascending and build events.
  final sortedTicks = tickMap.keys.toList()..sort();
  return [
    for (final tick in sortedTicks)
      PianoRollPlaybackEvent(
        tick: tick,
        midiNotes: tickMap[tick]!.toList()..sort(),
      ),
  ];
}
