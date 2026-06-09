import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_track.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('track variant renders a drum lane with its block', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern(name: 'Backbeat');
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: SongwriterScreenTrack())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('drumLaneRow_$laneId')), findsOneWidget);
    expect(find.text('Beat'), findsOneWidget);
    expect(find.byKey(Key('drumBlockTile_$patternId')), findsOneWidget);

    // Let the persist debounce timer fire so the test framework doesn't
    // complain about a pending timer during teardown.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('tapping a drum block opens the drum pattern sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    final laneId = notifier.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final patternId = notifier.addDrumPattern();
    notifier.addDrumBlock(
      sectionId: sectionId,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: SongwriterScreenTrack())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('drumBlockTile_$patternId')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('drumPatternBody_$patternId')), findsOneWidget);

    // Let the persist debounce timer fire.
    await tester.pump(const Duration(milliseconds: 600));
  });
}
