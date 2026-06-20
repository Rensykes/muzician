import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grid tap in palette mode invokes onPick, not load',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.hydrate();
    await settings.setSaveBrowserGrid(true);

    final ss = container.read(saveSystemProvider.notifier);
    // _savesHere only shows saves when _currentFolderId != null, so we must
    // create a folder and seed the save inside it.  The panel starts at root
    // and shows root-level folders; we tap the folder to navigate in, then tap
    // the save card.
    final folderId = ss.createSaveFolder('MyFolder', null);
    ss.saveSnapshot(
      'Riff',
      folderId!,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    );

    SaveEntry? picked;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SaveBrowserPanel(
            instrumentFilter: 'fretboard',
            onPick: (e) => picked = e,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Navigate into the folder so saves become visible.
    await tester.tap(find.text('MyFolder'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riff'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name, 'Riff');
  });

  testWidgets('list tap on empty part of the row still invokes onPick',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.hydrate();
    // List mode (not grid) is where the row stretches full width and most of
    // the row is empty space to the right of the short save name.
    await settings.setSaveBrowserGrid(false);

    final ss = container.read(saveSystemProvider.notifier);
    final folderId = ss.createSaveFolder('MyFolder', null);
    ss.saveSnapshot(
      'Riff',
      folderId!,
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    );

    SaveEntry? picked;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SaveBrowserPanel(
            instrumentFilter: 'fretboard',
            onPick: (e) => picked = e,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MyFolder'));
    await tester.pumpAndSettle();

    // Tap the centre of the name row — empty space to the right of "Riff",
    // not on the text glyphs. The whole row must be tappable.
    final rowGesture = find
        .ancestor(
          of: find.text('Riff'),
          matching: find.byType(GestureDetector),
        )
        .first;
    await tester.tap(rowGesture);
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name, 'Riff');
  });
}
