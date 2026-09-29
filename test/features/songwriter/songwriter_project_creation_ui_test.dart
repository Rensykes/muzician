import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<(ProviderContainer, String)> makeContainer({
    bool dirty = false,
  }) async {
    final container = ProviderContainer();
    final saveSystem = container.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject(
      'Current project',
      const ProjectConfig(),
    )!;
    saveSystem.selectProject(projectId);
    final writer = container.read(songwriterProvider.notifier);
    if (dirty) writer.addSection(label: 'Verse', lengthBars: 4);
    return (container, projectId);
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
    await tester.pumpAndSettle();
  }

  Future<void> enterProjectDetails(
    WidgetTester tester, {
    required String name,
    required HarmonyLaneInstrument instrument,
  }) async {
    await tester.tap(find.byKey(const Key('writerNewProjectButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('writerProjectNameField')),
      name,
    );
    await tester.tap(
      find.byKey(Key('writerProjectInstrument_${instrument.name}')),
    );
    await tester.tap(find.byKey(const Key('writerProjectDetailsContinue')));
    await tester.pumpAndSettle();
  }

  testWidgets('captures name and instrument; clean Writer defaults to Keep', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer();
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await enterProjectDetails(
      tester,
      name: 'Piano sketch',
      instrument: HarmonyLaneInstrument.piano,
    );
    expect(find.text('Changes in this Writer session'), findsNothing);
    await tester.pumpAndSettle();

    final projects = container.read(projectsListProvider);
    final created = projects.singleWhere(
      (project) => project.name == 'Piano sketch',
    );
    expect(
      created.projectConfig?.defaultHarmonyInstrument,
      HarmonyLaneInstrument.piano,
    );
    expect(container.read(saveSystemProvider).selectedProjectId, created.id);
    expect(container.read(songwriterProvider).sections, isEmpty);

    container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
    expect(container.read(songwriterProvider).sections, isEmpty);
  });

  testWidgets('dirty session can be kept from the Writer creation flow', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer(dirty: true);
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await enterProjectDetails(
      tester,
      name: 'Keep session',
      instrument: HarmonyLaneInstrument.fretboard,
    );
    expect(find.text('Changes in this Writer session'), findsOneWidget);
    await tester.tap(find.byKey(const Key('writerProjectDispositionKeep')));
    await tester.pumpAndSettle();

    final created = container
        .read(projectsListProvider)
        .singleWhere((project) => project.name == 'Keep session');
    expect(container.read(saveSystemProvider).selectedProjectId, created.id);
    expect(
      container
          .read(songwriterSessionsProvider)[oldProjectId]!
          .sections
          .single
          .label,
      'Verse',
    );
  });

  testWidgets('dirty session can be discarded from the Writer creation flow', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer(dirty: true);
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await enterProjectDetails(
      tester,
      name: 'Discard session',
      instrument: HarmonyLaneInstrument.fretboard,
    );
    await tester.tap(find.byKey(const Key('writerProjectDispositionDiscard')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(projectsListProvider)
          .any((project) => project.name == 'Discard session'),
      isTrue,
    );
    expect(
      container.read(songwriterSessionsProvider).containsKey(oldProjectId),
      isFalse,
    );
    container.read(saveSystemProvider.notifier).selectProject(oldProjectId);
    expect(container.read(songwriterProvider).sections, isEmpty);
  });

  testWidgets('cancelling the dirty-session choice creates no project', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer(dirty: true);
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await enterProjectDetails(
      tester,
      name: 'Cancelled project',
      instrument: HarmonyLaneInstrument.piano,
    );
    await tester.tap(find.byKey(const Key('writerProjectDispositionCancel')));
    await tester.pumpAndSettle();

    expect(container.read(projectsListProvider), hasLength(1));
    expect(container.read(saveSystemProvider).selectedProjectId, oldProjectId);
    expect(container.read(songwriterProvider).sections.single.label, 'Verse');
  });

  testWidgets('cancelling project details creates no project', (tester) async {
    final (container, oldProjectId) = await makeContainer();
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await tester.tap(find.byKey(const Key('writerNewProjectButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerProjectDetailsCancel')));
    await tester.pumpAndSettle();

    expect(container.read(projectsListProvider), hasLength(1));
    expect(container.read(saveSystemProvider).selectedProjectId, oldProjectId);
  });

  testWidgets('details require a valid name and an explicit instrument', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer();
    addTearDown(container.dispose);
    await pumpHeader(tester, container);

    await tester.tap(find.byKey(const Key('writerNewProjectButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerProjectDetailsContinue')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name with 1 to 60 characters.'), findsOneWidget);
    expect(find.text('Choose Piano or Fretboard to continue.'), findsOneWidget);
    expect(container.read(projectsListProvider), hasLength(1));
    expect(container.read(saveSystemProvider).selectedProjectId, oldProjectId);
  });

  testWidgets('project details stay usable on compact and wide screens', (
    tester,
  ) async {
    final (container, _) = await makeContainer();
    addTearDown(container.dispose);

    for (final size in [const Size(320, 480), const Size(1280, 800)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await pumpHeader(tester, container);
      await tester.tap(find.byKey(const Key('writerNewProjectButton')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('writerProjectNameField')), findsOneWidget);
      await tester.tap(find.byKey(const Key('writerProjectDetailsCancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('busy failure stays on Writer and shows an error', (
    tester,
  ) async {
    final (container, oldProjectId) = await makeContainer();
    addTearDown(container.dispose);
    container.read(writerProjectWriteFenceProvider.notifier).state = true;
    await pumpHeader(tester, container);

    await enterProjectDetails(
      tester,
      name: 'Busy project',
      instrument: HarmonyLaneInstrument.piano,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Another project change is in progress. Try again.'),
      findsOneWidget,
    );
    expect(container.read(projectsListProvider), hasLength(1));
    expect(container.read(saveSystemProvider).selectedProjectId, oldProjectId);
  });
}
