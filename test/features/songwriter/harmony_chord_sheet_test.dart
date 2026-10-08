import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('picking C major via manual picker returns a harmony block', (
    tester,
  ) async {
    SongBlock? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showHarmonyChordSheet(
                    context,
                    startBar: 0,
                    spanBars: 2,
                    keyRoot: null,
                    keyScaleName: null,
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

    await tester.tap(find.byKey(const Key('harmonyRoot_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result!.chordNotes, contains('C'));
    expect(result!.romanNumeral, isNull);
  });

  testWidgets('shows chord wheel when key is set', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showHarmonyChordSheet(
                  context,
                  startBar: 0,
                  spanBars: 2,
                  keyRoot: 0,
                  keyScaleName: 'major',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsOneWidget);
  });

  testWidgets('manual picker behind Other chord expander commits with key', (
    tester,
  ) async {
    SongBlock? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showHarmonyChordSheet(
                    context,
                    startBar: 0,
                    spanBars: 2,
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

    // Expand the Other chord section to reveal the manual picker.
    await tester.tap(find.text('Other chord'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('harmonyRoot_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result!.chordNotes, contains('C'));
    // Roman numeral is derived from the key context (C major key, C chord = I).
    expect(result!.romanNumeral, 'I');
  });

  testWidgets('shows root+quality grid when no key is set', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showHarmonyChordSheet(
                  context,
                  startBar: 0,
                  spanBars: 2,
                  keyRoot: null,
                  keyScaleName: null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordWheel), findsNothing);
    expect(find.text('Root'), findsOneWidget);
  });

  testWidgets(
    'unsupported keyed scale opens the manual picker and keeps its key context',
    (tester) async {
      SongBlock? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showHarmonyChordSheet(
                      context,
                      startBar: 2,
                      spanBars: 2,
                      keyRoot: 3,
                      keyScaleName: 'minor pentatonic',
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

      expect(find.byType(ChordWheel), findsNothing);
      expect(find.text('Other chord'), findsNothing);
      expect(find.text('Set a key to use the chord wheel'), findsNothing);
      expect(find.text('Root'), findsOneWidget);
      final root = find.byKey(const Key('harmonyRoot_3'));
      await tester.ensureVisible(root);
      await tester.pumpAndSettle();
      await tester.tap(root);
      expect(find.byKey(const Key('harmonyQuality_m')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('harmonyQuality_m')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('harmonyQuality_m')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.startBar, 2);
      expect(result!.spanBars, 2);
      expect(result!.chordRootPc, 3);
      expect(result!.chordQuality, 'm');
      expect(result!.chordNotes.toSet(), {'D#', 'F#', 'A#'});
      expect(result!.romanNumeral, 'i');
    },
  );

  testWidgets('flat root choices stay mapped to their canonical pitch class', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.sharps);
    SongBlock? result;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showHarmonyChordSheet(
                    context,
                    startBar: 0,
                    spanBars: 1,
                    keyRoot: null,
                    keyScaleName: null,
                  );
                },
                child: const Text('open flats test'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open flats test'));
    await tester.pumpAndSettle();
    expect(find.text('D#'), findsOneWidget);

    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();
    expect(find.text('Eb'), findsOneWidget);

    final root = find.byKey(const Key('harmonyRoot_3'));
    await tester.ensureVisible(root);
    await tester.tap(root);
    await tester.pumpAndSettle();
    final minor = find.byKey(const Key('harmonyQuality_m'));
    await tester.ensureVisible(minor);
    await tester.tap(minor);
    await tester.pumpAndSettle();

    expect(result?.chordRootPc, 3);
    expect(result?.chordSymbol, 'D#m');
  });

  testWidgets(
    'manual picker wraps compact chips and remains usable across viewports',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      for (final viewport in [
        (size: const Size(390, 844), textScale: 1.0),
        (size: const Size(390, 300), textScale: 1.0),
        (size: const Size(1180, 820), textScale: 1.0),
        (size: const Size(390, 844), textScale: 1.6),
      ]) {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        final container = ProviderContainer();
        SongBlock? result;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showHarmonyChordSheet(
                        context,
                        startBar: 2,
                        spanBars: 2,
                        keyRoot: 3,
                        keyScaleName: 'minor pentatonic',
                      );
                    },
                    child: const Text('open responsive picker'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open responsive picker'));
        await tester.pumpAndSettle();

        expect(find.byType(ChordWheel), findsNothing);
        expect(find.text('Set a key to use the chord wheel'), findsNothing);
        expect(find.text('Root'), findsOneWidget);

        final root = find.byKey(const Key('harmonyRoot_3'));
        await tester.ensureVisible(root);
        await tester.pumpAndSettle();
        final rootTarget = find.descendant(
          of: root,
          matching: find.byType(GestureDetector),
        );
        final rootRect = tester.getRect(rootTarget);
        expect(rootRect.width, greaterThanOrEqualTo(44));
        expect(rootRect.height, greaterThanOrEqualTo(44));
        expect(rootRect.width, lessThan(120));
        final rootSemantics = tester
            .getSemantics(
              find.descendant(of: root, matching: find.byType(Semantics)).first,
            )
            .getSemanticsData();
        expect(rootSemantics.label, 'D#');
        expect(rootSemantics.flagsCollection.isButton, isTrue);
        expect(rootSemantics.hasAction(SemanticsAction.tap), isTrue);
        await tester.tap(rootTarget);
        await tester.pumpAndSettle();

        final minor = find.byKey(const Key('harmonyQuality_m'));
        await tester.ensureVisible(minor);
        await tester.pumpAndSettle();
        final minorTarget = find.descendant(
          of: minor,
          matching: find.byType(GestureDetector),
        );
        final minorRect = tester.getRect(minorTarget);
        expect(minorRect.width, greaterThanOrEqualTo(44));
        expect(minorRect.height, greaterThanOrEqualTo(44));
        expect(minorRect.width, lessThan(120));
        await tester.tap(minorTarget);
        await tester.pumpAndSettle();

        expect(result, isNotNull, reason: 'viewport ${viewport.size}');
        expect(result!.chordRootPc, 3);
        expect(result!.chordQuality, 'm');
        expect(result!.romanNumeral, 'i');
        expect(
          tester.takeException(),
          isNull,
          reason: 'viewport ${viewport.size}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
      semantics.dispose();
    },
  );
}
