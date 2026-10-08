/// Songwriter transport: a tick clock that drives a playhead, a metronome,
/// and the project's audible events — harmony chord stabs, save-block
/// voicings, and drum lane patterns (see [flattenPlaybackEvents]).
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_project.dart' show AudioAsset;
import '../schema/rules/piano_roll_playback_rules.dart' as pr_rules;
import '../schema/rules/songwriter_audio_rules.dart';
import '../schema/rules/songwriter_playback_rules.dart';
import '../schema/rules/songwriter_rules.dart';
import '../utils/note_player.dart';
import '../utils/playback_profiling.dart';
import '../utils/tick_pacer.dart';
import 'drum_pattern_playback_store.dart';
import 'save_system_store.dart';
import 'settings_store.dart';
import 'songwriter_audio_audition_store.dart';
import 'songwriter_audio_sink.dart';
import 'songwriter_store.dart';

typedef SongwriterMetronomeSink = Future<void> Function({required bool accent});

/// In-memory diagnostic snapshot shared with the isolated profiling harness.
/// Release builds leave this unset and execute no profiling instrumentation.
final songwriterPlaybackProfileRunProvider =
    StateProvider<PlaybackProfileRunStats?>((ref) => null);

final songwriterMetronomeSinkProvider = Provider<SongwriterMetronomeSink>((
  ref,
) {
  return ({required bool accent}) async {
    NotePlayer.instance.playClick(accent: accent);
  };
});

/// Sink that sounds one chord / voicing stab at a lane mix bucket's [volume]
/// (0.0–1.0 lane gain, applied on top of the sink's own base level) and
/// [pan]. Mirrors [DrumPatternPlaybackSink]'s shape. Override in tests.
typedef SongwriterNoteSink =
    void Function(List<int> midiNotes, double volume, double pan);

final songwriterNoteSinkProvider = Provider<SongwriterNoteSink>((ref) {
  return (midiNotes, volume, pan) {
    for (final midi in midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6 * volume, pan: pan);
    }
  };
});

typedef SongwriterSequencedNoteSink =
    void Function({
      required int midiNote,
      required Duration duration,
      required Duration onsetDelay,
      required double volume,
      required double pan,
    });

typedef SongwriterSequencedNoteStopSink = void Function();

final songwriterSequencedNoteSinkProvider =
    Provider<SongwriterSequencedNoteSink>((ref) {
      return ({
        required int midiNote,
        required Duration duration,
        required Duration onsetDelay,
        required double volume,
        required double pan,
      }) {
        NotePlayer.instance.playSequencedNote(
          midiNote,
          duration: duration,
          onsetDelay: onsetDelay,
          volume: 0.6 * volume,
          pan: pan,
        );
      };
    });

