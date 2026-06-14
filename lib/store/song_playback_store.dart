/// Song Playback Transport Store
///
/// Dedicated transport provider that reads the [SongProject] at start time,
/// expands it into playback events, and drives the tick loop.  All audio
/// output goes through the injected [songNotePlaybackSinkProvider] and
/// [songDrumPlaybackSinkProvider] so that tests can capture events without
/// real audio.
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_playback.dart';
import '../models/song_project.dart';
import '../schema/rules/song_audio_rules.dart';
import '../schema/rules/song_playback_rules.dart' as pb_rules;
import '../schema/rules/song_rules.dart' as song_rules;
import '../utils/note_player.dart';
import 'settings_store.dart';
import 'song_project_store.dart';

/// Signature for a function that plays [midiNotes] as a chord at [volume].
typedef SongNotePlaybackSink =
    Future<void> Function(List<int> midiNotes, double volume);

/// Signature for a function that plays [lanes] as drum voices at [volume].
typedef SongDrumPlaybackSink =
    Future<void> Function(List<DrumLaneId> lanes, double volume);

/// Note playback sink backed by [NotePlayer]. Override in tests to capture events.
final songNotePlaybackSinkProvider = Provider<SongNotePlaybackSink>((ref) {
  return (midiNotes, volume) async {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: volume);
    }
  };
});

final songDrumPlaybackSinkProvider = Provider<SongDrumPlaybackSink>((ref) {
  return (lanes, volume) async {
    for (final lane in lanes) {
      NotePlayer.instance.playDrumLane(lane, volume: volume);
    }
  };
});

/// Sink for audio clips on audio tracks.  The default implementation is a
/// no-op so unit tests do not need to touch real audio playback; production
/// code overrides this with [AudioPlayersClipSink].
abstract class SongAudioClipSink {
  /// Pre-warm internal players so the tick loop's [startClip] calls can fire
  /// in parallel without racing on platform-channel source preparation.  The
  /// production implementation pre-loads one `AudioPlayer` per asset; the
  /// no-op default returns immediately.
  Future<void> prepare(Iterable<AudioAsset> assets);
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
  });
  Future<void> stopClip({required AudioAsset asset});
  Future<void> stopAll();
}

class _NoopAudioSink implements SongAudioClipSink {
  const _NoopAudioSink();
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
  }) async {}
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async {}
}

/// Metronome click sink for the Song transport. Override in tests.
typedef SongMetronomeSink = Future<void> Function({required bool accent});

final songMetronomeSinkProvider = Provider<SongMetronomeSink>((ref) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});

final songAudioClipSinkProvider = Provider<SongAudioClipSink>(
  (ref) => const _NoopAudioSink(),
);

class _PendingAudioStop {
  final AudioAsset asset;
  final int stopAtMs;
  _PendingAudioStop(this.asset, this.stopAtMs);
}

/// Riverpod notifier for the song playback transport.
///
/// Snapshots the [SongProject] at the moment [startPlayback] is called so
/// that mid-run edits do not affect the active playback.  Uses an internal
/// version counter for cancellation.
class SongPlaybackNotifier extends Notifier<SongPlaybackState> {
  int _playbackVersion = 0;

  @override
  SongPlaybackState build() => const SongPlaybackState();

