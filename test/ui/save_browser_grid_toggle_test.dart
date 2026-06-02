import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the grid toggle flips the saveBrowserGrid pref',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).hydrate();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SaveBrowserPanel(instrumentFilter: 'fretboard')),
      ),
    ));

    expect(container.read(settingsProvider).saveBrowserGrid, false);
    await tester.tap(find.byKey(const Key('saveBrowserGridToggle')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).saveBrowserGrid, true);
  });
}