final songwriterSequencedNoteStopSinkProvider =
    Provider<SongwriterSequencedNoteStopSink>(
      (ref) => NotePlayer.instance.stopSequencedNotes,
    );

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
  int _profileRunId = 0;

  @override
  SongwriterPlaybackState build() => const SongwriterPlaybackState();

  Future<void> startPlayback({
    int startTick = 0,
    Duration? tickDurationOverride,
    int? scoreTickLimit,
  }) async {
    if (state.status == SongwriterPlaybackStatus.playing) return;
    final runId = playbackProfilingEnabled ? ++_profileRunId : 0;
    final runTrace = playbackProfilingEnabled
        ? PlaybackProfileTask.begin(
            'writer.playback.run',
            arguments: {
              'run_id': runId,
              'build_mode': kProfileMode ? 'profile' : 'debug',
              'requested_start_tick': startTick,
              'tick_duration_override_us': tickDurationOverride?.inMicroseconds,
              'score_tick_limit': scoreTickLimit,
            },
          )
        : null;
    try {
      ref.read(songwriterAudioAuditionProvider.notifier).stop();

      final project = ref.read(songwriterProvider);
      final settings = ref.read(settingsProvider);
      final metronomeSink = ref.read(songwriterMetronomeSinkProvider);
      final noteSink = ref.read(songwriterNoteSinkProvider);
      final sequencedNoteSink = ref.read(songwriterSequencedNoteSinkProvider);
      final sequencedNoteStopSink = ref.read(
        songwriterSequencedNoteStopSinkProvider,
      );
      sequencedNoteStopSink();
      final drumSink = ref.read(drumPatternPlaybackSinkProvider);
      final saveState = ref.read(saveSystemProvider);
      final flattenWatch = playbackProfilingEnabled
          ? (Stopwatch()..start())
          : null;
      final events = flattenPlaybackEvents(
        project,
        saveState.saves,
        projectId: saveState.selectedProjectId,
        folders: saveState.folders,
        projectDefaultHarmonyInstrument: ref
            .read(songwriterProvider.notifier)
            .projectDefaultHarmonyInstrumentForSelectedProject,
      );
      final flattenDurationUs = flattenWatch?.elapsedMicroseconds;
      if (flattenWatch != null) {
        final noteCount = events.fold<int>(
          0,
          (count, event) =>
              count +
              event.noteGroups.fold<int>(
                0,
                (sum, group) => sum + group.midiNotes.length,
              ) +
              event.sequencedNoteGroups.fold<int>(
                0,
                (sum, group) => sum + group.notes.length,
              ),
        );
        final drumCount = events.fold<int>(
          0,
          (count, event) =>
              count +
              event.drumGroups.fold<int>(
                0,
                (sum, group) => sum + group.drumLanes.length,
              ),
        );
        runTrace?.instant(
          'writer.playback.flatten_complete',
          arguments: {
            'duration_us': flattenDurationUs,
            'event_count': events.length,
            'note_count': noteCount,
            'drum_count': drumCount,
          },
        );
      }

      final cfg = project.config;
      final beatTicks = cfg.ticksPerBeat;
      final measureTicks = cfg.measureTicks;
      final totalBars = flattenedBarCount(project.sections);
      final arrangementEndTick = totalBars * measureTicks;
      final endTick = playbackProfilingEnabled && scoreTickLimit != null
          ? scoreTickLimit < 0
                ? 0
                : scoreTickLimit > arrangementEndTick
                ? arrangementEndTick
                : scoreTickLimit
          : arrangementEndTick;
      final profileStartTick = startTick < 0
          ? 0
          : (startTick > endTick ? endTick : startTick);
      final metronomeOn = settings.metronomeEnabled;
      final tickDuration =
          tickDurationOverride ?? pr_rules.tickDuration(cfg.tempo);

      final profileRun = playbackProfilingEnabled
          ? PlaybackProfileRunStats(
              runId: runId,
              expectedVoiceCount: events
                  .where(
                    (event) =>
                        event.tick >= profileStartTick && event.tick < endTick,
                  )
                  .fold<int>(
                    0,
                    (count, event) =>
                        count +
                        event.noteGroups.fold<int>(
                          0,
                          (sum, group) => sum + group.midiNotes.length,
                        ) +
                        event.sequencedNoteGroups.fold<int>(
                          0,
                          (sum, group) => sum + group.notes.length,
                        ),
                  ),
            )
          : null;
      if (profileRun != null) {
        ref.read(songwriterPlaybackProfileRunProvider.notifier).state =
            profileRun;
      }

      if (endTick <= 0) {
        state = state.copyWith(status: SongwriterPlaybackStatus.completed);
        runTrace?.finish(arguments: {'result': 'empty_project'});
        return;
      }

      final version = ++_version;

      final audioSink = ref.read(songwriterAudioClipSinkProvider);
      // Already sorted by startMs by the rule.
      final clipScheduleWatch = playbackProfilingEnabled
          ? (Stopwatch()..start())
          : null;
      final scheduled = songwriterSchedulableAudioClips(project);
      final clipScheduleDurationUs = clipScheduleWatch?.elapsedMicroseconds;
      if (clipScheduleDurationUs != null) {
        runTrace?.instant(
          'writer.playback.schedule_clips_complete',
          arguments: {
            'duration_us': clipScheduleDurationUs,
            'clip_count': scheduled.length,
          },
        );
      }
      final pendingAudioStops = <(AudioAsset, int)>[];
      final clipPrepareTrace = playbackProfilingEnabled
          ? PlaybackProfileTask.begin(
              'writer.playback.prepare_clips',
              arguments: {
                'run_id': runId,
                'clip_count': scheduled.length,
                'asset_count': scheduled
                    .map((clip) => clip.asset.id)
                    .toSet()
                    .length,
              },
            )
          : null;
      try {
        await audioSink.prepare(scheduled.map((c) => c.asset));
        clipPrepareTrace?.finish(
          arguments: {'outcome': 'prepare_future_completed'},
        );
      } catch (error, stackTrace) {
        clipPrepareTrace?.finishError(error, stage: 'prepare');
        Error.throwWithStackTrace(error, stackTrace);
      }
      // A Stop issued during the (awaited) prepare must abort before we flip the
      // transport to "playing" — otherwise the loop exits immediately on the
      // version check and the UI stays stuck showing "playing".
      if (_version != version) {
        runTrace?.finish(arguments: {'result': 'stopped_during_clip_prepare'});
        return;
      }
      var nextClip = 0;
      Stopwatch? dispatchClock;
      List<int>? eventDispatchLatenessUs;
      void fireAudio(int tick, int elapsedTicks) {
        final nowMs = songwriterAudioTickToMs(tick, cfg);
        while (nextClip < scheduled.length &&
            scheduled[nextClip].startMs <= nowMs) {
          final clip = scheduled[nextClip++];
          // A mid-song start (startTick > 0) can skip past clips that both start
          // and end before it; don't briefly start-then-stop such a clip (the
          // fire-and-forget start/stop race can blip audio).
          if (clip.endMs <= nowMs) continue;
          final deadlineUs = dispatchClock == null
              ? null
              : elapsedTicks * tickDuration.inMicroseconds;
          final clipDispatchUs = dispatchClock?.elapsedMicroseconds;
          final clipDispatchLateUs =
              deadlineUs == null || clipDispatchUs == null
              ? null
              : (clipDispatchUs - deadlineUs).clamp(0, 1 << 62);
          if (clipDispatchLateUs != null) {
            runTrace?.instant(
              'writer.playback.clip_dispatch',
              arguments: {
                'run_id': runId,
                'tick': tick,
                'deadline_us': deadlineUs,
                'dispatch_lateness_us': clipDispatchLateUs,
                'offset_ms': clip
                    .offsetIntoAsset(nowMs)
                    .clamp(0, clip.asset.durationMs),
              },
            );
          }
          unawaited(
            audioSink.startClip(
              asset: clip.asset,
              offsetMs: clip
                  .offsetIntoAsset(nowMs)
                  .clamp(0, clip.asset.durationMs),
              volume: clip.volume,
              balance: clip.pan,
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

      final start = profileStartTick;
      if (start >= endTick) {
        state = state.copyWith(status: SongwriterPlaybackStatus.completed);
        runTrace?.finish(arguments: {'result': 'start_at_end'});
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
      dispatchClock = playbackProfilingEnabled ? (Stopwatch()..start()) : null;
      final dispatchLatenessUs = playbackProfilingEnabled ? <int>[] : null;
      final dispatchErrorUs = playbackProfilingEnabled ? <int>[] : null;
      eventDispatchLatenessUs = playbackProfilingEnabled ? <int>[] : null;
      final eventDispatchErrorUs = playbackProfilingEnabled ? <int>[] : null;
      runTrace?.instant(
        'writer.playback.clock_started',
        arguments: {
          'run_id': runId,
          'tempo_bpm': cfg.tempo,
          'start_tick': start,
          'end_tick': endTick,
          'tick_duration_us': tickDuration.inMicroseconds,
          'event_count': events.length,
          'clip_count': scheduled.length,
        },
      );
      var eventIndex = 0;
      // Skip events before the start tick so a mid-song start doesn't replay them.
      while (eventIndex < events.length && events[eventIndex].tick < start) {
        eventIndex++;
      }
      var elapsedTicks = 0;
      int? lastDispatchedTick;
      int? lastTickDeadlineUs;
      int? lastTickObservedUs;
      for (var tick = start; tick < endTick; tick++) {
        if (_version != version) {
          runTrace?.finish(
            arguments: {'result': 'stopped', 'dispatch_count': elapsedTicks},
          );
          return;
        }
        if (elapsedTicks > 0) await pacer.awaitBoundary(elapsedTicks);
        if (_version != version) {
          runTrace?.finish(
            arguments: {'result': 'stopped', 'dispatch_count': elapsedTicks},
          );
          return;
        }
        final scheduledDeadlineUs = elapsedTicks * tickDuration.inMicroseconds;
        final dispatchUs = dispatchClock?.elapsedMicroseconds;
        final rawDispatchLateUs = dispatchUs == null
            ? null
            : dispatchUs - scheduledDeadlineUs;
        lastDispatchedTick = tick;
        lastTickDeadlineUs = scheduledDeadlineUs;
        lastTickObservedUs = dispatchUs;
        final dispatchLateUs = rawDispatchLateUs == null
            ? null
            : (rawDispatchLateUs < 0 ? 0 : rawDispatchLateUs);
        if (dispatchLateUs != null) {
          dispatchLatenessUs!.add(dispatchLateUs);
          dispatchErrorUs!.add(rawDispatchLateUs!);
          profileRun?.recordTickDispatchError(rawDispatchLateUs);
        }
        state = state.copyWith(currentTick: () => tick);
        if (metronomeOn && tick % beatTicks == 0) {
          unawaited(metronomeSink(accent: tick % measureTicks == 0));
        }
        while (eventIndex < events.length && events[eventIndex].tick == tick) {
          final event = events[eventIndex];
          final eventId = eventIndex;
          eventIndex++;
          final eventDispatchUs = dispatchClock?.elapsedMicroseconds;
          final eventErrorUs = eventDispatchUs == null
              ? null
              : eventDispatchUs - scheduledDeadlineUs;
          final eventLateUs = eventErrorUs == null || eventErrorUs < 0
              ? (eventErrorUs == null ? null : 0)
              : eventErrorUs;
          if (eventErrorUs != null) {
            eventDispatchErrorUs!.add(eventErrorUs);
            eventDispatchLatenessUs!.add(eventLateUs!);
            profileRun?.recordEventDispatchError(eventErrorUs);
            runTrace?.instant(
              'writer.playback.event_dispatch',
              arguments: {
                'run_id': runId,
                'event_id': eventId,
                'tick': tick,
                'deadline_us': scheduledDeadlineUs,
                'dispatch_error_us': eventErrorUs,
                'dispatch_lateness_us': eventLateUs,
                'requested_voice_count':
                    event.noteGroups.fold<int>(
                      0,
                      (sum, group) => sum + group.midiNotes.length,
                    ) +
                    event.sequencedNoteGroups.fold<int>(
                      0,
                      (sum, group) => sum + group.notes.length,
                    ),
                'plain_note_count': event.noteGroups.fold<int>(
                  0,
                  (sum, group) => sum + group.midiNotes.length,
                ),
                'sequenced_note_count': event.sequencedNoteGroups.fold<int>(
                  0,
                  (sum, group) => sum + group.notes.length,
                ),
                'drum_count': event.drumGroups.fold<int>(
                  0,
                  (sum, group) => sum + group.drumLanes.length,
                ),
              },
            );
          }
          final eventProfile = profileRun == null || dispatchClock == null
              ? null
              : PlaybackProfileEventContext(
                  run: profileRun,
                  eventId: eventId,
                  scoreTick: tick,
                  deadlineUs: scheduledDeadlineUs,
                  clock: dispatchClock,
                );
          for (final group in event.noteGroups) {
            if (eventProfile == null) {
              noteSink(group.midiNotes, group.volume, group.pan);
            } else {
              withPlaybackProfileEvent(
                eventProfile,
                () => noteSink(group.midiNotes, group.volume, group.pan),
              );
            }
          }
          for (final group in event.sequencedNoteGroups) {
            for (final note in group.notes) {
              final onsetOffset = Duration(milliseconds: note.onsetOffsetMs);
              void invokeSink() {
                sequencedNoteSink(
                  midiNote: note.midiNote,
                  duration: pr_rules.effectiveSequencedNoteDuration(
                    tickDuration,
                    note,
                  ),
                  onsetDelay: onsetOffset,
                  volume: group.volume,
                  pan: group.pan,
                );
              }

              if (eventProfile == null) {
                invokeSink();
              } else {
                withPlaybackProfileVoice(
                  eventProfile.nextVoice(
                    onsetOffsetUs: onsetOffset.inMicroseconds,
                  ),
                  invokeSink,
                );
              }
            }
          }
          for (final group in event.drumGroups) {
            unawaited(drumSink(group.drumLanes, 0.8 * group.volume, group.pan));
          }
        }
        fireAudio(tick, elapsedTicks);
        elapsedTicks++;
      }
      if (_version != version) {
        runTrace?.finish(
          arguments: {'result': 'stopped', 'dispatch_count': elapsedTicks},
        );
        return;
      }
      for (final p in pendingAudioStops) {
        unawaited(audioSink.stopClip(asset: p.$1));
      }
      state = state.copyWith(
        status: SongwriterPlaybackStatus.completed,
        currentTick: () => endTick,
      );
      final scoreBoundaryDeadlineUs =
          (elapsedTicks * tickDuration.inMicroseconds);
      final scoreBoundaryObservedUs = dispatchClock?.elapsedMicroseconds;
      final scoreBoundarySample = playbackScoreBoundarySample(
        runId: runId,
        lastDispatchedTick: lastDispatchedTick,
        lastTickDeadlineUs: lastTickDeadlineUs,
        lastTickObservedUs: lastTickObservedUs,
        scoreBoundaryDeadlineUs: scoreBoundaryDeadlineUs,
        scoreBoundaryObservedUs: scoreBoundaryObservedUs,
      );
      if (profileRun != null) {
        profileRun.scoreBoundarySample = scoreBoundarySample;
      }
      runTrace?.instant(
        'writer.playback.score_boundary_sample',
        arguments: scoreBoundarySample,
      );
      if (dispatchLatenessUs != null) {
        final tickLatenessP95 = playbackProfilePercentile(
          dispatchLatenessUs,
          0.95,
        );
        final tickErrorP95 = playbackProfilePercentile(dispatchErrorUs!, 0.95);
        final eventLateness = [...?eventDispatchLatenessUs];
        final eventError = [...?eventDispatchErrorUs];
        final eventLatenessP95 = playbackProfilePercentile(eventLateness, 0.95);
        final eventErrorP95 = playbackProfilePercentile(eventError, 0.95);
        final worstTickAbsoluteError = dispatchErrorUs
            .map((value) => value.abs())
            .fold<int>(0, (worst, value) => value > worst ? value : worst);
        final worstEventAbsoluteError = eventError
            .map((value) => value.abs())
            .fold<int>(0, (worst, value) => value > worst ? value : worst);
        runTrace?.finish(
          arguments: {
            'result': 'completed',
            'tick_dispatch_count': dispatchLatenessUs.length,
            'tick_dispatch_error_p95_us': tickErrorP95,
            'tick_dispatch_lateness_p95_us': tickLatenessP95,
            'tick_dispatch_error_worst_abs_us': worstTickAbsoluteError,
            'tick_dispatch_lateness_worst_us': dispatchLatenessUs.fold<int>(
              0,
              (worst, value) => value > worst ? value : worst,
            ),
            'event_dispatch_count': eventLateness.length,
            if (eventError.isNotEmpty) ...{
              'event_dispatch_error_p95_us': eventErrorP95,
              'event_dispatch_lateness_p95_us': eventLatenessP95,
              'event_dispatch_error_worst_abs_us': worstEventAbsoluteError,
              'event_dispatch_lateness_worst_us': eventLateness.fold<int>(
                0,
                (worst, value) => value > worst ? value : worst,
              ),
            },
            'score_boundary_deadline_us': scoreBoundaryDeadlineUs,
            'score_boundary_observed_us': ?scoreBoundaryObservedUs,
            'last_tick_dispatch_error_us':
                ?scoreBoundarySample['last_tick_dispatch_error_us'],
            'completion_vs_score_boundary_error_us':
                ?scoreBoundarySample['completion_vs_score_boundary_error_us'],
            'voice_outcomes': ?profileRun?.toJson(),
          },
        );
      } else {
        runTrace?.finish(arguments: {'result': 'completed'});
      }
    } catch (error, stackTrace) {
      runTrace?.finishError(error, stage: 'transport');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void stopPlayback() {
    _version++;
    ref.read(songwriterSequencedNoteStopSinkProvider)();
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
    ref.listen<String?>(saveSystemProvider.select((s) => s.selectedProjectId), (
      prev,
      next,
    ) {
      if (prev != next) state = 0;
    });
    return 0;
  }

  void setTick(int tick) => state = tick < 0 ? 0 : tick;
  void reset() => state = 0;
}

final songwriterStartTickProvider =
    NotifierProvider<SongwriterStartTickNotifier, int>(
      SongwriterStartTickNotifier.new,
    );
