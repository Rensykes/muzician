import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('drum lane renders once per instance, sharing pattern data',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern(name: 'Backbeat');
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // One drum lane row per instance.
    expect(find.byKey(Key('sheetDrumLane_${laneId}_0')), findsOneWidget);
    expect(find.byKey(Key('sheetDrumLane_${laneId}_1')), findsOneWidget);
    // Pattern name shown in both.
    expect(find.text('Backbeat'), findsNWidgets(2));
  });

  testWidgets('sheet renders a drum lane below the harmony row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern(name: 'Backbeat');
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('sheetDrumLane_${laneId}_0')), findsOneWidget);
    expect(find.byKey(Key('sheetDrumTile_$patternId')), findsOneWidget);
    expect(find.text('Backbeat'), findsOneWidget);
  });

  testWidgets('tapping the drum tile opens the drum pattern sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern();
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('sheetDrumTile_$patternId')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('drumPatternBody_$patternId')), findsOneWidget);
  });
}
