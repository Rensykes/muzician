import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import '../../support/test_settings_notifier.dart';

void main() {
  testWidgets('selected note chips update spelling without changing notes', (
    tester,
  ) async {
    final settings = TestSettingsNotifier();
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    final piano = container.read(pianoProvider.notifier);
    for (final midi in [61, 66]) {
      final key = piano.getKeys().firstWhere((key) => key.midiNote == midi);
      piano.toggleKey(key.keyIndex, key.midiNote, key.noteName);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('C#'), findsOneWidget);
    expect(find.text('F#'), findsOneWidget);

    settings.changeSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();

    expect(find.text('Db'), findsOneWidget);
    expect(find.text('Gb'), findsOneWidget);
    expect(find.text('C#'), findsNothing);
    expect(
      container.read(pianoProvider).selectedNotes,
      containsAll(['C#', 'F#']),
    );
  });

  testWidgets('Piano: empty selection collapses the panel', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsNothing);
  });

  testWidgets('Piano: selecting 2 keys shows DETECTION header', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pianoProvider.notifier);
    final keys = notifier.getKeys();
    final c4 = keys.firstWhere((k) => k.midiNote == 60);
    final e4 = keys.firstWhere((k) => k.midiNote == 64);
    notifier.toggleKey(c4.keyIndex, c4.midiNote, c4.noteName);
    notifier.toggleKey(e4.keyIndex, e4.midiNote, e4.noteName);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsOneWidget);
  });

  testWidgets('Fretboard Free selection explains why Writer is unavailable', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fretboard = container.read(fretboardProvider.notifier);
    fretboard.toggleCell(0, 0, 'E');
    fretboard.toggleCell(1, 0, 'B');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SharedDetectionPanel(
              binding: fretboardBinding,
              onHandoffCompleted: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handoff = tester.widget<OutlinedButton>(
      find.byKey(const Key('addInstrumentSelectionToWriter')),
    );
    expect(handoff.onPressed, isNull);
    expect(
      find.text(
        'Switch to Chord mode and keep one note per string to add this selection to Writer.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Chord mode duplicate strings are explained without clearing', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fretboard = container.read(fretboardProvider.notifier);
    fretboard.toggleCell(0, 0, 'E');
    fretboard.toggleCell(0, 2, 'G');
    fretboard.setInputMode(FretboardInputMode.chord);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SharedDetectionPanel(
              binding: fretboardBinding,
              onHandoffCompleted: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handoff = tester.widget<OutlinedButton>(
      find.byKey(const Key('addInstrumentSelectionToWriter')),
    );
    expect(handoff.onPressed, isNull);
    expect(
      find.text(
        'Chord mode requires one valid note per string. Remove extra or invalid positions to add this selection to Writer.',
      ),
      findsOneWidget,
    );
    expect(container.read(fretboardProvider).selectedCells, hasLength(2));
  });

  testWidgets('Writer handoff availability follows live Fretboard mode', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fretboard = container.read(fretboardProvider.notifier);
    fretboard.setInputMode(FretboardInputMode.chord);
    fretboard.toggleCell(0, 0, 'E');
    fretboard.toggleCell(1, 0, 'B');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SharedDetectionPanel(
              binding: fretboardBinding,
              onHandoffCompleted: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('addInstrumentSelectionToWriter')),
          )
          .onPressed,
      isNotNull,
    );

    fretboard.setInputMode(FretboardInputMode.free);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('addInstrumentSelectionToWriter')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const Key('writerHandoffUnavailableReason')),
      findsOneWidget,
    );

    fretboard.setInputMode(FretboardInputMode.chord);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('addInstrumentSelectionToWriter')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('writerHandoffUnavailableReason')),
      findsNothing,
    );
    expect(container.read(fretboardProvider).selectedCells, hasLength(2));
  });
}
