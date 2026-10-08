/// Frame timing collection for the isolated Writer playback profile harness.
///
/// The listener may remain attached for the harness lifetime, but stores
/// timings only between an explicit [start] and [stop] pair.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/scheduler.dart';

class PlaybackProfileFrameSample {
  const PlaybackProfileFrameSample({
    required this.buildDurationUs,
    required this.rasterDurationUs,
  });

  factory PlaybackProfileFrameSample.fromFrameTiming(FrameTiming timing) =>
      PlaybackProfileFrameSample(
        buildDurationUs: timing.buildDuration.inMicroseconds,
        rasterDurationUs: timing.rasterDuration.inMicroseconds,
      );

  final int buildDurationUs;
  final int rasterDurationUs;

  int get criticalStageDurationUs =>
      math.max(buildDurationUs, rasterDurationUs);
}

/// Summarized UI frame costs. Refresh-based metrics are null when the display
/// refresh rate is unknown or invalid; the collector never assumes 60 or 120Hz.
class PlaybackProfileFrameSummary {
  const PlaybackProfileFrameSummary({
    required this.frameCount,
    required this.refreshRateHz,
    required this.frameBudgetUs,
    required this.buildDurationUs,
    required this.rasterDurationUs,
    required this.criticalStageDurationUs,
    required this.missedBudgetCount,
    required this.missedBudgetFraction,
    required this.worstBudgetMultiple,
    required this.captureComplete,
    required this.frameBudgetEvaluationAvailable,
    required this.postWindowFrameFenceObserved,
    required this.timingWindowStartWallUs,
    required this.timingWindowEndWallUs,
    required this.callbackDrainMs,
    required this.outOfWindowFrameCount,
    required this.unusableWallTimestampFrameCount,
    required this.captureCompleteness,
  });

  final int frameCount;
  final double? refreshRateHz;
  final double? frameBudgetUs;
  final Map<String, int?> buildDurationUs;
  final Map<String, int?> rasterDurationUs;
  final Map<String, int?> criticalStageDurationUs;
  final int? missedBudgetCount;
  final double? missedBudgetFraction;
  final double? worstBudgetMultiple;
  final bool captureComplete;
  final bool frameBudgetEvaluationAvailable;
  final bool postWindowFrameFenceObserved;
  final int? timingWindowStartWallUs;
  final int? timingWindowEndWallUs;
  final int callbackDrainMs;
  final int outOfWindowFrameCount;
  final int unusableWallTimestampFrameCount;
  final String captureCompleteness;

  Map<String, Object?> toJson() => {
    'frame_count': frameCount,
    'refresh_rate_hz': refreshRateHz,
    'frame_budget_us': frameBudgetUs,
    'build_duration_us': buildDurationUs,
    'raster_duration_us': rasterDurationUs,
    'critical_stage_duration_us': criticalStageDurationUs,
    'frame_budget_stage': 'max(build_duration, raster_duration)',
    'missed_budget_count': missedBudgetCount,
    'missed_budget_fraction': missedBudgetFraction,
    'worst_budget_multiple': worstBudgetMultiple,
    'capture_complete': captureComplete,
    'frame_budget_evaluation_available': frameBudgetEvaluationAvailable,
    'post_window_frame_fence_observed': postWindowFrameFenceObserved,
    'timing_window_start_wall_us': timingWindowStartWallUs,
    'timing_window_end_wall_us': timingWindowEndWallUs,
    'post_window_frame_fence_timeout_ms': callbackDrainMs,
    'out_of_window_frame_count': outOfWindowFrameCount,
    'unusable_wall_timestamp_frame_count': unusableWallTimestampFrameCount,
    'capture_completeness': captureCompleteness,
  };

