import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  (ProviderContainer, String) makeContainer({
    required ProjectConfig config,
    String name = 'Key test',
  }) {
    final container = ProviderContainer();
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(name, config)!;
    saveSystem.selectProject(projectId);
    container.read(projectConfigSyncProvider);
    return (container, projectId);
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedScalePicker(binding: fretboardBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseCMajor(WidgetTester tester) async {
    final rootTarget = find.byKey(const ValueKey('sharedScaleRoot_C'));
    final rootBounds = tester.getRect(rootTarget);
    expect(rootBounds.width, greaterThanOrEqualTo(44));
    expect(rootBounds.height, greaterThanOrEqualTo(44));
    await tester.tapAt(rootBounds.bottomRight - const Offset(1, 1));
    await tester.pumpAndSettle();
    final scaleTarget = find.byKey(const ValueKey('sharedScaleType_major'));
    final scaleBounds = tester.getRect(scaleTarget);
    expect(scaleBounds.width, greaterThanOrEqualTo(44));
    expect(scaleBounds.height, greaterThanOrEqualTo(44));
    await tester.tapAt(scaleBounds.bottomRight - const Offset(1, 1));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first project key requires confirmation and clear is confirmed',
    (tester) async {
      final (container, projectId) = makeContainer(
        config: const ProjectConfig(),
      );
      addTearDown(container.dispose);
      container.read(fretboardProvider.notifier).toggleCell(0, 0, 'E');
      final selectedCellsBefore = List.of(
        container.read(fretboardProvider).selectedCells,
      );
      await pumpPicker(tester, container);

      await chooseCMajor(tester);
      expect(find.text('Set project key?'), findsOneWidget);
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
        isNull,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
        isNull,
      );
      expect(
        container.read(fretboardProvider).selectedCells,
        selectedCellsBefore,
      );
      expect(container.read(fretboardProvider).highlightedNotes, isEmpty);

      await chooseCMajor(tester);
      await tester.tap(find.text('Set key'));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
        0,
      );
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyScaleName,
        'major',
      );
      expect(container.read(fretboardProvider).highlightedNotes, contains('C'));
      expect(
        container.read(fretboardProvider).selectedCells,
        selectedCellsBefore,
      );

      final clearKeyButton = find.byKey(
        const Key('sharedScaleClearProjectKey'),
      );
      final clearButtonBounds = tester.getSize(clearKeyButton);
      expect(clearButtonBounds.width, greaterThanOrEqualTo(44));
      expect(clearButtonBounds.height, greaterThanOrEqualTo(44));
      await tester.tap(clearKeyButton);
      await tester.pumpAndSettle();
      expect(find.text('Clear project key?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
        0,
      );
      expect(container.read(fretboardProvider).highlightedNotes, contains('C'));

      await tester.tap(clearKeyButton);
      await tester.pumpAndSettle();
      expect(find.text('Clear project key?'), findsOneWidget);
      await tester.tap(find.text('Clear key'));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
        isNull,
      );
      expect(container.read(fretboardProvider).highlightedNotes, isEmpty);
      expect(
        container.read(fretboardProvider).selectedCells,
        selectedCellsBefore,
      );
      expect(container.read(selectedProjectProvider)?.id, projectId);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'confirmation for an old project cannot update the next project',
    (tester) async {
      final (container, firstProjectId) = makeContainer(
        config: const ProjectConfig(),
        name: 'First',
      );
      addTearDown(container.dispose);
      final secondProjectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Second', const ProjectConfig())!;
      await pumpPicker(tester, container);

      await chooseCMajor(tester);
      expect(find.text('Set project key?'), findsOneWidget);
      container
          .read(saveSystemProvider.notifier)
          .selectProject(secondProjectId);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set key'));
      await tester.pumpAndSettle();

      final projects = container.read(projectsListProvider);
      expect(
        projects
            .singleWhere((project) => project.id == firstProjectId)
            .projectConfig
            ?.keyRootPc,
        isNull,
      );
      expect(
        projects
            .singleWhere((project) => project.id == secondProjectId)
            .projectConfig
            ?.keyRootPc,
        isNull,
      );
      expect(container.read(selectedProjectProvider)?.id, secondProjectId);
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}
