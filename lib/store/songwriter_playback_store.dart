/// Songwriter transport: a bar/tick clock that drives a playhead and a
/// metronome. v1 blocks are silent visual guides — no block audio.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../schema/rules/songwriter_rules.dart';
import '../utils/note_player.dart';
import 'settings_store.dart';
import 'songwriter_store.dart';

typedef SongwriterMetronomeSink = Future<void> Function({required bool accent});

final songwriterMetronomeSinkProvider = Provider<SongwriterMetronomeSink>((ref) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});

// ─── Transport State ─────────────────────────────────────────────────────────

enum SongwriterPlaybackStatus { idle, playing, completed }

class SongwriterPlaybackState {
  const SongwriterPlaybackState({
    this.status = SongwriterPlaybackStatus.idle,
    this.currentTick,
    this.totalTicks = 0,
    this.measureTicks = 4,
  });
  final SongwriterPlaybackStatus status;
  final int? currentTick;
  final int totalTicks;
  final int measureTicks;

  int? get currentBar =>
      currentTick == null ? null : currentTick! ~/ measureTicks;

  SongwriterPlaybackState copyWith({
    SongwriterPlaybackStatus? status,
    int? Function()? currentTick,
    int? totalTicks,
    int? measureTicks,
  }) =>
      SongwriterPlaybackState(
        status: status ?? this.status,
        currentTick: currentTick != null ? currentTick() : this.currentTick,
        totalTicks: totalTicks ?? this.totalTicks,
        measureTicks: measureTicks ?? this.measureTicks,
      );
}

// ─── Transport Notifier ──────────────────────────────────────────────────────

class SongwriterPlaybackNotifier extends Notifier<SongwriterPlaybackState> {
  int _version = 0;

  @override
  SongwriterPlaybackState build() => const SongwriterPlaybackState();

  Future<void> startPlayback({Duration? tickDurationOverride}) async {
    if (state.status == SongwriterPlaybackStatus.playing) return;

    final project = ref.read(songwriterProvider);
    final settings = ref.read(settingsProvider);
    final metronomeSink = ref.read(songwriterMetronomeSinkProvider);

    final cfg = project.config;
    final beatTicks = cfg.beatUnit == 8 ? 2 : 4;
    final measureTicks = beatTicks * cfg.beatsPerBar;
    final totalBars = flattenedBarCount(project.sections);
    final endTick = totalBars * measureTicks;
    final metronomeOn = settings.metronomeEnabled;
    final tickDuration =
        tickDurationOverride ?? pr_rules.durationForTickDelta(1, cfg.tempo);

    if (endTick <= 0) {
      state = state.copyWith(status: SongwriterPlaybackStatus.completed);
      return;
    }

    final version = ++_version;
    state = SongwriterPlaybackState(
      status: SongwriterPlaybackStatus.playing,
      currentTick: 0,
      totalTicks: endTick,
      measureTicks: measureTicks,
    );

    for (var tick = 0; tick < endTick; tick++) {
      if (_version != version) return;
      if (tick > 0) await Future<void>.delayed(tickDuration);
      if (_version != version) return;
      state = state.copyWith(currentTick: () => tick);
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }
    }
    if (_version != version) return;
    state = state.copyWith(
      status: SongwriterPlaybackStatus.completed,
      currentTick: () => endTick,
    );
  }

  void stopPlayback() {
    _version++;
    state = state.copyWith(
      status: SongwriterPlaybackStatus.idle,
      currentTick: () => null,
    );
  }
}

final songwriterPlaybackProvider =
    NotifierProvider<SongwriterPlaybackNotifier, SongwriterPlaybackState>(
  SongwriterPlaybackNotifier.new,
);
