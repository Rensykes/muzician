import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
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
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      index,
      reason: 'The app should restore $workspace on a $viewport view.',
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

      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
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
      ('song', 3),
      ('writer', 4),
    ]) {
      final useGenerousRollMount = viewport == 'wide' && workspace == 'roll';
      final testViewport = useGenerousRollMount ? 'generous wide' : viewport;
      testWidgets('startup restores $workspace on $testViewport view', (
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

    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
  });

  testWidgets('visiting Settings does not replace the restored workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      settingsStorageKey: jsonEncode({'lastContentWorkspace': 'song'}),
    });

    await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
    await _pumpUntil(tester, find.byType(IndexedStack));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);

    await tester.tap(find.byKey(const ValueKey('nav_Settings')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 5);
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
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 3);
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
      expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
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
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 4);
  });
}
