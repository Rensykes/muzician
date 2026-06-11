/// Song Playback Transport Models
///
/// Immutable state types for the dedicated song playback transport,
/// completely separate from the editor [SongProject].
library;

import 'song_project.dart';

/// Transport status for the song playback engine.
enum SongPlaybackStatus { idle, playing, completed, error }

/// A single playback event: fire the grouped notes and drum lanes at [tick].
class SongPlaybackEvent {
  final int tick;

  /// Same-tick notes bucketed by their track's playback volume.
  final List<({double volume, List<int> midiNotes})> noteGroups;
  final List<({double volume, List<DrumLaneId> drumLanes})> drumGroups;

  const SongPlaybackEvent({
    required this.tick,
    this.noteGroups = const [],
    this.drumGroups = const [],
  });

  /// Flattened, sorted view across all volume groups.
  List<int> get midiNotes =>
      ([for (final g in noteGroups) ...g.midiNotes]..sort());

  List<DrumLaneId> get drumLanes => [
    for (final g in drumGroups) ...g.drumLanes,
  ];
}

/// Immutable transport state for the song playback engine.
class SongPlaybackState {
  final SongPlaybackStatus status;
  final int? currentTick;
  final int? startTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;

  /// Half-open loop region; both null when no loop is set.
  final int? loopStartTick;
  final int? loopEndTickExclusive;

  /// Practice tempo scale: 1.0 (normal), 0.75 or 0.5.
  final double tempoMultiplier;

  /// When true, playback starts with a one-measure metronome count-in.
  final bool countInEnabled;

  const SongPlaybackState({
    this.status = SongPlaybackStatus.idle,
    this.currentTick,
    this.startTick,
    this.endTickExclusive,
    this.message,
    this.errorMessage,
    this.loopStartTick,
    this.loopEndTickExclusive,
    this.tempoMultiplier = 1.0,
    this.countInEnabled = false,
  });

  bool get hasLoop => loopStartTick != null && loopEndTickExclusive != null;

  SongPlaybackState copyWith({
    SongPlaybackStatus? status,
    int? Function()? currentTick,
    int? Function()? startTick,
    int? Function()? endTickExclusive,
    String? Function()? message,
    String? Function()? errorMessage,
    int? Function()? loopStartTick,
    int? Function()? loopEndTickExclusive,
    double? tempoMultiplier,
    bool? countInEnabled,
  }) => SongPlaybackState(
    status: status ?? this.status,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
    startTick: startTick != null ? startTick() : this.startTick,
    endTickExclusive: endTickExclusive != null
        ? endTickExclusive()
        : this.endTickExclusive,
    message: message != null ? message() : this.message,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    loopStartTick: loopStartTick != null ? loopStartTick() : this.loopStartTick,
    loopEndTickExclusive: loopEndTickExclusive != null
        ? loopEndTickExclusive()
        : this.loopEndTickExclusive,
    tempoMultiplier: tempoMultiplier ?? this.tempoMultiplier,
    countInEnabled: countInEnabled ?? this.countInEnabled,
  );
}
