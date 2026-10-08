import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saved chord cards and details follow spelling preference', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.setSaveBrowserGrid(true);

    final saves = container.read(saveSystemProvider.notifier);
    final folderId = saves.createSaveFolder('Chord saves', null)!;
    saves.saveSnapshot('Flat voicing', folderId, _snapshot('Bb', 'Bb'));
    saves.saveSnapshot('Sharp voicing', folderId, _snapshot('A#', 'A#'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SaveBrowserPanel(instrumentFilter: 'fretboard')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chord saves'));
    await tester.pumpAndSettle();

    expect(find.text('A#'), findsNWidgets(2));
    await settings.setNoteSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();
    expect(find.text('Bb'), findsNWidgets(2));

    await settings.setSaveBrowserGrid(false);
    await tester.pumpAndSettle();
    expect(find.text('Bb'), findsNWidgets(4));
    await tester.tap(find.text('Flat voicing'));
    await tester.pumpAndSettle();
    expect(find.text('Chord: Bb'), findsNWidgets(2));

    await settings.setNoteSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();
    expect(find.text('Chord: A#'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

FretboardSnapshot _snapshot(String root, String symbol) => FretboardSnapshot(
  tuning: TuningName.standard,
  numFrets: 12,
  capo: 0,
  selectedCells: const [],
  selectedNotes: const ['A#', 'D', 'F'],
  viewMode: FretboardViewMode.exact,
  pendingChord: PendingChord(root: root, quality: '', symbol: symbol),
);