  static PlaybackProfileFrameSummary fromSamples(
    Iterable<PlaybackProfileFrameSample> samples, {
    required double? refreshRateHz,
    int? timingWindowStartWallUs,
    int? timingWindowEndWallUs,
    int callbackDrainMs = 0,
    int outOfWindowFrameCount = 0,
    int unusableWallTimestampFrameCount = 0,
    String captureCompleteness = 'summary_only',
    bool captureComplete = true,
    bool postWindowFrameFenceObserved = false,
  }) {
    final frames = samples.toList(growable: false);
    final rate =
        refreshRateHz != null && refreshRateHz.isFinite && refreshRateHz > 0
        ? refreshRateHz
        : null;
    final budgetUs = rate == null
        ? null
        : Duration.microsecondsPerSecond / rate;
    final build = frames.map((frame) => frame.buildDurationUs).toList();
    final raster = frames.map((frame) => frame.rasterDurationUs).toList();
    final critical = frames
        .map((frame) => frame.criticalStageDurationUs)
        .toList();
    final hasUnusableWallTimestamps = unusableWallTimestampFrameCount > 0;
    final complete = captureComplete && !hasUnusableWallTimestamps;
    final missed = budgetUs == null || !complete || critical.isEmpty
        ? null
        : critical.where((duration) => duration > budgetUs).length;
    final completeness = hasUnusableWallTimestamps
        ? [
            'incomplete_unusable_wall_timestamp',
            if (postWindowFrameFenceObserved)
              'post_window_frame_fence_observed'
            else if (!captureComplete)
              captureCompleteness.split(';').first.trim(),
            'frame-budget evaluation unavailable',
          ].join('; ')
        : captureCompleteness;

    return PlaybackProfileFrameSummary(
      frameCount: frames.length,
      refreshRateHz: rate,
      frameBudgetUs: budgetUs,
      buildDurationUs: _distribution(build),
      rasterDurationUs: _distribution(raster),
      criticalStageDurationUs: _distribution(critical),
      missedBudgetCount: missed,
      missedBudgetFraction: missed == null || frames.isEmpty
          ? null
          : missed / frames.length,
      worstBudgetMultiple: budgetUs == null || critical.isEmpty || !complete
          ? null
          : critical.reduce(math.max) / budgetUs,
      captureComplete: complete,
      frameBudgetEvaluationAvailable:
          budgetUs != null && complete && critical.isNotEmpty,
      postWindowFrameFenceObserved: postWindowFrameFenceObserved,
      timingWindowStartWallUs: timingWindowStartWallUs,
      timingWindowEndWallUs: timingWindowEndWallUs,
      callbackDrainMs: callbackDrainMs,
      outOfWindowFrameCount: outOfWindowFrameCount,
      unusableWallTimestampFrameCount: unusableWallTimestampFrameCount,
      captureCompleteness: completeness,
    );
  }

  static Map<String, int?> _distribution(List<int> values) {
    if (values.isEmpty) {
      return const {'p50': null, 'p95': null, 'worst': null};
    }
    final sorted = List<int>.of(values)..sort();
    int percentile(double fraction) =>
        sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
    return {
      'p50': percentile(0.50),
      'p95': percentile(0.95),
      'worst': sorted.last,
    };
  }

  /// Represents a window that could not produce a trustworthy frame-budget
  /// evaluation, such as when another window is still draining.
  static PlaybackProfileFrameSummary unavailable({
    required String reason,
    int? timingWindowStartWallUs,
    int? timingWindowEndWallUs,
  }) => fromSamples(
    const [],
    refreshRateHz: null,
    timingWindowStartWallUs: timingWindowStartWallUs,
    timingWindowEndWallUs: timingWindowEndWallUs,
    captureComplete: false,
    captureCompleteness: '$reason; frame-budget evaluation unavailable',
  );
}

/// One caller's ownership token for the capture's single timing window.
/// Attempts arriving while a prior window drains remain explicit and can never
/// stop or summarize the window owned by that prior attempt.
class PlaybackProfileFrameTimingAttempt {
  const PlaybackProfileFrameTimingAttempt._({
    required this.id,
    required this.captureStarted,
    required this.startedWallUs,
    required this.owner,
    this.unavailableReason,
  });

  final int id;
  final bool captureStarted;
  final int startedWallUs;
  final Object? owner;
  final String? unavailableReason;
}

