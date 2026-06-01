import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano/piano_save_panel.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: PianoSavePanel())),
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
  testWidgets(
    'loading a snapshot with a scale syncs pending and active scale',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final folderId = container
          .read(saveSystemProvider.notifier)
          .createSaveFolder('Piano Saves', null);
      expect(folderId, isNotNull);

      final saveId = container
          .read(saveSystemProvider.notifier)
          .saveSnapshot(
            'With Scale',
            folderId!,
            PianoSnapshot(
              currentRange: PianoRangeName.key61,
              selectedKeys: const [],
              selectedNotes: const [],
              viewMode: PianoViewMode.exact,
              pendingScale: const PendingScale(root: 'D', scaleName: 'dorian'),
            ),
          );
      expect(saveId, isNotNull);

      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      await _loadSave(
        tester,
        folderName: 'Piano Saves',
        saveName: 'With Scale',
      );

      expect(container.read(pianoPendingScaleProvider), (
        root: 'D',
        scaleName: 'dorian',
      ));
      expect(container.read(pianoActiveScaleProvider), (
        root: 'D',
        scaleName: 'dorian',
      ));
    },
  );
}
