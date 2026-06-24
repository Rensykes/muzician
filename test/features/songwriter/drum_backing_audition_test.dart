import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_machine_editor.dart';
import 'package:muzician/models/song_project.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/drum_pattern_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

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

  SongwriterProjectSnapshot projectWithHarmony() =>
      const SongwriterProjectSnapshot(
    name: 'demo',
    config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
    drumPatterns: [
      DrumPattern(
        id: 'p1',
        name: 'Beat',
        lengthTicks: 16,
        lanes: [DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0])],
      ),
    ],
    sections: [
      SongSection(
        id: 's1',
        lengthBars: 2,
        order: 0,
        lanes: [
          SongLane(
            id: 'h1',
            kind: SongLaneKind.harmony,
            order: 0,
            blocks: [
              SongBlock(
                id: 'b1',
                startBar: 0,
                spanBars: 1,
                chordNotes: ['C', 'E', 'G'],
              ),
            ],
          ),
          SongLane(
            id: 'd1',
            kind: SongLaneKind.drum,
            order: 1,
            blocks: [
              SongBlock(id: 'db1', startBar: 0, spanBars: 2, patternId: 'p1'),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> openSheet(
    WidgetTester tester,
    ProviderContainer container,
    String? sectionId,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSongwriterDrumPatternSheet(
                  context: context,
                  patternId: 'p1',
                  sectionId: sectionId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet shows the backing toggle when opened from a harmony section',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).loadProject(projectWithHarmony());

    await openSheet(tester, container, 's1');

    expect(find.byKey(const Key('backingToggle')), findsOneWidget);
  });

  testWidgets('sheet shows no backing toggle when opened without a section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).loadProject(projectWithHarmony());

    await openSheet(tester, container, null);

    expect(find.byKey(const Key('backingToggle')), findsNothing);
  });
}
