import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/save_system/data_recovery_panel.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/persisted_data_recovery_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _recoveryKey(String sourceKey, int index) {
  final encoded = base64Url.encode(utf8.encode(sourceKey)).replaceAll('=', '');
  return '$dataRecoveryStoragePrefix${1000 + index}:$index:$encoded';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final viewport in const [
    (name: 'compact portrait', size: Size(390, 844)),
    (name: 'wide landscape', size: Size(1180, 820)),
  ]) {
    testWidgets('Data Recovery actions fit ${viewport.name}', (tester) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const raw = '{ "writer": [broken] }';
      final backupKey = _recoveryKey('@muzician/writer', 0);
      SharedPreferences.setMockInitialValues({backupKey: raw});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(dataRecoveryProvider.notifier).hydrate();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DataRecoveryPanel()),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(Key('recoveryEntry_$backupKey')));
      await tester.pumpAndSettle();

      expect(find.byKey(Key('recoveryCopy_$backupKey')), findsOneWidget);
      expect(find.byKey(Key('recoveryExport_$backupKey')), findsOneWidget);
      expect(find.byKey(Key('recoveryDelete_$backupKey')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'copy is exact; cancel and selective delete preserve other data',
    (tester) async {
      const rawOne = '{ "writer": [broken] }\n';
      const rawTwo = '{  "song": [broken]  }';
      final keyOne = _recoveryKey('@muzician/writer', 0);
      final keyTwo = _recoveryKey('@muzician/song', 1);
      SharedPreferences.setMockInitialValues({keyOne: rawOne, keyTwo: rawTwo});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(dataRecoveryProvider.notifier).hydrate();
      await container.read(saveSystemProvider.notifier).hydrate();
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Current project', const ProjectConfig())!;
      container.read(saveSystemProvider.notifier).selectProject(projectId);

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DataRecoveryPanel()),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(Key('recoveryEntry_$keyOne')));
      await tester.pumpAndSettle();
      expect(find.text(rawOne), findsOneWidget);

      await tester.tap(find.byKey(Key('recoveryCopy_$keyOne')));
      await tester.pump();
      expect(copiedText, rawOne);

      await tester.tap(find.byKey(Key('recoveryDelete_$keyOne')));
      await tester.pumpAndSettle();
      expect(find.text('Delete recovery backup?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(dataRecoveryProvider), hasLength(2));

      await tester.tap(find.byKey(Key('recoveryDelete_$keyOne')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete backup').last);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(keyOne), isNull);
      expect(prefs.getString(keyTwo), rawTwo);
      expect(container.read(dataRecoveryProvider), hasLength(1));
      expect(container.read(dataRecoveryProvider).single.raw, rawTwo);
      expect(container.read(saveSystemProvider).selectedProjectId, projectId);
    },
  );
}
