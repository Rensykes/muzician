import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'tapping the first bar cell adds the chord at that bar (not the 2nd row)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Test project', const ProjectConfig())!;
      container.read(saveSystemProvider.notifier).selectProject(projectId);
      final n = container.read(songwriterProvider.notifier);

      // Clear the key so the harmony sheet shows the tappable manual picker
      // (the diatonic chord wheel is a CustomPaint and is not key-tappable).
      n.setKey(null, null);
      n.addSection(label: 'Verse', lengthBars: 8);
      final sectionId = container.read(songwriterProvider).sections.first.id;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // The empty 8-bar lane renders one '·' placeholder per bar.
      // Tap the very first one (bar 0 — top-left) — now opens the add menu.
      expect(find.text('·'), findsNWidgets(8));
      await tester.tap(find.text('·').first);
      await tester.pumpAndSettle();

      // Tap "Add chord" in the new add menu to open the chord sheet.
      await tester.tap(find.byKey(const Key('barActionAddChord')));
      await tester.pumpAndSettle();

      // Manual picker: pick root C then quality maj (value '').
      await tester.ensureVisible(find.byKey(const Key('harmonyRoot_0')));
      await tester.tap(find.byKey(const Key('harmonyRoot_0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('harmonyQuality_')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('harmonyQuality_')));
      await tester.pumpAndSettle();

      final lane = container
          .read(songwriterProvider)
          .sections
          .first
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.harmony);
      expect(lane.blocks, hasLength(1));
      expect(lane.blocks.first.startBar, 0);
      expect(lane.harmonyInstrument, isNotNull);
      expect(
        container
            .read(songwriterProvider)
            .sections
            .first
            .lanes
            .where((candidate) => candidate.kind == SongLaneKind.save),
        isEmpty,
      );

      final createdBlock = lane.blocks.single;
      final saveId = createdBlock.saveId!;
      final initialSave = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id == saveId);
      expect(initialSave.name, 'C');
      expect(initialSave.snapshot, isA<HarmonyChordSnapshot>());
      expect(container.read(saveSystemProvider).saves, hasLength(1));
      expect(
        container.read(saveSystemProvider).writerLinks.single.saveId,
        saveId,
      );
      expect(
        container.read(saveSystemProvider).writerLinks.single.laneKind,
        SongLaneKind.harmony,
      );
      expect(find.text('C'), findsOneWidget);

      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('barActionRenameBlock')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('writerBlockNameField')),
        'Verse tag',
      );
      await tester.tap(find.byKey(const Key('writerBlockNameSave')));
      await tester.pumpAndSettle();
      expect(find.text('C'), findsOneWidget);
      expect(
        find.byKey(Key('writerBlockName_${createdBlock.id}_0')),
        findsOneWidget,
      );
      expect(find.text('Verse tag'), findsOneWidget);
      expect(
        container
            .read(saveSystemProvider)
            .saves
            .singleWhere((save) => save.id == saveId)
            .name,
        'Verse tag',
      );

      await tester.tap(find.text('C'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('barActionCreateStandaloneSave')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('barActionMakeBlockUnique')), findsNothing);
      await tester.tap(find.byKey(const Key('barActionCreateStandaloneSave')));
      await tester.pumpAndSettle();
      expect(find.text('Create standalone Save'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('writerBlockNameField')),
        'Verse tag copy',
      );
      await tester.tap(find.byKey(const Key('writerBlockNameSave')));
      await tester.pumpAndSettle();

      final unchangedBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((candidate) => candidate.kind == SongLaneKind.harmony)
          .blocks
          .single;
      expect(unchangedBlock.id, createdBlock.id);
      expect(unchangedBlock.saveId, saveId);
      final standalone = container
          .read(saveSystemProvider)
          .saves
          .singleWhere((save) => save.id != saveId);
      expect(standalone.name, 'Verse tag copy');
      expect(standalone.origin, SaveOrigin.manual);
      expect(standalone.folderId, projectId);
      expect(
        container.read(saveSystemProvider).writerLinks.single.saveId,
        saveId,
      );

      final notifier = container.read(songwriterProvider.notifier);
      notifier.addSilentBlock(
        sectionId: sectionId,
        laneId: lane.id,
        startBar: 1,
        spanBars: 1,
      );
      await tester.pumpAndSettle();
      final silentBlock = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .singleWhere((candidate) => candidate.kind == SongLaneKind.harmony)
          .blocks
          .singleWhere((block) => block.isSilent);
      expect(silentBlock.saveId, isNull);
      await tester.ensureVisible(
        find.byKey(Key('silentCell_${silentBlock.id}_0')),
      );
      await tester.tap(find.byKey(Key('silentCell_${silentBlock.id}_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barActionRenameBlock')), findsNothing);
      expect(find.byKey(const Key('barActionMakeBlockUnique')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Writer layout fits compact and wide viewports', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final projectId = container
        .read(saveSystemProvider.notifier)
        .createProject('Test project', const ProjectConfig())!;
    container.read(saveSystemProvider.notifier).selectProject(projectId);
    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 8);

    for (final size in [const Size(390, 844), const Size(1180, 820)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SongwriterScreenSheet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VERSE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
