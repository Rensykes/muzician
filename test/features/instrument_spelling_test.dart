import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/fretboard/tuning_selector.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import '../support/test_settings_notifier.dart';

void main() {
  testWidgets('Eb Standard tuning title follows spelling preference', (
    tester,
  ) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TuningSelector())),
      ),
    );
    await tester.tap(find.text('Metal'));
    await tester.pumpAndSettle();

    expect(find.text('Eb Standard'), findsOneWidget);
    settings.changeSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();
    expect(find.text('D# Standard'), findsOneWidget);
  });

  testWidgets('piano key labels and semantics react to spelling changes', (
    tester,
  ) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 300,
              child: PianoKeyboard(hideToolbar: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('Gb4, MIDI 66'), findsOneWidget);
    expect(find.text('Gb4'), findsOneWidget);

    settings.changeSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('F#4, MIDI 66'), findsOneWidget);
    expect(find.text('F#4'), findsOneWidget);
    expect(find.text('Gb4'), findsNothing);
    semantics.dispose();
  });

  testWidgets('fretboard canvas labels and semantics repaint in flats mode', (
    tester,
  ) async {
    final settings = TestSettingsNotifier(initialSpelling: NoteSpelling.flats);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 1200, height: 450, child: GuitarFretboard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('Gb4, string 1, fret 2'), findsOneWidget);

    settings.changeSpelling(NoteSpelling.sharps);
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('F#4, string 1, fret 2'), findsOneWidget);
    semantics.dispose();
  });
}
