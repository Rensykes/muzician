import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  (ProviderContainer, String, String) seedDirtyBound() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = ss.saveSnapshot('s1', pid, c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid, saveId);
    n.setTempo(200);
    return (c, pid, saveId);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump();
  }

  testWidgets('badge shows when dirty and overwrite updates the bound save',
      (tester) async {
    final (c, _, saveId) = seedDirtyBound();
    await pump(tester, c);
    expect(find.byKey(const Key('writerUnsavedBadge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();
    final entry =
        c.read(saveSystemProvider).saves.firstWhere((s) => s.id == saveId);
    expect((entry.snapshot as SongwriterProjectSnapshot).config.tempo, 200);
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('checkbox sets always-overwrite and next save skips the dialog',
      (tester) async {
    final (c, pid, _) = seedDirtyBound();
    await pump(tester, c);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAlwaysCheckbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();
    expect(c.read(writerSaveBindingProvider)[pid]!.alwaysOverwrite, true);
    c.read(songwriterProvider.notifier).setTempo(150);
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writerSaveOverwrite')), findsNothing);
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('no badge when project is clean', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    await pump(tester, c);
    expect(find.byKey(const Key('writerUnsavedBadge')), findsNothing);
  });

  testWidgets('unbound dirty project opens the Save/Load panel on save',
      (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    c.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    await pump(tester, c);
    // Dirty + unbound → no choice dialog, opens the Save/Load sheet instead.
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writerSaveOverwrite')), findsNothing);
    expect(find.text('Save / Load'), findsOneWidget);
  });

  testWidgets('save-as-new opens the Save/Load panel', (tester) async {
    final (c, _, _) = seedDirtyBound();
    await pump(tester, c);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAsNew')));
    await tester.pumpAndSettle();
    expect(find.text('Save / Load'), findsOneWidget);
  });
}
