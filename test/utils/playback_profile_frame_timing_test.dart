import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/playback_profile_frame_timing.dart';

FrameTiming _timing({
  required int buildUs,
  required int rasterUs,
  required int wallTimeUs,
  int frame = 0,
}) => FrameTiming(
  vsyncStart: frame * 20000,
  buildStart: frame * 20000 + 100,
  buildFinish: frame * 20000 + 100 + buildUs,
  rasterStart: frame * 20000 + 100 + buildUs + 100,
  rasterFinish: frame * 20000 + 200 + buildUs + rasterUs,
  rasterFinishWallTime: wallTimeUs,
  frameNumber: frame,
);

void main() {
  test('reports build/raster percentiles against measured 120Hz budget', () {
    final summary = PlaybackProfileFrameSummary.fromSamples(const [
      PlaybackProfileFrameSample(buildDurationUs: 1000, rasterDurationUs: 2000),
      PlaybackProfileFrameSample(buildDurationUs: 5000, rasterDurationUs: 8000),
      PlaybackProfileFrameSample(
        buildDurationUs: 10000,
        rasterDurationUs: 5000,
      ),
      PlaybackProfileFrameSample(buildDurationUs: 9000, rasterDurationUs: 2000),
    ], refreshRateHz: 120);

    expect(summary.frameCount, 4);
    expect(summary.frameBudgetUs, closeTo(8333.333, 0.01));
    expect(summary.buildDurationUs, {
      'p50': 5000,
      'p95': 10000,
      'worst': 10000,
    });
    expect(summary.rasterDurationUs, {'p50': 2000, 'p95': 8000, 'worst': 8000});
    expect(summary.criticalStageDurationUs, {
      'p50': 8000,
      'p95': 10000,
      'worst': 10000,
    });
    expect(summary.missedBudgetCount, 2);
    expect(summary.missedBudgetFraction, 0.5);
    expect(summary.worstBudgetMultiple, closeTo(1.2, 0.001));
    expect(summary.captureComplete, isTrue);
    expect(summary.frameBudgetEvaluationAvailable, isTrue);
  });

  test('keeps budget metrics unavailable when refresh rate is unknown', () {
    final summary = PlaybackProfileFrameSummary.fromSamples(const [
      PlaybackProfileFrameSample(buildDurationUs: 3200, rasterDurationUs: 4100),
    ], refreshRateHz: null);

    expect(summary.frameCount, 1);
    expect(summary.buildDurationUs['worst'], 3200);
    expect(summary.rasterDurationUs['worst'], 4100);
    expect(summary.frameBudgetUs, isNull);
    expect(summary.missedBudgetCount, isNull);
    expect(summary.missedBudgetFraction, isNull);
    expect(summary.worstBudgetMultiple, isNull);
    expect(summary.frameBudgetEvaluationAvailable, isFalse);
  });

  test(
    'late batches drain through ordered fence across resume and dispose',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final capture = PlaybackProfileFrameTimingCapture();
      final windowStart = DateTime.utc(2026, 10, 8, 12);
      final startUs = windowStart.microsecondsSinceEpoch;

      capture.attach();
      capture.attach();
      expect(capture.isAttached, isTrue);
      expect(capture.start(wallTime: windowStart), isTrue);
      expect(capture.start(), isFalse);
      capture.recordTimings([
        _timing(buildUs: 9000, rasterUs: 9000, wallTimeUs: startUs - 1),
        _timing(buildUs: 1000, rasterUs: 2000, wallTimeUs: startUs + 100),
      ]);
      final firstStop = capture.stop(
        refreshRateHz: 60,
        wallTime: windowStart.add(const Duration(microseconds: 200)),
        callbackDrain: const Duration(seconds: 1),
      );
      expect(capture.isCollecting, isFalse);
      expect(capture.isDraining, isTrue);
      expect(capture.start(), isFalse);
      // A late in-window frame is retained; the idle frame is the fence.
      capture.recordTimings([
        _timing(buildUs: 3000, rasterUs: 4000, wallTimeUs: startUs + 190),
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 201),
      ]);
      final first = await firstStop;
      expect(first?.frameCount, 2);
      expect(first?.postWindowFrameFenceObserved, isTrue);
      expect(first?.captureComplete, isTrue);
      expect(first?.frameBudgetEvaluationAvailable, isTrue);
      expect(first?.missedBudgetCount, 0);
      expect(first?.outOfWindowFrameCount, 2); // stale frame and fence frame.
      capture.recordTimings([
        _timing(buildUs: 9000, rasterUs: 9000, wallTimeUs: startUs + 202),
      ]);
      expect(await capture.stop(refreshRateHz: 60), isNull);

      final resumedStart = windowStart.add(const Duration(milliseconds: 500));
      expect(capture.start(wallTime: resumedStart), isTrue);
      capture.recordTimings([
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 190),
        _timing(buildUs: 3000, rasterUs: 4000, wallTimeUs: startUs + 501000),
      ]);
      final secondStop = capture.stop(
        refreshRateHz: null,
        wallTime: windowStart.add(const Duration(milliseconds: 600)),
        callbackDrain: const Duration(seconds: 1),
      );
      // Disposal during the drain keeps the timing listener until the fence.
      capture.dispose();
      expect(capture.isAttached, isTrue);
      capture.recordTimings([
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 600001),
      ]);
      final second = await secondStop;
      expect(second?.frameCount, 1);
      expect(second?.buildDurationUs['worst'], 3000);
      expect(second?.captureComplete, isTrue);
      expect(second?.missedBudgetFraction, isNull);
      expect(capture.isAttached, isFalse);

      capture.dispose();
      expect(capture.isCollecting, isFalse);
      capture.recordTimings([
        _timing(buildUs: 10000, rasterUs: 10000, wallTimeUs: startUs + 700000),
      ]);
    },
  );

  test(
    'unusable wall timestamps invalidate a fenced capture budget gate',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final capture = PlaybackProfileFrameTimingCapture();
      final start = DateTime.utc(2026, 10, 8, 12, 30);
      final startUs = start.microsecondsSinceEpoch;

      expect(capture.start(wallTime: start), isTrue);
      capture.recordTimings([
        _timing(buildUs: 20000, rasterUs: 18000, wallTimeUs: startUs + 100),
        _timing(buildUs: 9000, rasterUs: 9000, wallTimeUs: 0),
      ]);
      final pendingSummary = capture.stop(
        refreshRateHz: 60,
        wallTime: start.add(const Duration(microseconds: 200)),
        callbackDrain: const Duration(seconds: 1),
      );
      capture.recordTimings([
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 201),
      ]);

      final summary = await pendingSummary;
      expect(summary?.frameCount, 1);
      expect(summary?.buildDurationUs['worst'], 20000);
      expect(summary?.rasterDurationUs['worst'], 18000);
      expect(summary?.unusableWallTimestampFrameCount, 1);
      expect(summary?.postWindowFrameFenceObserved, isTrue);
      expect(summary?.captureComplete, isFalse);
      expect(summary?.frameBudgetEvaluationAvailable, isFalse);
      expect(summary?.missedBudgetCount, isNull);
      expect(summary?.missedBudgetFraction, isNull);
      expect(summary?.worstBudgetMultiple, isNull);
      expect(
        summary?.captureCompleteness,
        contains('incomplete_unusable_wall_timestamp'),
      );
      expect(
        summary?.captureCompleteness,
        contains('post_window_frame_fence_observed'),
      );

      // Callers constructing a summary directly cannot bypass the same gate.
      final directSummary = PlaybackProfileFrameSummary.fromSamples(
        const [
          PlaybackProfileFrameSample(
            buildDurationUs: 20000,
            rasterDurationUs: 18000,
          ),
        ],
        refreshRateHz: 60,
        unusableWallTimestampFrameCount: 1,
        captureComplete: true,
      );
      expect(directSummary.captureComplete, isFalse);
      expect(directSummary.frameBudgetEvaluationAvailable, isFalse);
      expect(directSummary.missedBudgetCount, isNull);
      expect(directSummary.missedBudgetFraction, isNull);
      expect(directSummary.worstBudgetMultiple, isNull);
      expect(
        directSummary.captureCompleteness,
        contains('incomplete_unusable_wall_timestamp'),
      );
      capture.dispose();
    },
  );

  test(
    'fence timeout reports incomplete and disables frame-budget gate',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final capture = PlaybackProfileFrameTimingCapture();
      final start = DateTime.utc(2026, 10, 8, 13);
      expect(capture.start(wallTime: start), isTrue);
      capture.recordTimings([
        _timing(
          buildUs: 20000,
          rasterUs: 20000,
          wallTimeUs: start.microsecondsSinceEpoch + 100,
        ),
      ]);
      final summary = await capture.stop(
        refreshRateHz: 60,
        wallTime: start.add(const Duration(microseconds: 200)),
        callbackDrain: Duration.zero,
      );

      expect(summary?.frameCount, 1);
      expect(summary?.captureComplete, isFalse);
      expect(summary?.postWindowFrameFenceObserved, isFalse);
      expect(summary?.frameBudgetEvaluationAvailable, isFalse);
      expect(summary?.criticalStageDurationUs['worst'], 20000);
      expect(summary?.missedBudgetCount, isNull);
      expect(summary?.missedBudgetFraction, isNull);
      expect(
        summary?.captureCompleteness,
        contains('incomplete_fence_timeout'),
      );
      expect(summary?.toJson()['capture_complete'], isFalse);
      capture.dispose();
    },
  );

  test(
    'draining window keeps its owner and marks a restarted attempt unavailable',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final capture = PlaybackProfileFrameTimingCapture();
      final window = PlaybackProfileFrameTimingWindow(capture);
      final start = DateTime.utc(2026, 10, 8, 14);
      final startUs = start.microsecondsSinceEpoch;
      final oldRunOwner = {
        'run_id': 41,
        'voice_outcomes': ['old-run-voice'],
      };
      final restartedRunOwner = {
        'run_id': 42,
        'voice_outcomes': ['new-run-voice'],
      };

      final oldAttempt = window.start(wallTime: start, owner: oldRunOwner);
      expect(oldAttempt.captureStarted, isTrue);
      expect(oldAttempt.owner, same(oldRunOwner));
      capture.recordTimings([
        _timing(buildUs: 4000, rasterUs: 5000, wallTimeUs: startUs + 100),
      ]);
      final oldStop = window.stop(
        oldAttempt,
        refreshRateHz: 60,
        wallTime: start.add(const Duration(microseconds: 200)),
        callbackDrain: const Duration(seconds: 1),
      );
      expect(capture.isDraining, isTrue);

      final restartedAttempt = window.start(
        wallTime: start.add(const Duration(milliseconds: 1)),
        owner: restartedRunOwner,
      );
      expect(restartedAttempt.captureStarted, isFalse);
      expect(restartedAttempt.owner, same(restartedRunOwner));
      expect(oldAttempt.owner, same(oldRunOwner));
      expect(
        restartedAttempt.unavailableReason,
        'capture_window_busy_draining',
      );
      final restartedSummary = await window.stop(
        restartedAttempt,
        refreshRateHz: 60,
        wallTime: start.add(const Duration(milliseconds: 2)),
      );
      expect(restartedSummary.frameCount, 0);
      expect(restartedSummary.captureComplete, isFalse);
      expect(restartedSummary.frameBudgetEvaluationAvailable, isFalse);
      expect(restartedSummary.missedBudgetCount, isNull);
      expect(
        restartedSummary.captureCompleteness,
        contains('capture_window_busy_draining'),
      );

      capture.recordTimings([
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 201),
      ]);
      final oldSummary = await oldStop;
      expect(oldSummary.frameCount, 1);
      expect(oldSummary.captureComplete, isTrue);
      expect(oldSummary.criticalStageDurationUs['worst'], 5000);

      final nextFreshAttempt = window.start(
        wallTime: start.add(const Duration(milliseconds: 3)),
      );
      expect(nextFreshAttempt.captureStarted, isTrue);
      capture.recordTimings([
        _timing(buildUs: 2000, rasterUs: 3000, wallTimeUs: startUs + 3100),
      ]);
      final freshStop = window.stop(
        nextFreshAttempt,
        refreshRateHz: 60,
        wallTime: start.add(const Duration(milliseconds: 3, microseconds: 200)),
        callbackDrain: const Duration(seconds: 1),
      );
      capture.recordTimings([
        _timing(buildUs: 99000, rasterUs: 99000, wallTimeUs: startUs + 3201),
      ]);
      final freshSummary = await freshStop;
      expect(freshSummary.frameCount, 1);
      expect(freshSummary.criticalStageDurationUs['worst'], 3000);
      expect(freshSummary.captureComplete, isTrue);
      capture.dispose();
    },
  );
}
