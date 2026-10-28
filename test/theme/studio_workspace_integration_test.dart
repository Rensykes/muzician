import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_roll_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final (size, scale) in [
    (const Size(320, 844), 1.5),
    (const Size(390, 844), 1.0),
    (const Size(844, 390), 1.0),
    (const Size(1024, 768), 1.0),
  ]) {
    testWidgets(
      'populated workspaces retain edits through themes at $size/$scale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MuzicianApp(),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.byType(IndexedStack).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(IndexedStack), findsWidgets);
        final saves = container.read(saveSystemProvider.notifier);
        final project = saves.createProject(
          'Studio integration project with a long readable name',
          const ProjectConfig(),
        )!;
        saves.selectProject(project);
        await tester.pumpAndSettle();
        container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
        container.read(fretboardProvider.notifier).toggleCell(0, 0, 'E');
        container.read(pianoRollProvider.notifier).addNote(60, 0, 4);
        final writer = container.read(songwriterProvider.notifier);
        writer.addSection(label: 'Verse', lengthBars: 4);
        await tester.pumpAndSettle();
        final piano = container.read(pianoProvider);
        final guitar = container.read(fretboardProvider);
        final roll = container.read(pianoRollProvider);
        final draft = container.read(songwriterProvider);
        final undoCount = writer.undoCount;
        expect(undoCount, greaterThan(0));
        final shell = tester.element(find.byType(IndexedStack).first);

        for (final variant in [
          AppThemeVariant.studioMuzician,
          AppThemeVariant.studio,
        ]) {
          await tester.tap(find.byKey(const ValueKey('nav_Settings')));
          await tester.pumpAndSettle();
          final choice = find.byKey(ValueKey('settings_theme_${variant.name}'));
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await tester.pumpAndSettle();
          expect(container.read(settingsProvider).themeVariant, variant);
          expect(
            StudioPalette.of(tester.element(choice)),
            variant == AppThemeVariant.studio
                ? StudioPalette.studio
                : StudioPalette.studioMuzician,
          );
          for (final destination in ['Fretboard', 'Piano', 'Roll', 'Writer']) {
            await tester.tap(find.byKey(ValueKey('nav_$destination')));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$destination / $variant',
            );
          }
          expect(tester.element(find.byType(IndexedStack).first), same(shell));
          expect(container.read(saveSystemProvider).selectedProjectId, project);
          expect(container.read(pianoProvider), same(piano));
          expect(container.read(fretboardProvider), same(guitar));
          expect(container.read(pianoRollProvider), same(roll));
          expect(container.read(songwriterProvider), same(draft));
          expect(writer.undoCount, undoCount);
          final prefs = await SharedPreferences.getInstance();
          final persisted =
              jsonDecode(prefs.getString(settingsStorageKey)!) as Map;
          expect(persisted['themeVariant'], variant.name);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
