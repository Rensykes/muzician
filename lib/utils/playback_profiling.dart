/// Lightweight playback tracing that is present only in debug/profile builds.
///
/// These traces are intended for DevTools Timeline captures. They deliberately
/// emit no console output, and release builds compile the guarded call sites
/// away.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const bool playbackProfilingEnabled = kDebugMode || kProfileMode;

const Object _profileEventZoneKey = #muzicianPlaybackProfileEvent;
const Object _profileVoiceZoneKey = #muzicianPlaybackProfileVoice;

/// Correlation data for one intended note in a profiled Writer/Song run.
/// Deadlines are relative to the run's monotonic Stopwatch, never wall clock.
class PlaybackProfileVoiceContext {
  const PlaybackProfileVoiceContext({
    required this.run,
    required this.eventId,
    required this.voiceId,
    required this.scoreTick,
    required this.eventDeadlineUs,
    required this.onsetOffsetUs,
    required this.clock,
  });

  final PlaybackProfileRunStats run;
  final int eventId;
  final String voiceId;
  final int scoreTick;
  final int eventDeadlineUs;
  final int onsetOffsetUs;
  final Stopwatch clock;

  int get intendedDeadlineUs => eventDeadlineUs + onsetOffsetUs;

  Map<String, Object?> get timelineArguments => {
    'run_id': run.runId,
    'event_id': eventId,
    'voice_id': voiceId,
    'score_tick': scoreTick,
    'event_deadline_us': eventDeadlineUs,
    'intended_onset_offset_us': onsetOffsetUs,
    'intended_deadline_us': intendedDeadlineUs,
  };
}

/// Mutable, development-only outcome counters shared by one transport run.
/// Play-future completion is a platform API observation, not audible onset.
class PlaybackProfileRunStats {
  PlaybackProfileRunStats({
    required this.runId,
    required this.expectedVoiceCount,
  });

  final int runId;
  final int expectedVoiceCount;
  final Map<String, PlaybackProfileVoiceRecord> _voices = {};
  final List<int> _tickDispatchErrorsUs = [];
  final List<int> _eventDispatchErrorsUs = [];
  Map<String, Object?>? scoreBoundarySample;
  int playerCreatedCount = 0;
  int playerReusedCount = 0;
  int stolenVoiceCount = 0;

  int get requestedVoiceCount => _voices.length;
  int get launchedVoiceCount =>
      _voices.values.where((voice) => voice.launched).length;
  int get playFutureCompletedCount =>
      _voices.values.where((voice) => voice.playFutureCompleted).length;
  int get terminatedVoiceCount =>
      _voices.values.where((voice) => voice.terminated).length;
  int get pendingVoiceCount =>
      _voices.values.where((voice) => voice.pending).length;
  int get activeVoiceCount =>
      _voices.values.where((voice) => voice.active).length;
  int get droppedVoiceCount => _voices.values
      .where((voice) => voice.outcome == 'dropped_not_ready')
      .length;
  int get errorVoiceCount =>
      _voices.values.where((voice) => voice.outcome == 'error').length;
  int get cancelledVoiceCount =>
      _voices.values.where((voice) => voice.outcome == 'cancelled').length;

  void request(PlaybackProfileVoiceContext context) {
    _voices.putIfAbsent(
      context.voiceId,
      () => PlaybackProfileVoiceRecord(context: context),
    );
  }

  bool isTerminated(PlaybackProfileVoiceContext context) =>
      _voices[context.voiceId]?.terminated ?? false;

  void launched(PlaybackProfileVoiceContext context) {
    final voice = _voices.putIfAbsent(
      context.voiceId,
      () => PlaybackProfileVoiceRecord(context: context),
    );
    voice.launched = true;
  }

  void recordTickDispatchError(int errorUs) =>
      _tickDispatchErrorsUs.add(errorUs);

  void recordEventDispatchError(int errorUs) =>
      _eventDispatchErrorsUs.add(errorUs);

  void outcome(PlaybackProfileVoiceContext context, String outcome) {
    final voice = _voices.putIfAbsent(
      context.voiceId,
      () => PlaybackProfileVoiceRecord(context: context),
    );
    switch (outcome) {
      case 'play_future_completed':
        voice.playFutureCompleted = true;
        voice.pending = false;
        voice.active = !voice.terminated;
        if (!voice.terminated) voice.outcome = outcome;
        break;
      case 'natural_completion':
      case 'cancelled':
      case 'error':
      case 'stolen_before_completion':
      case 'dropped_not_ready':
        if (!voice.terminated) {
          if (outcome == 'stolen_before_completion') stolenVoiceCount++;
          voice.outcome = outcome;
          voice.pending = false;
          voice.active = false;
          voice.terminated = true;
        }
        break;
      default:
        if (!voice.terminated) voice.outcome = outcome;
    }
  }

