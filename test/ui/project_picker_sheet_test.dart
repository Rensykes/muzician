import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/ui/project_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lists projects + dump + new-project entry', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    final pA = c
        .read(saveSystemProvider.notifier)
        .createProject('Alpha', const ProjectConfig())!;
    c
        .read(saveSystemProvider.notifier)
        .createProject('Beta', const ProjectConfig());
    c.read(saveSystemProvider.notifier).ensureDumpFolder();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: ProjectPickerSheet(allowDump: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Dump'), findsOneWidget);
    expect(find.textContaining('New project'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.read(saveSystemProvider).selectedProjectId, pA);
  });

  testWidgets(
    'Dump suppressed when allowDump=false',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(saveSystemProvider.notifier).hydrate();
      c.read(saveSystemProvider.notifier).ensureDumpFolder();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            home: Scaffold(body: ProjectPickerSheet(allowDump: false)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Dump'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets('first project asks for its Harmony instrument', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(settingsProvider.notifier).hydrate();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: ProjectPickerSheet(allowDump: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Piano project');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your first instrument'), findsOneWidget);
    await tester.tap(find.text('Piano'));
    await tester.pumpAndSettle();

    final project = c.read(projectsListProvider).single;
    expect(
      project.projectConfig?.defaultHarmonyInstrument,
      HarmonyLaneInstrument.piano,
    );
    expect(
      c.read(settingsProvider).defaultNewProjectHarmonyInstrument,
      HarmonyLaneInstrument.piano,
    );
    expect(c.read(saveSystemProvider).selectedProjectId, project.id);
  });

  testWidgets('cancelling first instrument choice creates no project', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(settingsProvider.notifier).hydrate();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: ProjectPickerSheet(allowDump: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cancelled project');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(c.read(projectsListProvider), isEmpty);
    expect(c.read(settingsProvider).defaultNewProjectHarmonyInstrument, isNull);
  });

  testWidgets('uses the saved default for later projects', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    await c.read(settingsProvider.notifier).hydrate();
    await c
        .read(settingsProvider.notifier)
        .setDefaultNewProjectHarmonyInstrument(HarmonyLaneInstrument.piano);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(body: ProjectPickerSheet(allowDump: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Saved default');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your first instrument'), findsNothing);
    expect(
      c
          .read(projectsListProvider)
          .single
          .projectConfig
          ?.defaultHarmonyInstrument,
      HarmonyLaneInstrument.piano,
    );
  });
}
