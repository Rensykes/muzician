import 'package:flutter/material.dart';
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

  testWidgets(
    'grid Use in Writer action has a 44px target and works on compact and wide layouts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          saveSystemProvider.overrideWith(
            () => _SeededSaveSystemNotifier(_stateWithWriterSave()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).hydrate();
      await container.read(settingsProvider.notifier).setSaveBrowserGrid(true);

      final usedSaveIds = <String>[];
      for (final viewport in [const Size(320, 800), const Size(1024, 768)]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SaveBrowserPanel(
                  rootFolderId: 'project',
                  allowedInstruments: const {'writer_block'},
                  onUseInWriter: (save) => usedSaveIds.add(save.id),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Writer idea'));
        await tester.pumpAndSettle();

        final action = find.byKey(const Key('useWriterSaveAction'));
        expect(action, findsOneWidget);
        final actionRect = tester.getRect(action);
        expect(actionRect.width, greaterThanOrEqualTo(44));
        expect(actionRect.height, greaterThanOrEqualTo(44));
        expect(actionRect.left, greaterThanOrEqualTo(0));
        expect(actionRect.right, lessThanOrEqualTo(viewport.width));

        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(usedSaveIds.last, 'save');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

SaveSystemState _stateWithWriterSave() {
  const project = SaveFolder(
    id: 'project',
    name: 'Project',
    createdAt: 1,
    order: 0,
    kind: SaveFolderKind.project,
  );
  const writerSave = SaveEntry(
    id: 'save',
    name: 'Writer idea',
    folderId: 'project',
    snapshot: WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: 'Am7',
      chordNotes: ['A', 'C', 'E', 'G'],
    ),
    createdAt: 2,
    updatedAt: 2,
    order: 0,
    origin: SaveOrigin.writer,
  );
  return const SaveSystemState(
    folders: [project],
    saves: [writerSave],
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