  Map<String, Object?> toJson() {
    final firstTickDispatchErrorUs = _tickDispatchErrorsUs.isEmpty
        ? null
        : _tickDispatchErrorsUs.first;
    final lastTickDispatchErrorUs = _tickDispatchErrorsUs.isEmpty
        ? null
        : _tickDispatchErrorsUs.last;
    final tickDispatchErrorChangeUs =
        firstTickDispatchErrorUs == null || lastTickDispatchErrorUs == null
        ? null
        : lastTickDispatchErrorUs - firstTickDispatchErrorUs;

    return {
      'run_id': runId,
      'expected_voice_count': expectedVoiceCount,
      'requested_voice_count': requestedVoiceCount,
      'launched_voice_count': launchedVoiceCount,
      'play_future_completed_count': playFutureCompletedCount,
      'terminated_voice_count': terminatedVoiceCount,
      'active_voice_count': activeVoiceCount,
      'pending_voice_count': pendingVoiceCount,
      'unknown_expected_voice_count': (expectedVoiceCount - requestedVoiceCount)
          .clamp(0, expectedVoiceCount),
      'unexpected_requested_voice_count':
          (requestedVoiceCount - expectedVoiceCount).clamp(
            0,
            requestedVoiceCount,
          ),
      'player_created_count': playerCreatedCount,
      'player_reused_count': playerReusedCount,
      'stolen_voice_count': stolenVoiceCount,
      'dropped_voice_count': droppedVoiceCount,
      'error_voice_count': errorVoiceCount,
      'cancelled_voice_count': cancelledVoiceCount,
      'audible_onset_observed': false,
      'dispatch_metrics': {
        'tick_sample_count': _tickDispatchErrorsUs.length,
        'first_tick_dispatch_error_us': firstTickDispatchErrorUs,
        'last_tick_dispatch_error_us': lastTickDispatchErrorUs,
        // This is the change between signed tick errors, separate from score
        // completion relative to the nominal boundary below.
        'tick_dispatch_error_change_us': tickDispatchErrorChangeUs,
        'tick_dispatch_error_p95_us': playbackProfilePercentile(
          _tickDispatchErrorsUs,
          0.95,
        ),
        'tick_dispatch_lateness_p95_us': playbackProfilePercentile(
          _tickDispatchErrorsUs.map((value) => value < 0 ? 0 : value).toList(),
          0.95,
        ),
        'tick_dispatch_error_worst_abs_us': _worstAbsolute(
          _tickDispatchErrorsUs,
        ),
        'tick_dispatch_lateness_worst_us': _worstPositive(
          _tickDispatchErrorsUs,
        ),
        'event_sample_count': _eventDispatchErrorsUs.length,
        'event_dispatch_error_p95_us': playbackProfilePercentile(
          _eventDispatchErrorsUs,
          0.95,
        ),
        'event_dispatch_lateness_p95_us': playbackProfilePercentile(
          _eventDispatchErrorsUs.map((value) => value < 0 ? 0 : value).toList(),
          0.95,
        ),
        'event_dispatch_error_worst_abs_us': _worstAbsolute(
          _eventDispatchErrorsUs,
        ),
        'event_dispatch_lateness_worst_us': _worstPositive(
          _eventDispatchErrorsUs,
        ),
        'score_boundary_sample': scoreBoundarySample,
      },
      'voices': [
        for (final voice in _voices.values)
          {
            ...voice.context.timelineArguments,
            'outcome': voice.outcome,
            'launched': voice.launched,
            'play_future_completed': voice.playFutureCompleted,
            'terminated': voice.terminated,
          },
      ],
    };
  }

  int _worstAbsolute(List<int> errors) => errors.fold<int>(
    0,
    (worst, value) => value.abs() > worst ? value.abs() : worst,
  );

  int _worstPositive(List<int> errors) =>
      errors.fold<int>(0, (worst, value) => value > worst ? value : worst);
}

