import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard_save_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/save_system_store.dart';

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: FretboardSavePanel())),
  );
}

Future<void> _loadSave(
  WidgetTester tester, {
  required String folderName,
  required String saveName,
}) async {
  await tester.tap(find.text(folderName));
  await tester.pumpAndSettle();
  await tester.tap(find.text(saveName));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Load'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loading a snapshot without a scale clears stale activeScale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeScaleProvider.notifier).state = (
      root: 'C',
      scaleName: 'major',
    );

    final saveSystem = container.read(saveSystemProvider.notifier);
    final dumpId = saveSystem.ensureDumpFolder();
    saveSystem.selectProject(dumpId);
    final folderId = container
        .read(saveSystemProvider.notifier)
        .createSaveFolder('Fretboard Saves', dumpId);
    expect(folderId, isNotNull);

    final saveId = container
        .read(saveSystemProvider.notifier)
        .saveSnapshot(
          'No Scale',
          folderId!,
          FretboardSnapshot(
            tuning: TuningName.standard,
            numFrets: 12,
            capo: 0,
            selectedCells: const [],
            selectedNotes: const [],
            viewMode: FretboardViewMode.exact,
          ),
        );
    expect(saveId, isNotNull);

    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await _loadSave(
      tester,
      folderName: 'Fretboard Saves',
      saveName: 'No Scale',
    );

    expect(container.read(activeScaleProvider), isNull);
    expect(container.read(pendingScaleProvider), isNull);
  });
}
