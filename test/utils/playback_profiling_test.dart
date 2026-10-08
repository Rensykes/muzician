import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/note_player.dart';
import 'package:muzician/utils/playback_profiling.dart';

void main() {
  group('PlaybackProfileRunStats', () {
    test('keeps denominator and reconciles launched and terminal outcomes', () {
      final run = PlaybackProfileRunStats(runId: 7, expectedVoiceCount: 3);
      final clock = Stopwatch()..start();
      final event = PlaybackProfileEventContext(
        run: run,
        eventId: 2,
        scoreTick: 16,
        deadlineUs: 2000000,
        clock: clock,
      );
      final completed = event.nextVoice();
      final dropped = event.nextVoice(onsetOffsetUs: 125000);

      run.request(completed);
      run.launched(completed);
      run.outcome(completed, 'play_future_completed');
      run.outcome(completed, 'natural_completion');
      run.request(dropped);
      run.outcome(dropped, 'dropped_not_ready');

      final report = run.toJson();
      expect(completed.voiceId, 'r7-e2-v0');
      expect(dropped.voiceId, 'r7-e2-v1');
      expect(dropped.intendedDeadlineUs, 2125000);
      expect(report['expected_voice_count'], 3);
      expect(report['requested_voice_count'], 2);
      expect(report['launched_voice_count'], 1);
      expect(report['play_future_completed_count'], 1);
      expect(report['terminated_voice_count'], 2);
      expect(report['unknown_expected_voice_count'], 1);
      expect(report['dropped_voice_count'], 1);
      expect(report['active_voice_count'], 0);
      expect(report['pending_voice_count'], 0);
      expect(report['audible_onset_observed'], isFalse);
    });

    test('signed dispatch percentiles retain early dispatch errors', () {
      expect(playbackProfilePercentile([-400, -20, 300, 700], 0.5), -20);
      expect(playbackProfilePercentile(<int>[], 0.95), isNull);
    });

    test('reports null tick endpoints when no ticks were dispatched', () {
      final run = PlaybackProfileRunStats(runId: 9, expectedVoiceCount: 0);

      final metrics = run.toJson()['dispatch_metrics']! as Map<String, Object?>;
      expect(metrics['tick_sample_count'], 0);
      expect(metrics['first_tick_dispatch_error_us'], isNull);
      expect(metrics['last_tick_dispatch_error_us'], isNull);
      expect(metrics['tick_dispatch_error_change_us'], isNull);
    });

    test('reports a single signed tick error with zero change', () {
      final run = PlaybackProfileRunStats(runId: 10, expectedVoiceCount: 0)
        ..recordTickDispatchError(-17);

      final metrics = run.toJson()['dispatch_metrics']! as Map<String, Object?>;
      expect(metrics['tick_sample_count'], 1);
      expect(metrics['first_tick_dispatch_error_us'], -17);
      expect(metrics['last_tick_dispatch_error_us'], -17);
      expect(metrics['tick_dispatch_error_change_us'], 0);
    });

    test(
      'reports signed tick error change separately from boundary completion',
      () {
        final run = PlaybackProfileRunStats(runId: 11, expectedVoiceCount: 0)
          ..recordTickDispatchError(-500)
          ..recordTickDispatchError(-20)
          ..recordTickDispatchError(150)
          ..recordTickDispatchError(250)
          ..scoreBoundarySample = playbackScoreBoundarySample(
            runId: 11,
            lastDispatchedTick: 479,
            lastTickDeadlineUs: 59875000,
            lastTickObservedUs: 59875250,
            scoreBoundaryDeadlineUs: 60000000,
            scoreBoundaryObservedUs: 59900000,
          );

        final report = run.toJson();
        final metrics = report['dispatch_metrics']! as Map<String, Object?>;
        final boundary = metrics['score_boundary_sample']! as Map;
        expect(metrics['first_tick_dispatch_error_us'], -500);
        expect(metrics['last_tick_dispatch_error_us'], 250);
        expect(metrics['tick_dispatch_error_change_us'], 750);
        expect(boundary['last_tick_dispatch_error_us'], 250);
        expect(boundary['completion_vs_score_boundary_error_us'], -100000);
      },
    );

    test(
      'reports zero change when several signed samples end at their start',
      () {
        final run = PlaybackProfileRunStats(runId: 12, expectedVoiceCount: 0)
          ..recordTickDispatchError(-50)
          ..recordTickDispatchError(400)
          ..recordTickDispatchError(-50);

        final metrics =
            run.toJson()['dispatch_metrics']! as Map<String, Object?>;
        expect(metrics['first_tick_dispatch_error_us'], -50);
        expect(metrics['last_tick_dispatch_error_us'], -50);
        expect(metrics['tick_dispatch_error_change_us'], 0);
      },
    );

    test('score end records final tick drift separately from completion', () {
      final sample = playbackScoreBoundarySample(
        runId: 3,
        lastDispatchedTick: 479,
        lastTickDeadlineUs: 59875000,
        lastTickObservedUs: 59874950,
        scoreBoundaryDeadlineUs: 60000000,
        scoreBoundaryObservedUs: 59875100,
      );

      expect(sample['last_dispatched_tick'], 479);
      expect(sample['last_tick_dispatch_error_us'], -50);
      expect(sample['score_boundary_deadline_us'], 60000000);
      expect(sample['score_boundary_observed_us'], 59875100);
      expect(sample['completion_vs_score_boundary_error_us'], -124900);
      expect(sample['completion_vs_score_boundary_lateness_us'], 0);
      expect(sample, isNot(contains('dispatch_error_us')));
    });

    test('first terminal error survives cleanup and late completion', () {
      final run = PlaybackProfileRunStats(runId: 8, expectedVoiceCount: 1);
      final event = PlaybackProfileEventContext(
        run: run,
        eventId: 0,
        scoreTick: 0,
        deadlineUs: 0,
        clock: Stopwatch()..start(),
      );
      final voice = event.nextVoice();

      run.request(voice);
      run.launched(voice);
      run.outcome(voice, 'error');
      run.outcome(voice, 'error_cleanup');
      run.outcome(voice, 'natural_completion');

      final report = run.toJson();
      final voiceReport = (report['voices']! as List).single as Map;
      expect(voiceReport['outcome'], 'error');
      expect(voiceReport['terminated'], isTrue);
      expect(report['error_voice_count'], 1);
      expect(report['cancelled_voice_count'], 0);
      expect(report['play_future_completed_count'], 0);
    });
  });

  test('uninitialized NotePlayer records a dropped profile voice', () {
    final run = PlaybackProfileRunStats(runId: 1, expectedVoiceCount: 1);
    final context = PlaybackProfileEventContext(
      run: run,
      eventId: 0,
      scoreTick: 0,
      deadlineUs: 0,
      clock: Stopwatch()..start(),
    );

    withPlaybackProfileVoice(context.nextVoice(), () {
      NotePlayer.instance.previewNote(60);
    });

    final report = run.toJson();
    expect(report['requested_voice_count'], 1);
    expect(report['launched_voice_count'], 0);
    expect(report['dropped_voice_count'], 1);
    expect(report['terminated_voice_count'], 1);
  });
}
