import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/ui/project_gate_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Song variant hides Dump and disables Cancel', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(saveSystemProvider.notifier).hydrate();
    c.read(saveSystemProvider.notifier).createProject('Alpha', const ProjectConfig());
    c.read(saveSystemProvider.notifier).ensureDumpFolder();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(body: ProjectGateModal(allowDump: false, allowCancel: false)),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Dump'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });
}
