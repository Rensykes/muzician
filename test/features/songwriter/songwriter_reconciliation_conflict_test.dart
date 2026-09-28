import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'recovery banner fits compact and wide layouts and opens both saved versions',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final saves = container.read(saveSystemProvider.notifier);
      final projectId = saves.createProject(
        'Conflict project',
        const ProjectConfig(),
      )!;
      saves.selectProject(projectId);
      saves.saveSnapshot(
        'Previous chord',
        projectId,
        const WriterBlockSnapshot(
          laneKind: SongLaneKind.harmony,
          chordSymbol: 'C',
          chordQuality: '',
          chordRootPc: 0,
          chordNotes: ['C', 'E', 'G'],
        ),
      );

      final writer = container.read(songwriterProvider.notifier);
      writer.addSection(label: 'Verse', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      final laneId = writer.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
      );
      writer.addHarmonyBlock(
        sectionId: sectionId,
        laneId: laneId,
        block: const SongBlock(
          id: 'recovered-block',
          startBar: 0,
          spanBars: 1,
          chordSymbol: 'Dm7',
          chordQuality: 'm7',
          chordRootPc: 2,
          chordNotes: ['D', 'F', 'A', 'C'],
        ),
        saveName: 'Recovered chord',
      );
      final actualProjectId = container
          .read(saveSystemProvider)
          .selectedProjectId!;
      container.read(writerReconciliationConflictsProvider.notifier).state = [
        WriterReconciliationConflict(
          projectId: actualProjectId,
          blockId: 'recovered-block',
          canonicalSaveId: 'previous-save',
          recoveredSaveId: container
              .read(songwriterProvider)
              .sections
              .single
              .lanes
              .single
              .blocks
              .single
              .saveId!,
        ),
      ];

      final child = UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      );
      for (final size in [
        const Size(320, 844),
        const Size(390, 844),
        const Size(1180, 820),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(child);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('writerReconciliationConflictBanner')),
          findsOneWidget,
        );
        expect(find.text('Review both versions'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(child);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('writerReconciliationReviewSaves')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(writerReconciliationConflictsProvider),
        isEmpty,
        reason: 'opening the review acknowledges the recovery notice',
      );
      expect(find.text('Previous chord'), findsOneWidget);
      await tester.tap(find.text('Verse').last);
      await tester.pumpAndSettle();
      expect(find.text('Recovered chord').last, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
