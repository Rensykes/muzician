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
import '../schema/rules/piano_roll_playback_rules.dart' as rules;
import '../utils/note_player.dart';
import '../utils/tick_pacer.dart';

/// Signature for a function that plays [lanes] as drum voices at [volume].
typedef DrumPatternPlaybackSink =
    Future<void> Function(List<DrumLaneId> lanes, double volume);

/// Injected playback sink backed by [NotePlayer].  Override in tests to capture
/// events without real audio.
final drumPatternPlaybackSinkProvider = Provider<DrumPatternPlaybackSink>((
  ref,
) {
  return (lanes, volume) async {
    for (final lane in lanes) {
      NotePlayer.instance.playDrumLane(lane, volume: volume);
    }
  };
});

/// Signature for a function that sounds a chord/voicing backing stab.
typedef DrumPatternBackingSink = void Function(List<int> midiNotes);

/// Injected backing sink backed by [NotePlayer].  Override in tests to capture
/// the chord stabs that play under the pattern during "audition with backing".
final drumPatternBackingSinkProvider = Provider<DrumPatternBackingSink>((ref) {
  return (midiNotes) {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6);
    }
  };
});

/// Descriptor for the drum editor's "audition with backing": the section loop
/// length in ticks and a `tick → midi pitches` chord bed that loops under the
/// pattern.
typedef DrumBackingDescriptor = ({int loopTicks, Map<int, List<int>> notesByTick});

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
  /// pattern is empty.
  ///
  /// Solo (default): the loop wraps after [DrumPattern.lengthTicks]. When
  /// [backingNotes] + [loopTicks] are given (the drum editor's "audition with
  /// backing"), the loop wraps after [loopTicks] instead; the drum pattern tiles
  /// within it (`tick % length`) and the chord stabs in [backingNotes] fire via
  /// [drumPatternBackingSinkProvider]. Runs until [stop] is called.
  Future<void> start({
    required DrumPattern pattern,
    required int tempo,
    Map<int, List<int>>? backingNotes,
    int? loopTicks,
  }) async {
    if (state.status == DrumPatternPlaybackStatus.playing) return;
    final length = pattern.lengthTicks;
    if (length <= 0) return;
    final loop = (loopTicks != null && loopTicks > 0) ? loopTicks : length;

    final sink = ref.read(drumPatternPlaybackSinkProvider);
    final backingSink = ref.read(drumPatternBackingSinkProvider);

    final lanesByTick = <int, List<DrumLaneId>>{};
    for (final lane in pattern.lanes) {
      for (final tick in lane.activeTicks) {
        (lanesByTick[tick] ??= <DrumLaneId>[]).add(lane.laneId);
      }
    }

    // Sixteenth-grid tick: a quarter note spans 4 ticks, so one tick is a
    // sixteenth.
    final tickDuration = rules.tickDuration(tempo);

    final version = ++_version;
    state = const DrumPatternPlaybackState(
      status: DrumPatternPlaybackStatus.playing,
      currentTick: 0,
    );

    // [TickPacer] anchors each tick to the wall clock so per-tick body work
    // (state mutation → rebuilds, the sinks) cannot accumulate into drift.
    final pacer = TickPacer(tickDuration);
    var tick = 0;
    // elapsedTicks increases monotonically so TickPacer's boundary never resets
    // across loop wraps (both `tick % loop` and `drumTick = tick % length`).
    var elapsedTicks = 0;
    while (_version == version) {
      final drumTick = tick % length;
      // Keep the grid highlight inside the pattern even when the backing loop is
      // longer than the pattern.
      state = state.copyWith(currentTick: () => drumTick);
      final lanes = lanesByTick[drumTick];
      if (lanes != null && lanes.isNotEmpty) {
        unawaited(sink(lanes, 0.8));
      }
      if (backingNotes != null) {
        final notes = backingNotes[tick];
        if (notes != null && notes.isNotEmpty) backingSink(notes);
      }
      await pacer.awaitBoundary(++elapsedTicks);
      if (_version != version) return;
      tick = (tick + 1) % loop;
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