/// Adds per-attempt ownership around a single [PlaybackProfileFrameTimingCapture].
class PlaybackProfileFrameTimingWindow {
  PlaybackProfileFrameTimingWindow(this.capture);

  final PlaybackProfileFrameTimingCapture capture;
  int _nextAttemptId = 0;
  int? _captureOwnerId;

  PlaybackProfileFrameTimingAttempt start({DateTime? wallTime, Object? owner}) {
    final startedWallUs = (wallTime ?? DateTime.now()).microsecondsSinceEpoch;
    final id = ++_nextAttemptId;
    if (capture.start(wallTime: wallTime)) {
      _captureOwnerId = id;
      return PlaybackProfileFrameTimingAttempt._(
        id: id,
        captureStarted: true,
        startedWallUs: startedWallUs,
        owner: owner,
      );
    }
    final reason = capture.isDraining
        ? 'capture_window_busy_draining'
        : capture.isCollecting
        ? 'capture_window_already_active'
        : 'capture_window_unavailable';
    return PlaybackProfileFrameTimingAttempt._(
      id: id,
      captureStarted: false,
      startedWallUs: startedWallUs,
      owner: owner,
      unavailableReason: reason,
    );
  }

  Future<PlaybackProfileFrameSummary> stop(
    PlaybackProfileFrameTimingAttempt attempt, {
    required double? refreshRateHz,
    required DateTime wallTime,
    Duration callbackDrain = const Duration(milliseconds: 1200),
  }) async {
    final endedWallUs = wallTime.microsecondsSinceEpoch;
    if (!attempt.captureStarted) {
      return PlaybackProfileFrameSummary.unavailable(
        reason: attempt.unavailableReason ?? 'capture_window_not_started',
        timingWindowStartWallUs: attempt.startedWallUs,
        timingWindowEndWallUs: endedWallUs,
      );
    }
    if (_captureOwnerId != attempt.id) {
      return PlaybackProfileFrameSummary.unavailable(
        reason: 'capture_window_owner_mismatch',
        timingWindowStartWallUs: attempt.startedWallUs,
        timingWindowEndWallUs: endedWallUs,
      );
    }
    _captureOwnerId = null;
    final summary = await capture.stop(
      refreshRateHz: refreshRateHz,
      wallTime: wallTime,
      callbackDrain: callbackDrain,
    );
    return summary ??
        PlaybackProfileFrameSummary.unavailable(
          reason: 'capture_disposed_before_summary',
          timingWindowStartWallUs: attempt.startedWallUs,
          timingWindowEndWallUs: endedWallUs,
        );
  }
}

/// Owns one timing callback and one explicitly delimited sample window.
class PlaybackProfileFrameTimingCapture {
  final List<PlaybackProfileFrameSample> _samples = [];
  bool _attached = false;
  bool _collecting = false;
  bool _draining = false;
  bool _disposed = false;
  int? _windowStartWallUs;
  int? _windowEndWallUs;
  int _outOfWindowFrameCount = 0;
  int _unusableWallTimestampFrameCount = 0;
  bool _disposeAfterDrain = false;
  Completer<void>? _drainCompleter;

  bool get isAttached => _attached;
  bool get isCollecting => _collecting;
  bool get isDraining => _draining;

  /// Idempotent so widget rebuilds cannot register duplicate callbacks.
  void attach() {
    if (_disposed) throw StateError('Frame timing capture is disposed.');
    if (_attached || kReleaseMode) return;
    SchedulerBinding.instance.addTimingsCallback(recordTimings);
    _attached = true;
  }

  /// Starts a fresh window, returning false when another window is active.
  bool start({DateTime? wallTime}) {
    if (_disposed) throw StateError('Frame timing capture is disposed.');
    if (kReleaseMode) return false;
    attach();
    if (_collecting || _draining) return false;
    _samples.clear();
    _windowStartWallUs = (wallTime ?? DateTime.now()).microsecondsSinceEpoch;
    _windowEndWallUs = null;
    _outOfWindowFrameCount = 0;
    _unusableWallTimestampFrameCount = 0;
    _collecting = true;
    return true;
  }