/// Builds honest end-of-run timing fields without treating loop completion as
/// an observation at the nominal score boundary. The last dispatched tick is
/// the drift sample; completion may precede the score boundary by one tick.
Map<String, Object?> playbackScoreBoundarySample({
  required int runId,
  required int? lastDispatchedTick,
  required int? lastTickDeadlineUs,
  required int? lastTickObservedUs,
  required int scoreBoundaryDeadlineUs,
  required int? scoreBoundaryObservedUs,
}) {
  final lastTickDispatchErrorUs =
      lastTickObservedUs == null || lastTickDeadlineUs == null
      ? null
      : lastTickObservedUs - lastTickDeadlineUs;
  final completionErrorUs = scoreBoundaryObservedUs == null
      ? null
      : scoreBoundaryObservedUs - scoreBoundaryDeadlineUs;
  return {
    'run_id': runId,
    'last_dispatched_tick': ?lastDispatchedTick,
    'last_tick_deadline_us': ?lastTickDeadlineUs,
    'last_tick_observed_us': ?lastTickObservedUs,
    'last_tick_dispatch_error_us': ?lastTickDispatchErrorUs,
    'score_boundary_deadline_us': scoreBoundaryDeadlineUs,
    'score_boundary_observed_us': ?scoreBoundaryObservedUs,
    'completion_vs_score_boundary_error_us': ?completionErrorUs,
    if (completionErrorUs != null)
      'completion_vs_score_boundary_lateness_us': completionErrorUs < 0
          ? 0
          : completionErrorUs,
  };
}

class PlaybackProfileVoiceRecord {
  PlaybackProfileVoiceRecord({required this.context});

  final PlaybackProfileVoiceContext context;
  String outcome = 'pending';
  bool pending = true;
  bool launched = false;
  bool active = false;
  bool playFutureCompleted = false;
  bool terminated = false;
}

/// Event scope for legacy sink signatures. NotePlayer consumes one voice id
/// per preview request from this scope, preserving the public sink contract.
class PlaybackProfileEventContext {
  PlaybackProfileEventContext({
    required this.run,
    required this.eventId,
    required this.scoreTick,
    required this.deadlineUs,
    required this.clock,
  });

  final PlaybackProfileRunStats run;
  final int eventId;
  final int scoreTick;
  final int deadlineUs;
  final Stopwatch clock;
  int _nextVoiceOrdinal = 0;

  PlaybackProfileVoiceContext nextVoice({int onsetOffsetUs = 0}) =>
      PlaybackProfileVoiceContext(
        run: run,
        eventId: eventId,
        voiceId: 'r${run.runId}-e$eventId-v${_nextVoiceOrdinal++}',
        scoreTick: scoreTick,
        eventDeadlineUs: deadlineUs,
        onsetOffsetUs: onsetOffsetUs,
        clock: clock,
      );
}

T withPlaybackProfileEvent<T>(
  PlaybackProfileEventContext context,
  T Function() action,
) => runZoned<T>(action, zoneValues: {_profileEventZoneKey: context});

T withPlaybackProfileVoice<T>(
  PlaybackProfileVoiceContext context,
  T Function() action,
) => runZoned<T>(action, zoneValues: {_profileVoiceZoneKey: context});

PlaybackProfileVoiceContext? playbackProfileVoiceContext({
  int onsetOffsetUs = 0,
}) {
  if (!playbackProfilingEnabled) return null;
  final explicit = Zone.current[_profileVoiceZoneKey];
  if (explicit is PlaybackProfileVoiceContext) return explicit;
  final event = Zone.current[_profileEventZoneKey];
  if (event is PlaybackProfileEventContext) {
    return event.nextVoice(onsetOffsetUs: onsetOffsetUs);
  }
  return null;
}

/// Nearest-rank percentile over signed microsecond errors.
int? playbackProfilePercentile(List<int> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final index = ((sorted.length * percentile).ceil() - 1).clamp(
    0,
    sorted.length - 1,
  );
  return sorted[index];
}

class PlaybackProfileTask {
  PlaybackProfileTask._(this._task);

  final developer.TimelineTask _task;
  bool _finished = false;

  static PlaybackProfileTask begin(
    String name, {
    Map<String, Object?> arguments = const {},
  }) {
    final task = developer.TimelineTask()..start(name, arguments: arguments);
    return PlaybackProfileTask._(task);
  }

  void instant(String name, {Map<String, Object?> arguments = const {}}) {
    _task.instant(name, arguments: arguments);
  }

  void finish({Map<String, Object?> arguments = const {}}) {
    if (_finished) return;
    _finished = true;
    _task.finish(arguments: arguments);
  }

  void finishError(Object error, {String? stage}) {
    finish(
      arguments: {
        'outcome': 'error',
        'error_type': error.runtimeType.toString(),
        'stage': ?stage,
      },
    );
  }
}

void playbackProfileInstant(
  String name, {
  Map<String, Object?> arguments = const {},
}) {
  if (!playbackProfilingEnabled) return;
  developer.Timeline.instantSync(name, arguments: arguments);
}
