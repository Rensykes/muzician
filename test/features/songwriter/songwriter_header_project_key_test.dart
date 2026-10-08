import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/project_config_sync.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer({required bool withProject}) {
    final container = ProviderContainer();
    if (withProject) {
      final saveSystem = container.read(saveSystemProvider.notifier);
      final projectId = saveSystem.createProject(
        'Key test project',
        const ProjectConfig(),
      )!;
      saveSystem.selectProject(projectId);
      container.read(projectConfigSyncProvider);
    }
    return container;
  }

  Future<void> pumpTransitions(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> pumpHeader(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
      ),
    );
    await pumpTransitions(tester);
  }

  Future<void> chooseCMajor(WidgetTester tester) async {
    await tester.tap(find.text('KEY'));
    await pumpTransitions(tester);
    await tester.tap(find.byKey(const ValueKey('keyPill_major_0')));
    await pumpTransitions(tester);
  }

  testWidgets('Writer project key is confirmed and clear is confirmed', (
    tester,
  ) async {
    final container = makeContainer(withProject: true);
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await chooseCMajor(tester);
    expect(find.text('Set project key?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await pumpTransitions(tester);
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      isNull,
    );
    expect(container.read(songwriterProvider).config.keyRoot, isNull);

    await chooseCMajor(tester);
    await tester.tap(find.text('Set key'));
    await pumpTransitions(tester);
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      0,
    );
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyScaleName,
      'major',
    );
    expect(container.read(songwriterProvider).config.keyRoot, 0);

    await tester.tap(find.text('C major'));
    await pumpTransitions(tester);
    await tester.tap(find.text('Clear key'));
    await pumpTransitions(tester);
    expect(find.text('Clear project key?'), findsOneWidget);
    await tester.tap(find.text('Clear key'));
    await pumpTransitions(tester);
    expect(
      container.read(selectedProjectProvider)?.projectConfig?.keyRootPc,
      isNull,
    );
    expect(container.read(songwriterProvider).config.keyRoot, isNull);
  });

  testWidgets('Writer key remains local when no project is selected', (
    tester,
  ) async {
    final container = makeContainer(withProject: false);
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await chooseCMajor(tester);
    expect(find.text('Set project key?'), findsNothing);
    expect(container.read(songwriterProvider).config.keyRoot, 0);
    expect(container.read(songwriterProvider).config.keyScaleName, 'major');
  });

  testWidgets('Writer key labels update with spelling without changing pitch', (
    tester,
  ) async {
    final container = makeContainer(withProject: false);
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setKey(3, 'minor');
    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await pumpHeader(tester, container);

    expect(find.text('Eb minor'), findsOneWidget);
    expect(container.read(songwriterProvider).config.keyRoot, 3);

    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();

    expect(find.text('D# minor'), findsOneWidget);
    expect(container.read(songwriterProvider).config.keyRoot, 3);
  });
}
