import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_arranger_timeline.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/models/song_project.dart';

/// Regression: a single shared ScrollController attached to the ruler AND every
/// track lane scroll view trips `_positions.length == 1` the moment pan-scroll
/// reads `.offset`. With multiple tracks present, a horizontal drag on the
/// timeline must not throw.
void main() {
  testWidgets('horizontal pan-scroll with multiple lanes does not assert', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songProjectProvider.notifier);
    // Several lanes → the old shared controller attached >1 scroll position.
    for (var i = 0; i < 3; i++) {
      final trackId = notifier.addTrack(SongTrackType.drum);
      notifier.createEmptyDrumPatternClip(
        trackId: trackId,
        startTick: 0,
        patternName: 'Beat $i',
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SongArrangerTimeline(
              measureTicks: 16,
              currentPlaybackTick: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag horizontally over a track lane to trigger the pan-to-scroll path
    // that reads hScroll.offset / position / jumpTo.
    await tester.drag(find.byType(SongArrangerTimeline), const Offset(-200, 0));
    await tester.pump();

    // No exception thrown => controller no longer shared across scroll views.
    expect(tester.takeException(), isNull);
  });
}
