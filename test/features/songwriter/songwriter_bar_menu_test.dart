import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('showBarActionSheet renders items and invokes the tapped action',
      (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('open'),
              child: const SizedBox(),
              onPressed: () => showBarActionSheet(
                context: context,
                title: 'Bar',
                actions: [
                  BarAction(
                    key: const Key('act_a'),
                    label: 'Action A',
                    icon: Icons.edit,
                    onTap: () => tapped = 'a',
                  ),
                  BarAction(
                    key: const Key('act_del'),
                    label: 'Remove',
                    icon: Icons.delete,
                    destructive: true,
                    onTap: () => tapped = 'del',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Action A'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.byKey(const Key('act_del')));
    await tester.pumpAndSettle();
    expect(tapped, 'del');
    expect(find.text('Action A'), findsNothing);
  });

  testWidgets('Lyrics action writes the lyric for the tapped verse',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.setSectionRepeat(sectionId, 2);
    n.addLane(sectionId: sectionId, kind: SongLaneKind.harmony, label: 'Harmony');
    final laneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: const SongBlock(
        id: 'b1',
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: 'maj',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final secondRow = find.byKey(Key('sectionInstance_${sectionId}_1'));
    expect(secondRow, findsOneWidget);
    await tester.tap(find.descendant(of: secondRow, matching: find.text('C')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('barActionLyrics')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('verseLyricField')), 'second verse words');
    await tester.tap(find.byKey(const Key('verseLyricSave')));
    await tester.pumpAndSettle();

    final block = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).blocks.first;
    expect(block.lyrics, ['', 'second verse words']);
  });

  testWidgets('tapping a chord opens the action sheet and does not remove it',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.harmony, label: 'Harmony');
    final laneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony).id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: const SongBlock(
        id: 'b1', startBar: 0, spanBars: 1, chordSymbol: 'C',
        chordQuality: 'maj', chordRootPc: 0, chordNotes: ['C', 'E', 'G'],
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionChangeChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(
      container.read(songwriterProvider).sections.first.lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony).blocks.length,
      1,
    );
  });

  testWidgets('tapping a standalone save opens a menu and does not remove it',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final saveLaneId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.save).id;
    n.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: 'save-xyz',
      startBar: 0,
      spanBars: 1,
    );
    final saveBlockId = container.read(songwriterProvider).sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.save).blocks.first.id;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(Key('saveCell_${saveBlockId}_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionRemoveSave')), findsOneWidget);
    expect(
      container.read(songwriterProvider).sections.first.lanes
          .firstWhere((l) => l.kind == SongLaneKind.save).blocks.length,
      1,
    );
  });
}
