import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a short save browser scrolls as one area from a save row', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final viewport in [
      const Size(390, 300),
      const Size(390, 844),
      const Size(800, 600),
      const Size(1180, 820),
    ]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final container = _panelContainer();
      await container.read(settingsProvider.notifier).hydrate();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SaveBrowserPanel(rootFolderId: 'project')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport $viewport');

      if (viewport.height == 300) {
        final verticalScrollables = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        );
        expect(verticalScrollables, findsOneWidget);
        final panelScroll = tester.state<ScrollableState>(verticalScrollables);

        await tester.drag(find.text('Save 00'), const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.drag(find.text('Save 12'), const Offset(0, -300));
        await tester.pumpAndSettle();

        expect(panelScroll.position.pixels, greaterThan(0));
        final lastSaveRect = tester.getRect(find.text('Save 19'));
        expect(lastSaveRect.top, greaterThanOrEqualTo(0));
        expect(lastSaveRect.bottom, lessThanOrEqualTo(viewport.height));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets('save row delete and reorder controls expose 44px targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = _panelContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).hydrate();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SaveBrowserPanel(rootFolderId: 'project')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveBrowserEditToggle')));
    await tester.pumpAndSettle();

    for (final control in [
      find.byKey(const Key('saveBrowserDelete-save-00')),
      find.byKey(const Key('saveBrowserMoveUp-save-01')),
      find.byKey(const Key('saveBrowserMoveDown-save-01')),
    ]) {
      final rect = tester.getRect(control);
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
      final data = tester.getSemantics(control).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    }

    expect(
      tester
          .getSemantics(find.byKey(const Key('saveBrowserDelete-save-00')))
          .label,
      'Delete save',
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('saveBrowserMoveUp-save-01')))
          .label,
      'Move save up',
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('saveBrowserMoveDown-save-01')))
          .label,
      'Move save down',
    );
    semantics.dispose();
  });
}

ProviderContainer _panelContainer() => ProviderContainer(
  overrides: [
    saveSystemProvider.overrideWith(
      () => _SeededSaveSystemNotifier(_stateWithManySaves()),
    ),
  ],
);

SaveSystemState _stateWithManySaves() {
  final snapshot = FretboardSnapshot(
    tuning: TuningName.standard,
    numFrets: 12,
    capo: 0,
    selectedCells: const [],
    selectedNotes: const [],
    viewMode: FretboardViewMode.exact,
  );
  return SaveSystemState(
    folders: const [
      SaveFolder(
        id: 'project',
        name: 'Project',
        createdAt: 1,
        order: 0,
        kind: SaveFolderKind.project,
      ),
    ],
    saves: List.generate(
      20,
      (index) => SaveEntry(
        id: 'save-${index.toString().padLeft(2, '0')}',
        name: 'Save ${index.toString().padLeft(2, '0')}',
        folderId: 'project',
        snapshot: snapshot,
        createdAt: index + 2,
        updatedAt: index + 2,
        order: index,
      ),
    ),
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
