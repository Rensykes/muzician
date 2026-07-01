/// Songwriter transport: a tick clock that drives a playhead, a metronome,
/// and the project's audible events — harmony chord stabs, save-block
/// voicings, and drum lane patterns (see [flattenPlaybackEvents]).
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_project.dart' show AudioAsset;
import '../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../schema/rules/songwriter_audio_rules.dart';
import '../schema/rules/songwriter_playback_rules.dart';
import '../schema/rules/songwriter_rules.dart';
import '../utils/note_player.dart';
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'save_system_store.dart';
import 'settings_store.dart';
import 'songwriter_audio_audition_store.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_store.dart';

typedef SongwriterMetronomeSink = Future<void> Function({required bool accent});

final songwriterMetronomeSinkProvider = Provider<SongwriterMetronomeSink>((
  ref,
) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});

/// Sink that sounds a chord / voicing stab. Override in tests.
typedef SongwriterNoteSink = void Function(List<int> midiNotes);

final songwriterNoteSinkProvider = Provider<SongwriterNoteSink>((ref) {
  return (midiNotes) {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6);
    }
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
  }) => SongwriterPlaybackState(
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

  Future<void> startPlayback({
    int startTick = 0,
    Duration? tickDurationOverride,
  }) async {
    if (state.status == SongwriterPlaybackStatus.playing) return;
    ref.read(songwriterAudioAuditionProvider.notifier).stop();

    final project = ref.read(songwriterProvider);
    final settings = ref.read(settingsProvider);
    final metronomeSink = ref.read(songwriterMetronomeSinkProvider);
    final noteSink = ref.read(songwriterNoteSinkProvider);
    final drumSink = ref.read(drumPatternPlaybackSinkProvider);
    final events = flattenPlaybackEvents(
      project,
      ref.read(saveSystemProvider).saves,
    );

    final cfg = project.config;
    final beatTicks = cfg.ticksPerBeat;
    final measureTicks = cfg.measureTicks;
    final totalBars = flattenedBarCount(project.sections);
    final endTick = totalBars * measureTicks;
    final metronomeOn = settings.metronomeEnabled;
    final tickDuration =
        tickDurationOverride ?? pr_rules.tickDuration(cfg.tempo);

    if (endTick <= 0) {
      state = state.copyWith(status: SongwriterPlaybackStatus.completed);
      return;
    }

    final version = ++_version;

    final audioSink = ref.read(songwriterAudioClipSinkProvider);
    // Already sorted by startMs by the rule.
    final scheduled = songwriterSchedulableAudioClips(project);
    final pendingAudioStops = <(AudioAsset, int)>[];
    await audioSink.prepare(scheduled.map((c) => c.asset));
    // A Stop issued during the (awaited) prepare must abort before we flip the
    // transport to "playing" — otherwise the loop exits immediately on the
    // version check and the UI stays stuck showing "playing".
    if (_version != version) return;
    var nextClip = 0;
    void fireAudio(int tick) {
      final nowMs = songwriterAudioTickToMs(tick, cfg);
      while (nextClip < scheduled.length &&
          scheduled[nextClip].startMs <= nowMs) {
        final clip = scheduled[nextClip++];
        // A mid-song start (startTick > 0) can skip past clips that both start
        // and end before it; don't briefly start-then-stop such a clip (the
        // fire-and-forget start/stop race can blip audio).
        if (clip.endMs <= nowMs) continue;
        unawaited(
          audioSink.startClip(
            asset: clip.asset,
            offsetMs: clip
                .offsetIntoAsset(nowMs)
                .clamp(0, clip.asset.durationMs),
            volume: clip.volume,
            loop: clip.loop,
          ),
        );
        pendingAudioStops.add((clip.asset, clip.endMs));
      }
      pendingAudioStops.removeWhere((p) {
        if (p.$2 <= nowMs) {
          unawaited(audioSink.stopClip(asset: p.$1));
          return true;
        }
        return false;
      });
    }

    final start = startTick < 0
        ? 0
        : (startTick > endTick ? endTick : startTick);
    if (start >= endTick) {
      state = state.copyWith(status: SongwriterPlaybackStatus.completed);
      return;
    }

    state = SongwriterPlaybackState(
      status: SongwriterPlaybackStatus.playing,
      currentTick: start,
      totalTicks: endTick,
      measureTicks: measureTicks,
    );

    // [TickPacer] anchors each tick to the wall clock so the body's work
    // (state mutation → rebuilds, sinks, the active-position provider) cannot
    // accumulate into drift. Pace off a 0-based [elapsedTicks] counter, not the
    // absolute tick — otherwise a mid-song start would wait tickDuration*start
    // before the first tick.
    final pacer = TickPacer(tickDuration);
    var eventIndex = 0;
    // Skip events before the start tick so a mid-song start doesn't replay them.
    while (eventIndex < events.length && events[eventIndex].tick < start) {
      eventIndex++;
    }
    var elapsedTicks = 0;
    for (var tick = start; tick < endTick; tick++) {
      if (_version != version) return;
      if (elapsedTicks > 0) await pacer.awaitBoundary(elapsedTicks);
      if (_version != version) return;
      state = state.copyWith(currentTick: () => tick);
      if (metronomeOn && tick % beatTicks == 0) {
        unawaited(metronomeSink(accent: tick % measureTicks == 0));
      }
      while (eventIndex < events.length && events[eventIndex].tick == tick) {
        final event = events[eventIndex];
        eventIndex++;
        if (event.midiNotes.isNotEmpty) noteSink(event.midiNotes);
        if (event.drumLanes.isNotEmpty) {
          unawaited(drumSink(event.drumLanes, 0.8));
        }
      }
      fireAudio(tick);
      elapsedTicks++;
    }
    if (_version != version) return;
    for (final p in pendingAudioStops) {
      unawaited(audioSink.stopClip(asset: p.$1));
    }
    state = state.copyWith(
      status: SongwriterPlaybackStatus.completed,
      currentTick: () => endTick,
    );
  }

  void stopPlayback() {
    _version++;
    unawaited(ref.read(songwriterAudioClipSinkProvider).stopAll());
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

/// Sheet-space playhead position, or null when the transport is idle.
final songwriterActivePositionProvider = Provider<SongwriterActivePosition?>((
  ref,
) {
  // Select only (status, bar): the position changes per bar, so watching the
  // whole state would recompute expandSections on every tick.
  final (status, bar) = ref.watch(
    songwriterPlaybackProvider.select((p) => (p.status, p.currentBar)),
  );
  if (status != SongwriterPlaybackStatus.playing || bar == null) {
    return null;
  }
  final sections = ref.watch(songwriterProvider.select((p) => p.sections));
  return activePositionForBar(sections, bar);
});

/// Fractional position within the current bar, in `[0, 1)`, for a smoothly
/// sweeping playhead. Updates every tick (unlike [currentBar]), so only the
/// active row's playhead overlay should watch it.
final songwriterPlayheadFracProvider = Provider<double>((ref) {
  final (tick, measureTicks) = ref.watch(
    songwriterPlaybackProvider.select((p) => (p.currentTick, p.measureTicks)),
  );
  if (tick == null || measureTicks <= 0) return 0.0;
  return (tick % measureTicks) / measureTicks;
});

/// The parked playback start tick, set by the per-section ruler and read by the
/// header Play button. Persists while idle (the transport state resets on stop).
/// 0 means "top of the song".
class SongwriterStartTickNotifier extends Notifier<int> {
  @override
  int build() {
    // The parked tick is an absolute position on the flattened timeline, so it
    // is meaningless once a different project loads. Clear it on project switch
    // — otherwise the header Play button resumes the new song from the previous
    // song's bar (or jumps straight to its end).
    ref.listen<String?>(
      saveSystemProvider.select((s) => s.selectedProjectId),
      (prev, next) {
        if (prev != next) state = 0;
      },
    );
    return 0;
  }

  void setTick(int tick) => state = tick < 0 ? 0 : tick;
  void reset() => state = 0;
}

final songwriterStartTickProvider =
    NotifierProvider<SongwriterStartTickNotifier, int>(
      SongwriterStartTickNotifier.new,
    );
