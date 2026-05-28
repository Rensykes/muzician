import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_project_store.dart';

Future<ProviderContainer> _setupDrumProject(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(songProjectProvider.notifier);
  final trackId = notifier.addTrack(SongTrackType.drum);
  final clipId = notifier.createEmptyDrumPatternClip(
    trackId: trackId,
    startTick: 0,
    patternName: 'Beat',
  );
  final patternId = container
      .read(songProjectProvider)
      .clips
      .firstWhere((clip) => clip.id == clipId)
      .patternId;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: DrumMachineEditor(clipId: clipId, patternId: patternId),
      ),
    ),
  );

  return container;
}

void main() {
  testWidgets('DrumMachineEditor renders pattern name and Make unique', (
    tester,
  ) async {
    await _setupDrumProject(tester);
    expect(find.text('Beat'), findsOneWidget);
    expect(find.text('Make unique'), findsOneWidget);
    expect(find.text('Used in 1 clips'), findsOneWidget);
  });

  testWidgets('DrumMachineEditor renders all 8 drum lanes', (tester) async {
    await _setupDrumProject(tester);
    expect(find.text('Kick'), findsOneWidget);
    expect(find.text('Snare'), findsOneWidget);
    expect(find.text('Closed HH'), findsOneWidget);
    expect(find.text('Open HH'), findsOneWidget);
    expect(find.text('Clap'), findsOneWidget);
    expect(find.text('Low Tom'), findsOneWidget);
    expect(find.text('High Tom'), findsOneWidget);
    expect(find.text('Crash'), findsOneWidget);
  });

  testWidgets('tapping a step cell toggles it', (tester) async {
    final container = await _setupDrumProject(tester);

    // Find a step cell (any GestureDetector inside a _StepCell — we use
    // the fact that step cells are the leaf GestureDetector widgets in the
    // drum grid; they each wrap a single Container child with margin 2).
    final stepCells = find.byWidgetPredicate(
      (w) =>
          w is GestureDetector &&
          w.child is Container &&
          (w.child as Container).margin != null,
    );
    expect(stepCells, findsWidgets);

    // Tap the first step cell (tick 0 in kick lane — the first lane row)
    await tester.tap(stepCells.first);
    await tester.pump();

    // Verify state was updated: kick lane tick 0 should now be active
    final project = container.read(songProjectProvider);
    final pattern = project.drumPatterns.first;
    final kickLane = pattern.lanes.firstWhere(
      (l) => l.laneId == DrumLaneId.kick,
    );
    expect(kickLane.activeTicks, contains(0));
  });
}
