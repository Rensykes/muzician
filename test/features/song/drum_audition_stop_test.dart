import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';

DrumPattern _pattern() => const DrumPattern(
  id: 'p1',
  name: 'Beat',
  lengthTicks: 4,
  lanes: [
    DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0]),
    DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: [2]),
  ],
);

void main() {
  testWidgets('closing the drum editor stops the audition loop', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        drumPatternPlaybackSinkProvider.overrideWithValue(
          (lanes, volume) async {},
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: _pattern(),
              tempo: 6000,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    // Start the looping audition (fast tempo → ~2.5ms ticks). The pacer anchors
    // to the wall clock, so the loop must run under real async (runAsync), not
    // the fake test clock.
    await tester.runAsync(() async {
      container
          .read(drumPatternPlaybackProvider.notifier)
          .start(pattern: _pattern(), tempo: 6000);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(
      container.read(drumPatternPlaybackProvider).status,
      DrumPatternPlaybackStatus.playing,
    );

    // Close the panel: replace the editor with an empty tree → body.dispose().
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();

    // dispose() stops synchronously.
    expect(
      container.read(drumPatternPlaybackProvider).status,
      DrumPatternPlaybackStatus.idle,
    );

    // Let the in-flight tick settle so the loop exits cleanly.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
