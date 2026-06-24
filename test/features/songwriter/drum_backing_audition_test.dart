import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';

DrumPattern _pattern() => const DrumPattern(
  id: 'p1',
  name: 'Beat',
  lengthTicks: 16,
  lanes: [
    DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.snare, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.closedHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.openHiHat, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.clap, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.lowTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.highTom, activeTicks: []),
    DrumLaneSequence(laneId: DrumLaneId.crash, activeTicks: []),
  ],
);

void main() {
  testWidgets('backing toggle is shown when a backing descriptor is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: _pattern(),
              tempo: 120,
              onChanged: (_) {},
              backing: (loopTicks: 16, notesByTick: {0: [60, 64, 67]}),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('backingToggle')), findsOneWidget);
    await tester.tap(find.byKey(const Key('backingToggle')));
    await tester.pump();
    final chip = tester.widget<FilterChip>(
      find.byKey(const Key('backingToggle')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('no backing toggle when backing is null', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DrumMachineEditorBody(
              pattern: _pattern(),
              tempo: 120,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('backingToggle')), findsNothing);
  });
}
