/// Piano Roll Playback Transport Models
///
/// Immutable state types for the dedicated playback transport,
/// completely separate from the editor [PianoRollState].
library;

/// Transport status for the piano roll playback engine.
///
///   * [idle] — ready to start playback.
///   * [playing] — actively iterating through events.
///   * [completed] — finished cleanly (reached end-of-timeline).
///   * [error] — stopped due to a problem captured in [PianoRollPlaybackState.errorMessage].
enum PianoRollPlaybackStatus { idle, playing, completed, error }

/// A single playback event: play [midiNotes] (as a chord) at [tick].
class PianoRollPlaybackEvent {
  final int tick;
  final List<int> midiNotes;

  const PianoRollPlaybackEvent({required this.tick, required this.midiNotes});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PianoRollPlaybackEvent &&
          tick == other.tick &&
          _listEquals(midiNotes, other.midiNotes);

  @override
  int get hashCode => Object.hash(tick, Object.hashAll(midiNotes));

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Immutable transport state for the piano roll playback engine.
class PianoRollPlaybackState {
  final PianoRollPlaybackStatus status;
  final int? startTick;
  final int? currentTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;

  const PianoRollPlaybackState({
    this.status = PianoRollPlaybackStatus.idle,
    this.startTick,
    this.currentTick,
    this.endTickExclusive,
    this.message,
    this.errorMessage,
  });

  PianoRollPlaybackState copyWith({
    PianoRollPlaybackStatus? status,
    int? Function()? startTick,
    int? Function()? currentTick,
    int? Function()? endTickExclusive,
    String? Function()? message,
    String? Function()? errorMessage,
  }) => PianoRollPlaybackState(
    status: status ?? this.status,
    startTick: startTick != null ? startTick() : this.startTick,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
    endTickExclusive: endTickExclusive != null
        ? endTickExclusive()
        : this.endTickExclusive,
    message: message != null ? message() : this.message,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}
