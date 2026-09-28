import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('badge shows when dirty and overwrite updates the bound save', (
    tester,
  ) async {
    final (c, _, saveId) = seedDirtyBound();
    await pump(tester, c);
    expect(find.byKey(const Key('writerUnsavedBadge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();
    final entry = c
        .read(saveSystemProvider)
        .saves
        .firstWhere((s) => s.id == saveId);
    expect((entry.snapshot as SongwriterProjectSnapshot).config.tempo, 200);
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('overwrite rebases the loaded named Song version', (
    tester,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final saveSystem = c.read(saveSystemProvider.notifier);
    final projectId = saveSystem.createProject('Proj', const ProjectConfig())!;
    saveSystem.selectProject(projectId);
    final writer = c.read(songwriterProvider.notifier);
    writer.addSection(label: 'Verse', lengthBars: 4);
    final savedVersion = writer.materializeCurrentContent();
    final saveId = saveSystem.saveSnapshot(
      'First version',
      projectId,
      savedVersion,
    )!;
    await writer.loadProject(savedVersion, saveId: saveId);
    writer.setTempo(200);
    expect(c.read(writerDirtyProvider), true);

    await pump(tester, c);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();

    final entry = c
        .read(saveSystemProvider)
        .saves
        .singleWhere((save) => save.id == saveId);
    expect((entry.snapshot as SongwriterProjectSnapshot).config.tempo, 200);
    final binding = c.read(writerSaveBindingProvider)[projectId]!;
    expect(
      binding.materializedBaselineJson,
      jsonEncode(writer.materializeCurrentContent().toJson()),
    );
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('checkbox sets always-overwrite and next save skips the dialog', (
    tester,
  ) async {
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

  testWidgets('unbound dirty project opens the Save/Load panel on save', (
    tester,
  ) async {
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
    expect(find.text('Browse saves'), findsOneWidget);
  });

  testWidgets('save-as-new opens the Save/Load panel', (tester) async {
    final semantics = tester.ensureSemantics();
    final (c, _, _) = seedDirtyBound();
    await pump(tester, c);
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAsNew')));
    await tester.pumpAndSettle();
    expect(find.text('Browse saves'), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    final closeSemantics = tester
        .getSemantics(find.bySemanticsLabel('Close'))
        .getSemanticsData();
    expect(closeSemantics.flagsCollection.isButton, isTrue);
    expect(closeSemantics.hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Browse saves'), findsNothing);
    semantics.dispose();
  });
}
