import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('detected scale updates a project only after confirmation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Detection key',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    container.read(projectConfigSyncProvider);
    container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selectedNotesBefore = List.of(
      container.read(pianoProvider).selectedNotes,
    );
    final scaleChip = find.text('C major');
    expect(scaleChip, findsWidgets);

    await tester.tap(scaleChip.first);
    await tester.pumpAndSettle();
    expect(find.text('Set project key?'), findsOneWidget);
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(pianoProvider).selectedNotes, selectedNotesBefore);
    expect(container.read(pianoPendingScaleProvider), isNull);
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      isNull,
    );

    await tester.tap(find.text('C major').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set key'));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      0,
    );
    expect(container.read(pianoActiveScaleProvider), (
      root: 'C',
      scaleName: 'major',
    ));
    expect(container.read(pianoPendingScaleProvider), isNull);
    expect(container.read(pianoProvider).selectedNotes, selectedNotesBefore);
    await tester.pump(const Duration(milliseconds: 600));
  });
}
