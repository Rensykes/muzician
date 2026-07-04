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

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester, {
    required void Function(SongwriterNotifier n) seed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seed(container.read(songwriterProvider.notifier));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  testWidgets('two harmony lanes render two bar rows with labels', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    // 4 empty bar placeholders per harmony lane.
    expect(find.text('·'), findsNWidgets(8));
    // Lane labels shown when the section has more than one harmony lane.
    expect(find.text('Harmony'), findsWidgets);
    expect(find.text('Harmony 2'), findsOneWidget);
    expect(
      container.read(songwriterProvider).sections.single.lanes,
      hasLength(2),
    );
  });

  testWidgets('section menu adds a numbered harmony lane', (tester) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
      },
    );
    final sectionId = container.read(songwriterProvider).sections.single.id;

    await tester.tap(find.byKey(Key('sheetSectionMenu_$sectionId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addHarmonyLaneSheetAction')));
    await tester.pumpAndSettle();

    final lanes = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();
    expect(lanes, hasLength(2));
    expect(lanes.last.label, 'Harmony 2');
  });

  testWidgets('secondary lane header deletes the lane after confirm', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .last
        .id;

    await tester.tap(find.byKey(Key('deleteHarmonyLane_$laneId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDeleteHarmonyLane')));
    await tester.pumpAndSettle();

    expect(
      container.read(songwriterProvider).sections.single.lanes,
      hasLength(1),
    );
  });

  testWidgets('primary harmony lane header has no delete action', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );
    final lanes = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();

    expect(
      find.byKey(Key('deleteHarmonyLane_${lanes.first.id}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('deleteHarmonyLane_${lanes.last.id}')),
      findsOneWidget,
    );
  });

  testWidgets('harmony lane header label renames the lane', (tester) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 4);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .last
        .id;

    await tester.tap(find.byKey(Key('renameHarmonyLane_$laneId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('laneRenameField')), 'Double');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      container.read(songwriterProvider).sections.single.lanes.last.label,
      'Double',
    );
    expect(find.text('Double'), findsOneWidget);
  });

  testWidgets('lyric bar action only offered on the primary harmony lane', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final l1 = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony',
        );
        final l2 = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        for (final l in [l1, l2]) {
          n.addHarmonyBlock(
            sectionId: s,
            laneId: l,
            block: const SongBlock(
              id: '',
              startBar: 0,
              spanBars: 1,
              chordSymbol: 'C',
              chordNotes: ['C', 'E', 'G'],
            ),
          );
        }
      },
    );

    // Both lanes show the chord cell.
    expect(find.text('C'), findsNWidgets(2));

    // Primary lane's chord: action sheet offers the lyric action.
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barActionLyrics')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss
    await tester.pumpAndSettle();

    // Secondary lane's chord: no lyric action.
    await tester.tap(find.text('C').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(find.byKey(const Key('barActionLyrics')), findsNothing);
  });

  testWidgets('secondary empty bar offers library saves too', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    await tester.tap(find.text('·').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionAddChord')), findsOneWidget);
    expect(find.byKey(const Key('barActionAddLibrary')), findsOneWidget);
  });

  testWidgets('secondary add-chord sheet offers library saves too', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony 2');
      },
    );

    await tester.tap(find.text('·').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('barActionAddChord')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fromLibraryButton')), findsOneWidget);
  });

  testWidgets('secondary chord action does not expose primary save removal', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        final primary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony',
        );
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        final saveLane = n.addLane(
          sectionId: s,
          kind: SongLaneKind.save,
          label: 'Save',
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: primary,
          block: const SongBlock(
            id: 'primary-c',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'C',
            chordQuality: 'maj',
            chordRootPc: 0,
            chordNotes: ['C', 'E', 'G'],
          ),
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: secondary,
          block: const SongBlock(
            id: 'secondary-g',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'G',
            chordQuality: 'maj',
            chordRootPc: 7,
            chordNotes: ['G', 'B', 'D'],
          ),
        );
        n.addSaveBlock(
          sectionId: s,
          laneId: saveLane,
          saveId: 'save-xyz',
          startBar: 0,
          spanBars: 1,
        );
      },
    );

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barActionRemove')), findsOneWidget);
    expect(find.byKey(const Key('barActionRemoveSave')), findsNothing);
  });

  testWidgets('secondary chord tools expose the library too', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        n.addHarmonyBlock(
          sectionId: s,
          laneId: secondary,
          block: const SongBlock(
            id: 'secondary-g',
            startBar: 0,
            spanBars: 1,
            chordSymbol: 'G',
            chordQuality: 'maj',
            chordRootPc: 7,
            chordNotes: ['G', 'B', 'D'],
          ),
        );
      },
    );

    await tester.tap(find.text('G'));
    await tester.pumpAndSettle();

    expect(find.text('Voicings & library'), findsOneWidget);

    await tester.tap(find.byKey(const Key('barActionVoicings')));
    await tester.pumpAndSettle();

    expect(find.text('Voicings'), findsOneWidget);
    expect(find.text('Harmony'), findsWidgets);
    expect(find.text('Library'), findsOneWidget);
    // Lyrics stay primary-only, so the edit label omits them here.
    expect(find.text('Edit chord'), findsOneWidget);
    expect(find.text('Edit chord & lyrics'), findsNothing);
  });

  testWidgets('anchored save renders on its harmony lane row only', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      seed: (n) {
        n.addSection(label: 'Verse', lengthBars: 2);
        final s = n.state.sections.single.id;
        n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
        final secondary = n.addLane(
          sectionId: s,
          kind: SongLaneKind.harmony,
          label: 'Harmony 2',
        );
        n.addLibraryBlockAt(
          sectionId: s,
          saveId: 'save-xyz',
          startBar: 1,
          anchorLaneId: secondary,
        );
      },
    );

    final saveLane = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .singleWhere((l) => l.kind == SongLaneKind.save);
    expect(
      saveLane.anchorLaneId,
      container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.label == 'Harmony 2')
          .id,
    );
    final blockId = saveLane.blocks.single.id;
    // Exactly one standalone save cell across both harmony rows.
    expect(find.byKey(Key('saveCell_${blockId}_0')), findsOneWidget);
  });
}
