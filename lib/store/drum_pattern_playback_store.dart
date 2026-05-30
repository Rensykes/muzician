/// Drum Pattern Playback Store
///
/// Dedicated, looping audition transport for a single [DrumPattern] inside the
/// drum machine editor.  Mirrors the structure of [pianoRollPlaybackProvider]:
/// all audio goes through an injected sink so tests can capture lane hits
/// without real audio, and an internal version counter cancels the loop.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_project.dart';
import '../utils/note_player.dart';

/// Signature for a function that plays [lanes] as drum voices at [volume].
typedef DrumPatternPlaybackSink =
    Future<void> Function(List<DrumLaneId> lanes, double volume);

/// Injected playback sink backed by [NotePlayer].  Override in tests to capture
/// events without real audio.
final drumPatternPlaybackSinkProvider = Provider<DrumPatternPlaybackSink>((ref) {
  return (lanes, volume) async {
    for (final lane in lanes) {
      NotePlayer.instance.playDrumLane(lane, volume: volume);
    }
  };
});

enum DrumPatternPlaybackStatus { idle, playing }

/// Immutable transport state for the drum pattern audition.
class DrumPatternPlaybackState {
  final DrumPatternPlaybackStatus status;

  /// The currently sounding step tick, or null when idle.  Drives the moving
  /// column highlight in the editor grid.
  final int? currentTick;

  const DrumPatternPlaybackState({
    this.status = DrumPatternPlaybackStatus.idle,
    this.currentTick,
  });

  DrumPatternPlaybackState copyWith({
    DrumPatternPlaybackStatus? status,
    int? Function()? currentTick,
  }) => DrumPatternPlaybackState(
    status: status ?? this.status,
    currentTick: currentTick != null ? currentTick() : this.currentTick,
  );
}

/// Riverpod notifier for the looping drum pattern audition.
class DrumPatternPlaybackNotifier extends Notifier<DrumPatternPlaybackState> {
  int _version = 0;

  @override
  DrumPatternPlaybackState build() => const DrumPatternPlaybackState();

  /// Starts looping [pattern] at [tempo] BPM.  No-op if already playing or the
  /// pattern is empty.  The loop wraps back to tick 0 after [DrumPattern.lengthTicks]
  /// and runs until [stop] is called.
  Future<void> start({
    required DrumPattern pattern,
    required int tempo,
  }) async {
    if (state.status == DrumPatternPlaybackStatus.playing) return;
    final length = pattern.lengthTicks;
    if (length <= 0) return;

    final sink = ref.read(drumPatternPlaybackSinkProvider);

    final lanesByTick = <int, List<DrumLaneId>>{};
    for (final lane in pattern.lanes) {
      for (final tick in lane.activeTicks) {
        (lanesByTick[tick] ??= <DrumLaneId>[]).add(lane.laneId);
      }
    }

    // Sixteenth-grid tick: a quarter note spans 4 ticks, so one tick is a
    // sixteenth.  ms = (60000 / tempo) / 4.
    final tickDuration = Duration(
      microseconds: ((60000000 / tempo) / 4).round(),
    );

    final version = ++_version;
    state = const DrumPatternPlaybackState(
      status: DrumPatternPlaybackStatus.playing,
      currentTick: 0,
    );

    var tick = 0;
    while (_version == version) {
      state = state.copyWith(currentTick: () => tick);
      final lanes = lanesByTick[tick];
      if (lanes != null && lanes.isNotEmpty) {
        unawaited(sink(lanes, 0.8));
      }
      await Future<void>.delayed(tickDuration);
      if (_version != version) return;
      tick = (tick + 1) % length;
    }
  }

  /// Stops the audition loop and resets to idle.  Safe to call repeatedly.
  void stop() {
    _version++;
    state = const DrumPatternPlaybackState();
  }
}

final drumPatternPlaybackProvider =
    NotifierProvider<DrumPatternPlaybackNotifier, DrumPatternPlaybackState>(
      DrumPatternPlaybackNotifier.new,
    );
