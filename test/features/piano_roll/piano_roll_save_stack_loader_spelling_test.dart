import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_save_stack_loader.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('stack loader chord context follows spelling preference', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final saves = container.read(saveSystemProvider.notifier);
    final folderId = saves.createSaveFolder('Chord saves', null)!;
    saves.saveSnapshot(
      'Flat voicing',
      folderId,
      _snapshot(root: 'Bb', symbol: 'Bb'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PianoRollSaveStackLoader()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chord saves'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flat voicing'));
    await tester.pumpAndSettle();

    expect(find.text('Chord: A#'), findsOneWidget);
    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();
    expect(find.text('Chord: Bb'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

FretboardSnapshot _snapshot({required String root, required String symbol}) =>
    FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: const ['A#', 'D', 'F'],
      viewMode: FretboardViewMode.exact,
      pendingChord: PendingChord(root: root, quality: '', symbol: symbol),
    );
