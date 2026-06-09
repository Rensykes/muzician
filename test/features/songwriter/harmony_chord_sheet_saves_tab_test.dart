import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';

PianoSnapshot _piano(List<String> notes) => PianoSnapshot(
      currentRange: PianoRangeName.key49,
      selectedKeys: const [],
      selectedNotes: notes,
      viewMode: PianoViewMode.exact,
    );

FretboardSnapshot _fret(List<String> notes) => FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: notes,
      viewMode: FretboardViewMode.exact,
    );

Future<void> _openSheet(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showHarmonyChordSheet(
                ctx,
                startBar: 0,
                spanBars: 1,
                keyRoot: 0,
                keyScaleName: 'major',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<SongBlock?> _runAndCapture(
  WidgetTester tester,
  ProviderContainer container,
  Future<void> Function() body,
) async {
  SongBlock? captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                captured = await showHarmonyChordSheet(
                  ctx,
                  startBar: 0,
                  spanBars: 1,
                  keyRoot: 0,
                  keyScaleName: 'major',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await body();
  return captured;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Saves tab shows empty hint when no piano/fretboard saves',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _openSheet(tester, container);
    await tester.tap(find.byKey(const Key('savesTab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savesTabEmpty')), findsOneWidget);
  });

  testWidgets('tapping a detectable save commits a harmony block',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(saveSystemProvider.notifier);
    final folderId = notifier.createSaveFolder('Chords', null)!;
    notifier.saveSnapshot('C major triad', folderId, _piano(['C', 'E', 'G']));

    final result = await _runAndCapture(tester, container, () async {
      await tester.tap(find.byKey(const Key('savesTab')));
      await tester.pumpAndSettle();
      expect(find.text('C major triad'), findsOneWidget);
      await tester.tap(find.text('C major triad'));
      await tester.pumpAndSettle();
    });

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result.chordSymbol, 'C');
    expect(result.romanNumeral, 'I');
  });

  testWidgets('fretboard save also detects', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(saveSystemProvider.notifier);
    final folderId = notifier.createSaveFolder('Voicings', null)!;
    notifier.saveSnapshot('A minor', folderId, _fret(['A', 'C', 'E']));

    final result = await _runAndCapture(tester, container, () async {
      await tester.tap(find.byKey(const Key('savesTab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A minor'));
      await tester.pumpAndSettle();
    });

    expect(result, isNotNull);
    expect(result!.chordSymbol, 'Am');
    expect(result.chordQuality, 'm');
  });

  testWidgets(
      'undetectable save switches to Chord tab and prefills root',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(saveSystemProvider.notifier);
    final folderId = notifier.createSaveFolder('Misc', null)!;
    // Two unrelated notes — no chord template matches exactly.
    notifier.saveSnapshot('mystery', folderId, _piano(['C', 'F#']));

    await _openSheet(tester, container);
    await tester.tap(find.byKey(const Key('savesTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mystery'));
    await tester.pumpAndSettle();

    // Manual picker now visible (key was set so it was behind the
    // "Other chord" expander — fallback opened it).
    expect(find.byKey(const Key('harmonyRoot_0')), findsOneWidget);
    expect(find.byKey(const Key('harmonyQuality_')), findsOneWidget);
  });
}
