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
          drumPatternPlaybackSinkProvider.overrideWithValue((lanes, volume) async {
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
