import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/ui/project_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lists projects + dump + new-project entry', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    final pA = c.read(saveSystemProvider.notifier)
        .createProject('Alpha', const ProjectConfig())!;
    c.read(saveSystemProvider.notifier).createProject('Beta', const ProjectConfig());
    c.read(saveSystemProvider.notifier).ensureDumpFolder();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ProjectPickerSheet(allowDump: true))),
    ));
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

  testWidgets('Dump suppressed when allowDump=false', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    c.read(saveSystemProvider.notifier).ensureDumpFolder();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ProjectPickerSheet(allowDump: false))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Dump'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