  /// Starts playback from [startTick] through [endTickExclusive].
  ///
  /// Returns early without starting transport if already playing or if the
  /// requested range is empty. Honors the state's loop region (wrapping the
  /// tick clock), tempo multiplier, count-in, and the settings metronome.
  Future<void> startPlayback({
    int? startTick,
    int? endTickExclusive,
    Duration? tickDurationOverride,
  }) async {
    if (state.status == SongPlaybackStatus.playing) return;

    // ── Snapshot project state at start ────────────────────────────────────
    final project = ref.read(songProjectProvider);
    final noteSink = ref.read(songNotePlaybackSinkProvider);
    final drumSink = ref.read(songDrumPlaybackSinkProvider);
    final audioSink = ref.read(songAudioClipSinkProvider);
    final metronomeSink = ref.read(songMetronomeSinkProvider);
    final metronomeOn = ref.read(settingsProvider).metronomeEnabled;
    final allScheduled = schedulableAudioClips(project)
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final scheduled = [...allScheduled];
    final pendingStops = <_PendingAudioStop>[];

    // Pre-load every audio player synchronously before the tick loop so the
    // parallel startClip calls in fireAudioForTick only have to seek + resume
    // — eliminates the iOS race where two concurrent setSource calls cause
    // one player to silently never start.
    await audioSink.prepare(scheduled.map((c) => c.asset));

    final totalTicks = song_rules.songTotalTicks(project.config);
    final start = startTick ?? 0;
    final end = endTickExclusive ?? totalTicks;

    if (start >= end) return;

    final events = pb_rules.buildPlaybackEvents(project);
    final multiplier = state.tempoMultiplier;
    final baseTickDuration =
        tickDurationOverride ??
        Duration(milliseconds: ((60000 / project.config.tempo) / 4).round());
    final tickDuration = multiplier == 1.0
        ? baseTickDuration
        : Duration(
            microseconds: (baseTickDuration.inMicroseconds / multiplier)
                .round(),
          );
    final beatTicks = project.config.timeSignature.beatUnit == 8 ? 2 : 4;
    final measureTicks =
        beatTicks * project.config.timeSignature.beatsPerMeasure;

    // ── Cancel any previous playback ───────────────────────────────────────
    final version = ++_playbackVersion;

    state = state.copyWith(
      status: SongPlaybackStatus.playing,
      startTick: () => start,
      endTickExclusive: () => end,
      currentTick: () => start,
      message: () => null,
      errorMessage: () => null,
    );

    try {
      // Filter events to the requested range.
      final rangeEvents = events
          .where((e) => e.tick >= start && e.tick < end)
          .toList();
      int eventIndexAtOrAfter(int tick) {
        var i = 0;
        while (i < rangeEvents.length && rangeEvents[i].tick < tick) {
          i++;
        }
        return i;
      }

      // One-measure metronome count-in before the clock starts.
      if (state.countInEnabled && metronomeOn) {
        final beats = project.config.timeSignature.beatsPerMeasure;
        for (var beat = 0; beat < beats; beat++) {
          if (_playbackVersion != version) return;
          unawaited(metronomeSink(accent: beat == 0));
          await Future<void>.delayed(tickDuration * beatTicks);
        }
        if (_playbackVersion != version) return;
      }

      // Elapsed wall-clock ticks (keeps audio scheduling monotonic across
      // loop wraps).
      var elapsedTicks = 0;

      void fireAudioForTick(int tick) {
        final nowMs = audioTickToMs(tick, project.config);
        while (scheduled.isNotEmpty && scheduled.first.startMs <= nowMs) {
          final clip = scheduled.removeAt(0);
          unawaited(
            audioSink.startClip(
              asset: clip.asset,
              offsetMs: clip
                  .offsetIntoAsset(nowMs)
                  .clamp(0, clip.asset.durationMs),
              volume: clip.volume,
            ),
          );
          pendingStops.add(_PendingAudioStop(clip.asset, clip.endMs));
        }
        pendingStops.removeWhere((pending) {
          if (pending.stopAtMs <= nowMs) {
            unawaited(audioSink.stopClip(asset: pending.asset));
            return true;
          }
          return false;
        });
      }

      var tick = start;
      var eventIndex = 0;
      while (tick < end && _playbackVersion == version) {
        if (elapsedTicks > 0) await Future<void>.delayed(tickDuration);
        if (_playbackVersion != version) return;
        state = state.copyWith(currentTick: () => tick);

        if (metronomeOn && tick % beatTicks == 0) {
          unawaited(metronomeSink(accent: tick % measureTicks == 0));
        }

        // Fire all events at this tick.
        while (eventIndex < rangeEvents.length &&
            rangeEvents[eventIndex].tick == tick) {
          final event = rangeEvents[eventIndex];
          for (final group in event.noteGroups) {
            unawaited(noteSink(group.midiNotes, 0.8 * group.volume));
          }
          for (final group in event.drumGroups) {
            unawaited(drumSink(group.drumLanes, 0.8 * group.volume));
          }
          eventIndex++;
        }
        fireAudioForTick(tick);

        tick++;
        elapsedTicks++;

        // Loop wrap: jump back to the loop start, re-arm events and audio.
        final loopStart = state.loopStartTick;
        final loopEnd = state.loopEndTickExclusive;
        if (loopStart != null &&
            loopEnd != null &&
            tick == loopEnd &&
            loopStart < loopEnd) {
          tick = loopStart;
          eventIndex = eventIndexAtOrAfter(tick);
          unawaited(audioSink.stopAll());
          pendingStops.clear();
          final wrapMs = audioTickToMs(tick, project.config);
          scheduled
            ..clear()
            ..addAll(allScheduled.where((c) => c.startMs >= wrapMs));
        }
      }

      // Flush any audio still queued past the loop end.
      for (final pending in pendingStops) {
        unawaited(audioSink.stopClip(asset: pending.asset));
      }
      pendingStops.clear();

      if (_playbackVersion == version) {
        // Let last notes decay.
        await Future<void>.delayed(
          Duration(milliseconds: (60000 / project.config.tempo).round()),
        );
        state = state.copyWith(
          status: SongPlaybackStatus.completed,
          currentTick: () => null,
          startTick: () => null,
          endTickExclusive: () => null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: SongPlaybackStatus.error,
        errorMessage: () => e.toString(),
      );
    }
  }

  /// Sets (or replaces) the loop region. Ignored when the range is empty.
  void setLoopRegion(int startTick, int endTickExclusive) {
    if (endTickExclusive <= startTick) return;
    final s = startTick < 0 ? 0 : startTick;
    state = state.copyWith(
      loopStartTick: () => s,
      loopEndTickExclusive: () => endTickExclusive,
    );
  }

  void clearLoopRegion() {
    state = state.copyWith(
      loopStartTick: () => null,
      loopEndTickExclusive: () => null,
    );
  }

  /// Cycles the practice tempo: 1.0 → 0.75 → 0.5 → 1.0.
  void cycleTempoMultiplier() {
    final next = switch (state.tempoMultiplier) {
      1.0 => 0.75,
      0.75 => 0.5,
      _ => 1.0,
    };
    state = state.copyWith(tempoMultiplier: next);
  }

  void toggleCountIn() {
    state = state.copyWith(countInEnabled: !state.countInEnabled);
  }

  /// Moves the idle playhead cursor to [tick] without starting playback.
  ///
  /// If playback is active, it is stopped first (so the audible position does
  /// not fight the scrub) and the cursor is parked at [tick]; pressing play
  /// then resumes from there.  [tick] is clamped into the project's range.
  void seek(int tick) {
    final project = ref.read(songProjectProvider);
    final totalTicks = song_rules.songTotalTicks(project.config);
    final maxTick = totalTicks > 0 ? totalTicks - 1 : 0;
    final clamped = tick.clamp(0, maxTick);
    if (state.status == SongPlaybackStatus.playing) {
      _playbackVersion++;
      unawaited(ref.read(songAudioClipSinkProvider).stopAll());
    }
    state = state.copyWith(
      status: SongPlaybackStatus.idle,
      currentTick: () => clamped,
      startTick: () => null,
      endTickExclusive: () => null,
    );
  }

  /// Stops active playback and resets the transport to idle.
  ///
  /// Safe to call repeatedly; cancels any pending scheduled work via an
  /// internal version counter.
  void stopPlayback() {
    _playbackVersion++;
    unawaited(ref.read(songAudioClipSinkProvider).stopAll());
    state = state.copyWith(
      status: SongPlaybackStatus.idle,
      currentTick: () => null,
      startTick: () => null,
      endTickExclusive: () => null,
      message: () => null,
      errorMessage: () => null,
    );
  }
}

/// The song playback provider.  Widgets watch this for the current tick,
/// status, and error message.
final songPlaybackProvider =
    NotifierProvider<SongPlaybackNotifier, SongPlaybackState>(
      SongPlaybackNotifier.new,
    );
