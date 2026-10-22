import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_screen.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $finder.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> expectRestoredWorkspace(
    WidgetTester tester, {
    required String viewport,
    required Size size,
    required String workspace,
    required int index,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      settingsStorageKey: jsonEncode({'lastContentWorkspace': workspace}),
    });

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      index,
      reason:
          'The app should open tab $index for the $workspace preference on a $viewport view.',
    );
  }

  testWidgets('malformed data blocks workspace mounting and stays intact', (
    tester,
  ) async {
    const raw = '{ "writer": [broken] }';
    SharedPreferences.setMockInitialValues({songwriterSessionsStorageKey: raw});

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.text('Some saved data could not be read'));

    expect(find.text('Some saved data could not be read'), findsOneWidget);
    expect(find.byType(IndexedStack), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(songwriterSessionsStorageKey), raw);
    expect(prefs.getString(settingsStorageKey), isNull);
  });

  testWidgets(
    'first run mounts the Writer workspace without writing a preference',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
      await _pumpUntil(tester, find.byType(IndexedStack));

      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        4,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(settingsStorageKey), isNull);
    },
  );

  for (final (viewport, size) in [
    ('compact', const Size(393, 844)),
    ('wide', const Size(1180, 820)),
  ]) {
    for (final (workspace, index) in const [
      ('fretboard', 0),
      ('piano', 1),
      ('roll', 2),
      ('song', 4),
      ('writer', 4),
    ]) {
      final useGenerousRollMount = viewport == 'wide' && workspace == 'roll';
      final testViewport = useGenerousRollMount ? 'generous wide' : viewport;
      final restoredWorkspace = workspace == 'song'
          ? 'Writer for the disabled Song preference'
          : workspace;
      testWidgets('startup restores $restoredWorkspace on $testViewport view', (
        tester,
      ) async {
        await expectRestoredWorkspace(
          tester,
          viewport: testViewport,
          size: useGenerousRollMount ? const Size(1800, 1000) : size,
          workspace: workspace,
          index: index,
        );
      });
    }
  }

  testWidgets('invalid workspace preference falls back to Writer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsStorageKey: jsonEncode({'lastContentWorkspace': 'settings'}),
    });

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      4,
    );
  });

  testWidgets('visiting Settings does not replace the restored workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsStorageKey: jsonEncode({'lastContentWorkspace': 'song'}),
    });

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      4,
    );

    await tester.tap(find.byKey(const ValueKey('nav_Settings')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      5,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      AppSettings.fromJson(
        (jsonDecode(prefs.getString(settingsStorageKey)!) as Map)
            .cast<String, dynamic>(),
      ).lastContentWorkspace,
      'song',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      4,
    );
  });

  testWidgets(
    'Song is disabled and tapping it leaves the workspace unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(393, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MuzicianApp(),
        ),
      );
      await _pumpUntil(tester, find.byType(IndexedStack));
      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        4,
      );

      final saveState = container.read(saveSystemProvider);
      final writerState = container.read(songwriterProvider);
      final songState = container.read(songProjectProvider);
      final settingsState = container.read(settingsProvider);
      final songTab = find.byKey(const ValueKey('nav_Song'));
      final semantics = tester.getSemantics(songTab).getSemanticsData();
      expect(semantics.label, 'Song');
      expect(semantics.hint, 'Temporarily unavailable');
      expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
      expect(semantics.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(songTab);
      await tester.pumpAndSettle();

      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        4,
      );
      expect(find.byType(SongScreen), findsNothing);
      expect(container.read(saveSystemProvider), same(saveState));
      expect(container.read(songwriterProvider), same(writerState));
      expect(container.read(songProjectProvider), same(songState));
      expect(container.read(settingsProvider), same(settingsState));
    },
  );

  testWidgets('Settings exposes the persistent flat spelling switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));
    await tester.tap(find.byKey(const ValueKey('nav_Settings')));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const ValueKey('settings_note_spelling'));
    await tester.ensureVisible(switchFinder);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      AppSettings.fromJson(
        (jsonDecode(prefs.getString(settingsStorageKey)!) as Map)
            .cast<String, dynamic>(),
      ).noteSpelling,
      NoteSpelling.flats,
    );
  });

  testWidgets(
    'workspace read failure offers Retry and keeps workspace unmounted',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        songwriterSessionsStorageKey: true,
      });

      await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
      await _pumpUntil(tester, find.text('Could not load your workspaces'));

      expect(find.text('Could not load your workspaces'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(IndexedStack), findsNothing);

      SharedPreferences.setMockInitialValues({});
      await tester.tap(find.text('Retry'));
      await _pumpUntil(tester, find.byType(IndexedStack));
      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        4,
      );
    },
  );

  testWidgets('save-system read failure retries after storage is available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'@muzician/save-system/v3': true});

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.text('Could not load your workspaces'));

    expect(find.text('Could not load your workspaces'), findsOneWidget);
    expect(find.byType(IndexedStack), findsNothing);
    SharedPreferences.setMockInitialValues({});
    await tester.tap(find.text('Retry'));
    await _pumpUntil(tester, find.byType(IndexedStack));
    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
      4,
    );
  });
}
