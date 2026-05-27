/// Song Playback Transport Models
///
/// Immutable state types for the dedicated song playback transport,
/// completely separate from the editor [SongProject].
library;

import 'song_project.dart';

/// Transport status for the song playback engine.
enum SongPlaybackStatus { idle, playing, completed, error }

/// A single playback event: fire [midiNotes] and [drumLanes] at [tick].
class SongPlaybackEvent {
  final int tick;
  final List<int> midiNotes;
  final List<DrumLaneId> drumLanes;

  const SongPlaybackEvent({
    required this.tick,
    required this.midiNotes,
    required this.drumLanes,
  });
}

/// Immutable transport state for the song playback engine.
class SongPlaybackState {
  final SongPlaybackStatus status;
  final int? currentTick;
  final int? startTick;
  final int? endTickExclusive;
  final String? message;
  final String? errorMessage;

  const SongPlaybackState({
    this.status = SongPlaybackStatus.idle,
    this.currentTick,
    this.startTick,
    this.endTickExclusive,
    this.message,
    this.errorMessage,
  });

  SongPlaybackState copyWith({
    SongPlaybackStatus? status,
    int? Function()? currentTick,
    int? Function()? startTick,
    int? Function()? endTickExclusive,
    String? Function()? message,
    String? Function()? errorMessage,
  }) => SongPlaybackState(
    status: status ?? this.status,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
    startTick: startTick != null ? startTick() : this.startTick,
    endTickExclusive: endTickExclusive != null
        ? endTickExclusive()
        : this.endTickExclusive,
    message: message != null ? message() : this.message,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}
