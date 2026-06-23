import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';

void main() {
  group('DrumPatternPlaybackNotifier', () {
    late List<({List<DrumLaneId> lanes, double volume})> events;

    ProviderContainer makeContainer() {
      events = [];
      final c = ProviderContainer(
        overrides: [
          drumPatternPlaybackSinkProvider.overrideWithValue((
            lanes,
            volume,
          ) async {
            events.add((lanes: lanes, volume: volume));
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    DrumPattern pattern() => const DrumPattern(
      id: 'dp1',
      name: 'Beat',
      lengthTicks: 4,
      lanes: [
        DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
        DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [2]),
      ],
    );

    test('starts idle with no current tick', () {
      final c = makeContainer();
      final state = c.read(drumPatternPlaybackProvider);
      expect(state.status, DrumPatternPlaybackStatus.idle);
      expect(state.currentTick, isNull);
    });

    test('fires active lanes and loops while playing, then stops', () async {
      final c = makeContainer();
      final notifier = c.read(drumPatternPlaybackProvider.notifier);

      // Fast tempo keeps the test quick: tick = (60000 / 6000) / 4 = 2.5ms.
      unawaited(notifier.start(pattern: pattern(), tempo: 6000));

      expect(
        c.read(drumPatternPlaybackProvider).status,
        DrumPatternPlaybackStatus.playing,
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));
      notifier.stop();

      final firedLanes = events.expand((e) => e.lanes).toSet();
      expect(firedLanes, contains(DrumLaneId.kick));
      expect(firedLanes, contains(DrumLaneId.snare));

      final state = c.read(drumPatternPlaybackProvider);
      expect(state.status, DrumPatternPlaybackStatus.idle);
      expect(state.currentTick, isNull);
    });

    test('start is a no-op while already playing', () async {
      final c = makeContainer();
      final notifier = c.read(drumPatternPlaybackProvider.notifier);
      unawaited(notifier.start(pattern: pattern(), tempo: 6000));
      // Second start should not throw or restart; status stays playing.
      unawaited(notifier.start(pattern: pattern(), tempo: 6000));
      expect(
        c.read(drumPatternPlaybackProvider).status,
        DrumPatternPlaybackStatus.playing,
      );
      notifier.stop();
    });

    test(
      'loop clock is wall-anchored: per-loop body cost does not accumulate '
      'as drift',
      () async {
        // One active hit per 8-tick loop carries a heavy synchronous cost.
        // Without wall-clock anchoring this is added on top of every loop, so
        // reaching the 5th hit takes far longer than the ideal span. Anchored,
        // the cost is absorbed by the seven cost-free ticks that follow it.
        final fifthHit = Completer<void>();
        var hits = 0;
        final c = ProviderContainer(
          overrides: [
            drumPatternPlaybackSinkProvider.overrideWithValue((
              lanes,
              volume,
            ) async {
              hits++;
              if (hits >= 5) {
                if (!fifthHit.isCompleted) fifthHit.complete();
                return; // Measure time to *reach* the 5th hit, excluding cost.
              }
              // Synchronous busy-wait (runs inline before any await),
              // simulating per-hit audio/UI work on the loop isolate.
              final spin = Stopwatch()..start();
              while (spin.elapsedMilliseconds < 12) {
                // Busy-wait.
              }
            }),
          ],
        );
        addTearDown(c.dispose);

        const p = DrumPattern(
          id: 'dp',
          name: 'Beat',
          lengthTicks: 8,
          lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
        );

        final notifier = c.read(drumPatternPlaybackProvider.notifier);
        final clock = Stopwatch()..start();
        // tempo 7500 → tick = (60000 / 7500) / 4 = 2ms. Loop span = 8 × 2 =
        // 16ms. The 5th hit is at the start of the 5th loop → tick 32 → 64ms
        // ideal. Four intervening hits inject 4 × 12 = 48ms of cost; anchored
        // that fits within the 64ms span. Unanchored total ≈ 64 + 48 = 112ms.
        unawaited(notifier.start(pattern: p, tempo: 7500));
        await fifthHit.future;
        final elapsedMs = clock.elapsedMilliseconds;
        notifier.stop();

        expect(
          elapsedMs,
          lessThan(88),
          reason: 'drift not absorbed; reached 5th hit in ${elapsedMs}ms',
        );
      },
    );

    test('empty pattern does not enter playing state', () async {
      final c = makeContainer();
      final notifier = c.read(drumPatternPlaybackProvider.notifier);
      const empty = DrumPattern(
        id: 'dp0',
        name: 'Empty',
        lengthTicks: 0,
        lanes: [],
      );
      await notifier.start(pattern: empty, tempo: 120);
      expect(
        c.read(drumPatternPlaybackProvider).status,
        DrumPatternPlaybackStatus.idle,
      );
    });
  });
}
