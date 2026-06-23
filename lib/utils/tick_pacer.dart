/// Drift-free transport pacing against a wall clock.
///
/// A fixed per-tick `Future.delayed(tickDuration)` lets each tick's body work
/// (state mutation → widget rebuilds, audio sinks, scheduling jitter) pile up
/// *between* the delays, so a tick loop runs progressively late — the playback
/// "loses tempo." [TickPacer] anchors every tick to the wall clock instead:
/// boundary `n` is due at `tickDuration * n` from construction, and
/// [awaitBoundary] waits only the time still remaining. When the loop has
/// fallen behind, it returns without adding any wait, so the schedule
/// self-corrects rather than accumulating drift.
///
/// Shared by every playback transport (piano roll, song, songwriter, drum
/// audition) so the timing invariant lives in exactly one place.
library;

import 'dart:async';

class TickPacer {
  /// Starts the wall clock immediately. Process tick 0 right away (no
  /// [awaitBoundary] call), then gate each later tick on its boundary.
  TickPacer(this.tickDuration) : _clock = Stopwatch()..start();

  /// Ideal wall-clock spacing between consecutive ticks.
  final Duration tickDuration;

  final Stopwatch _clock;

  /// Waits until boundary [n] — i.e. `n` ticks from the clock start — is due.
  ///
  /// [n] must be monotonically non-decreasing across calls. For loops that
  /// wrap (e.g. a looping audition), pass a count that keeps rising across the
  /// wrap so the schedule never resets and drift cannot creep back in.
  Future<void> awaitBoundary(int n) {
    final lag = tickDuration * n - _clock.elapsed;
    return Future<void>.delayed(lag > Duration.zero ? lag : Duration.zero);
  }
}