  /// Closes the active window, then drains ordered callback batches through a
  /// post-window frame fence or a bounded timeout. The SDK documents
  /// raster-finish wall time as correlatable with the system clock, unlike the
  /// generic raster timestamp whose epoch may not match DateTime. Matching
  /// wall-time bounds keep idle frames outside the closed window, even in late
  /// batches.
  Future<PlaybackProfileFrameSummary?> stop({
    required double? refreshRateHz,
    DateTime? wallTime,
    Duration callbackDrain = const Duration(milliseconds: 1200),
  }) async {
    if (!_collecting) return null;
    _collecting = false;
    _windowEndWallUs = (wallTime ?? DateTime.now()).microsecondsSinceEpoch;
    _draining = true;
    final fenceCompleter = Completer<void>();
    _drainCompleter = fenceCompleter;
    // The first reported frame after the closed window is an ordered fence:
    // Flutter batches timing callbacks in chronological order, so receiving
    // this frame proves earlier in-window frames have been reported as well.
    SchedulerBinding.instance.scheduleFrame();
    var fenceObserved = false;
    try {
      await fenceCompleter.future.timeout(callbackDrain);
      fenceObserved = true;
    } on TimeoutException {
      // Preserve observed samples but make frame-budget evaluation unavailable.
    } finally {
      _drainCompleter = null;
    }
    _draining = false;
    if (_disposed) return null;
    final summary = PlaybackProfileFrameSummary.fromSamples(
      List.unmodifiable(_samples),
      refreshRateHz: refreshRateHz,
      timingWindowStartWallUs: _windowStartWallUs,
      timingWindowEndWallUs: _windowEndWallUs,
      callbackDrainMs: callbackDrain.inMilliseconds,
      outOfWindowFrameCount: _outOfWindowFrameCount,
      unusableWallTimestampFrameCount: _unusableWallTimestampFrameCount,
      captureComplete: fenceObserved,
      postWindowFrameFenceObserved: fenceObserved,
      captureCompleteness: fenceObserved
          ? 'complete_after_ordered_post_window_frame_fence'
          : 'incomplete_fence_timeout; frame-budget evaluation unavailable',
    );
    if (_disposeAfterDrain) _disposeNow();
    return summary;
  }

  /// Receives engine timings. Public to allow lifecycle tests to inject
  /// synthetic timings through the same active-window gate as the callback.
  void recordTimings(List<FrameTiming> timings) {
    if (!_collecting && !_draining) return;
    for (final timing in timings) {
      final rasterFinishWallUs = timing.timestampInMicroseconds(
        FramePhase.rasterFinishWallTime,
      );
      if (rasterFinishWallUs <= 0) {
        _unusableWallTimestampFrameCount++;
        continue;
      }
      final startWallUs = _windowStartWallUs;
      final endWallUs = _windowEndWallUs;
      if (startWallUs == null || rasterFinishWallUs < startWallUs) {
        _outOfWindowFrameCount++;
        continue;
      }
      if (endWallUs != null && rasterFinishWallUs > endWallUs) {
        _outOfWindowFrameCount++;
        final fenceCompleter = _drainCompleter;
        if (fenceCompleter != null && !fenceCompleter.isCompleted) {
          fenceCompleter.complete();
        }
        continue;
      }
      _samples.add(PlaybackProfileFrameSample.fromFrameTiming(timing));
    }
  }

  /// Removes the callback once and makes all future operations inert.
  void dispose() {
    if (_disposed) return;
    _collecting = false;
    if (_draining) {
      // The window is already closed by wall-clock bounds. Keep the callback
      // briefly so delayed active-window timings can drain, then detach it.
      _disposeAfterDrain = true;
      return;
    }
    _disposeNow();
  }

  void _disposeNow() {
    if (_disposed) return;
    _collecting = false;
    _draining = false;
    if (_attached) {
      SchedulerBinding.instance.removeTimingsCallback(recordTimings);
      _attached = false;
    }
    _disposed = true;
  }
}
