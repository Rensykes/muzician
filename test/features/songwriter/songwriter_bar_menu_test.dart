import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

String _createPianoSave(ProviderContainer container) {
  final saves = container.read(saveSystemProvider.notifier);
  final projectId = saves.createProject('Test project', const ProjectConfig())!;
  saves.selectProject(projectId);
  return saves.saveSnapshot(
    'Piano idea',
    projectId,
    PianoSnapshot(
      currentRange: PianoRangeName.key61,
      selectedKeys: const [],
      selectedNotes: const ['C4', 'E4', 'G4'],
      viewMode: PianoViewMode.exact,
    ),
  )!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'showBarActionSheet renders items and invokes the tapped action',
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
    },
  );

  testWidgets('Lyrics action writes the lyric for the tapped verse', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.setSectionRepeat(sectionId, 2);
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony)
        .id;
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
      find.byKey(const Key('verseLyricField')),
      'second verse words',
    );
    await tester.tap(find.byKey(const Key('verseLyricSave')));
    await tester.pumpAndSettle();

    final block = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony)
        .blocks
        .first;
    expect(block.lyrics, ['', 'second verse words']);
  });

  testWidgets('tapping a chord opens the action sheet and does not remove it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony)
        .id;
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

    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionChangeChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(
      container
          .read(songwriterProvider)
          .sections
          .first
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony)
          .blocks
          .length,
      1,
    );
  });

  testWidgets('Change chord keeps shared placement links and lyrics', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    final projectId = saves.createProject(
      'Shared Writer chord',
      const ProjectConfig(),
    )!;
    saves.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final verseId = container.read(songwriterProvider).sections.single.id;
    final verseLaneId = writer.addLane(
      sectionId: verseId,
      kind: SongLaneKind.harmony,
    );
    writer.addHarmonyBlock(
      sectionId: verseId,
      laneId: verseLaneId,
      block: const SongBlock(
        id: 'shared-chord',
        startBar: 1,
        spanBars: 2,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
        lyrics: ['Verse lyric'],
      ),
    );
    final source = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .single
        .blocks
        .single;
    final saveId = source.saveId!;

    writer.addSection(label: 'Chorus', lengthBars: 8);
    final chorusId = container.read(songwriterProvider).sections.last.id;
    final chorusLaneId = writer.addLane(
      sectionId: chorusId,
      kind: SongLaneKind.harmony,
    );
    expect(
      writer.insertWriterBlockFromSave(
        saveId: saveId,
        sectionId: chorusId,
        laneKind: SongLaneKind.harmony,
        startBar: 3,
        spanBars: 2,
        laneId: chorusLaneId,
      ),
      isTrue,
    );
    final chorus = container
        .read(songwriterProvider)
        .sections
        .last
        .lanes
        .single
        .blocks
        .single;
    writer.setBlockLyric(
      sectionId: chorusId,
      laneId: chorusLaneId,
      blockId: chorus.id,
      verseIndex: 0,
      text: 'Chorus lyric',
    );
    final child = UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
    );
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();

    final undoCount = writer.undoCount;
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barActionChangeChord')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyRoot_2')));
    await tester.pumpAndSettle();
    final minorSeven = find.byKey(const Key('harmonyQuality_m7'));
    await tester.ensureVisible(minorSeven);
    await tester.tap(minorSeven);
    await tester.pumpAndSettle();

    final sections = container.read(songwriterProvider).sections;
    final updatedVerse = sections
        .singleWhere((section) => section.id == verseId)
        .lanes
        .single
        .blocks
        .single;
    final updatedChorus = sections
        .singleWhere((section) => section.id == chorusId)
        .lanes
        .single
        .blocks
        .single;
    expect(writer.undoCount, undoCount + 1);
    expect(updatedVerse.id, source.id);
    expect(updatedVerse.saveId, saveId);
    expect(updatedVerse.startBar, 1);
    expect(updatedVerse.spanBars, 2);
    expect(updatedVerse.chordSymbol, 'Dm7');
    expect(updatedVerse.lyrics, ['Verse lyric']);
    expect(updatedChorus.saveId, saveId);
    expect(updatedChorus.startBar, 3);
    expect(updatedChorus.spanBars, 2);
    expect(updatedChorus.chordSymbol, 'Dm7');
    expect(updatedChorus.lyrics, ['Chorus lyric']);
    expect(
      (container
                  .read(saveSystemProvider)
                  .saves
                  .singleWhere((save) => save.id == saveId)
                  .snapshot
              as WriterBlockSnapshot)
          .chordSymbol,
      'Dm7',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an empty bar opens an add menu', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('·').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionAddChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionAddLibrary')), findsOneWidget);
  });

  testWidgets('tapping a standalone save opens a menu and does not remove it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveId = _createPianoSave(container);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final saveLaneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    n.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: saveId,
      startBar: 0,
      spanBars: 1,
    );
    final saveBlockId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
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

    await tester.tap(find.byKey(Key('saveCell_${saveBlockId}_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionRemoveSave')), findsOneWidget);
    expect(
      container
          .read(songwriterProvider)
          .sections
          .first
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.save)
          .blocks
          .length,
      1,
    );
  });

  testWidgets('long-pressing a chord removes it (with undo)', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.harmony)
        .id;
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

    await tester.longPress(find.text('C').first);
    await tester.pumpAndSettle();

    // Long-press removes the chord directly (no menu).
    expect(
      container
          .read(songwriterProvider)
          .sections
          .first
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony)
          .blocks,
      isEmpty,
    );
    // Undo affordance shown.
    expect(find.text('Block removed'), findsOneWidget);

    // Drain the undo snackbar's auto-dismiss timer before teardown.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('save menu offers Lyrics and writes the save block lyric', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveId = _createPianoSave(container);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final saveLaneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    n.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: saveId,
      startBar: 0,
      spanBars: 1,
    );
    final saveBlockId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
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

    await tester.tap(find.byKey(Key('saveCell_${saveBlockId}_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barActionLyrics')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('verseLyricField')),
      'sing here',
    );
    await tester.tap(find.byKey(const Key('verseLyricSave')));
    await tester.pumpAndSettle();

    final saveBlock = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .blocks
        .first;
    expect(saveBlock.lyrics, ['sing here']);
  });

  testWidgets('a save cell renders its verse lyric', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(sectionId: sectionId, kind: SongLaneKind.save, label: 'Guitar');
    final saveLaneId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .id;
    n.addSaveBlock(
      sectionId: sectionId,
      laneId: saveLaneId,
      saveId: 'save-xyz',
      startBar: 0,
      spanBars: 1,
    );
    final saveBlockId = container
        .read(songwriterProvider)
        .sections
        .first
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.save)
        .blocks
        .first
        .id;
    n.setBlockLyric(
      sectionId: sectionId,
      laneId: saveLaneId,
      blockId: saveBlockId,
      verseIndex: 0,
      text: 'verse one',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('verse one'), findsOneWidget);
  });
}
