import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lyrics lane renders its text and an add-lyric affordance', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.lyrics,
      label: 'Lyrics',
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.lyrics)
        .id;
    n.addLyricBlock(
      sectionId: section.id,
      laneId: laneId,
      startBar: 0,
      spanBars: 4,
      text: 'first line of the song',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(Key('sheetLyricLane_${laneId}_0')), findsOneWidget);
    expect(find.text('first line of the song'), findsOneWidget);
  });

  testWidgets('Add lyrics lane menu action creates a lyrics lane', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('sheetSectionMenu_${section.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addLyricLaneSheetAction')));
    await tester.pumpAndSettle();

    final lanes = container.read(songwriterProvider).sections.first.lanes;
    expect(lanes.where((l) => l.kind == SongLaneKind.lyrics), hasLength(1));
  });

  testWidgets('tapping a lyric tile edits its text via the dialog', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.lyrics,
      label: 'Lyrics',
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.lyrics)
        .id;
    n.addLyricBlock(
      sectionId: section.id,
      laneId: laneId,
      startBar: 0,
      spanBars: 4,
      text: 'old',
    );
    final blockId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.lyrics)
        .blocks
        .first
        .id;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('sheetLyricTile_$blockId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('lyricLaneEditField')),
      'new words',
    );
    await tester.tap(find.byKey(const Key('lyricLaneEditSave')));
    await tester.pumpAndSettle();

    final block = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.lyrics)
        .blocks
        .first;
    expect(block.lyrics, ['new words']);
  });
}
