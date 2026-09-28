import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('recovery labels identify both saves in list and grid views', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final viewport in [const Size(390, 844), const Size(1180, 820)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      for (final gridMode in [false, true]) {
        final container = ProviderContainer(
          overrides: [
            saveSystemProvider.overrideWith(
              () => _SeededSaveSystemNotifier(_stateWithRecoveryPair()),
            ),
          ],
        );
        await container.read(settingsProvider.notifier).hydrate();
        if (gridMode) {
          await container
              .read(settingsProvider.notifier)
              .setSaveBrowserGrid(true);
        }

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: SaveBrowserPanel(rootFolderId: 'project')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Original · “Recovered harmony”'), findsOneWidget);
        if (gridMode) {
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.text('Original · “Recovered harmony”'),
                )
                .didExceedMaxLines,
            isFalse,
            reason:
                'Grid label width ${tester.getSize(find.text('Original · “Recovered harmony”'))} at $viewport',
          );
        }
        expect(find.text('original-save-id'), findsNothing);
        await tester.tap(find.text('Verse'));
        await tester.pumpAndSettle();
        expect(find.text('Recovered · “Original harmony”'), findsOneWidget);
        if (gridMode) {
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.text('Recovered · “Original harmony”'),
                )
                .didExceedMaxLines,
            isFalse,
          );
        }
        expect(find.text('original-save-id'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    }
  });

  testWidgets('header controls have 44px targets and button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final viewport in [const Size(390, 844), const Size(1180, 820)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final container = ProviderContainer(
        overrides: [
          saveSystemProvider.overrideWith(
            () => _SeededSaveSystemNotifier(_stateWithRecoveryPair()),
          ),
        ],
      );
      await container.read(settingsProvider.notifier).hydrate();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SaveBrowserPanel(
                rootFolderId: 'project',
                captureSnapshot: () => const WriterBlockSnapshot(
                  laneKind: SongLaneKind.harmony,
                  chordSymbol: 'C',
                  chordNotes: ['C', 'E', 'G'],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in [
        'saveBrowserGridToggle',
        'saveBrowserSaveHere',
        'saveBrowserNewFolder',
        'saveBrowserEditToggle',
      ]) {
        final control = find.byKey(Key(key));
        expect(control, findsOneWidget);
        final rect = tester.getRect(control);
        expect(rect.width, greaterThanOrEqualTo(44), reason: key);
        expect(rect.height, greaterThanOrEqualTo(44), reason: key);
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(viewport.width), reason: key);

        final data = tester.getSemantics(control).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue, reason: key);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: key);
      }
      expect(
        tester.getSemantics(find.byKey(const Key('saveBrowserSaveHere'))).label,
        'Save here',
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('saveBrowserNewFolder')))
            .label,
        '+ Folder',
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('saveBrowserEditToggle')))
            .label,
        'Edit',
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('saveBrowserGridToggle')))
            .label,
        'Grid view',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
    semantics.dispose();
  });
}

SaveSystemState _stateWithRecoveryPair() {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const section = SaveFolder(
    id: 'section-folder',
    name: 'Verse',
    parentId: 'project',
    createdAt: 2,
    order: 0,
    writerSectionId: 'section',
  );
  const snapshot = WriterBlockSnapshot(
    laneKind: SongLaneKind.harmony,
    chordSymbol: 'Am7',
    chordNotes: ['A', 'C', 'E', 'G'],
  );
  const original = SaveEntry(
    id: 'original-save-id',
    name: 'Original harmony',
    folderId: 'project',
    snapshot: snapshot,
    createdAt: 3,
    updatedAt: 3,
    order: 0,
  );
  const recovered = SaveEntry(
    id: 'recovered-save-id',
    name: 'Recovered harmony',
    folderId: 'section-folder',
    snapshot: snapshot,
    createdAt: 4,
    updatedAt: 4,
    order: 0,
    origin: SaveOrigin.writer,
    recoveredFromSaveId: 'original-save-id',
  );
  const link = WriterSaveLink(
    blockId: 'block',
    sectionId: 'section',
    folderId: 'section-folder',
    saveId: 'recovered-save-id',
    laneKind: SongLaneKind.harmony,
  );
  return const SaveSystemState(
    folders: [project, section],
    saves: [original, recovered],
    writerLinks: [link],
    hydrated: true,
    selectedProjectId: 'project',
  );
}

class _SeededSaveSystemNotifier extends SaveSystemNotifier {
  final SaveSystemState seed;

  _SeededSaveSystemNotifier(this.seed);

  @override
  SaveSystemState build() => seed;
}
