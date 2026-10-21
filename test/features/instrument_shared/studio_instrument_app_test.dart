import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/fretboard/capo_control.dart';
import 'package:muzician/features/piano/piano_range_selector.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final guitar in [true, false]) {
    for (final size in [
      const Size(320, 844),
      const Size(390, 844),
      const Size(1024, 768),
    ]) {
      testWidgets(
        'actual ${guitar ? 'Fretboard' : 'Piano'} Setup keeps controls before subdued Clear at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = size.width == 320
              ? 1.5
              : 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const MuzicianApp(),
            ),
          );
          final destination = find.byKey(
            ValueKey(guitar ? 'nav_Fretboard' : 'nav_Piano'),
          );
          for (var i = 0; i < 30 && destination.evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(destination);
          await tester.pumpAndSettle();
          if (guitar) {
            container.read(fretboardProvider.notifier).toggleCell(0, 0, 'E');
          } else {
            container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
          }
          await tester.pumpAndSettle();
          final setup = find.byKey(const Key('instrumentInspectorSetup'));
          await tester.ensureVisible(setup);
          await tester.pumpAndSettle();
          await tester.tap(setup);
          await tester.pumpAndSettle();
          final clear = find.text('Clear all selections');
          final clearButton = find.byKey(
            const Key('instrumentClearAllSelections'),
          );
          expect(tester.widget(clearButton), isA<TextButton>());
          expect(tester.getSize(clearButton).height, greaterThanOrEqualTo(44));
          expect(
            tester.getTopLeft(clearButton).dy -
                tester
                    .getBottomLeft(
                      find.byType(guitar ? CapoControl : PianoRangeSelector),
                    )
                    .dy,
            inInclusiveRange(8, 12),
          );
          expect(
            find.text(guitar ? 'CAPO' : 'RANGE'),
            guitar ? findsNothing : findsOneWidget,
          );
          final mode = find.byType(
            guitar
                ? ModeSegment<FretboardViewMode>
                : ModeSegment<PianoViewMode>,
          );
          expect(
            tester.getTopLeft(mode).dy -
                tester.getBottomLeft(find.text('VIEW MODE')).dy,
            lessThanOrEqualTo(8),
          );
          final clearPosition = tester.getTopLeft(clearButton);
          final stateBeforeTheme = guitar
              ? container.read(fretboardProvider)
              : container.read(pianoProvider);
          await container
              .read(settingsProvider.notifier)
              .setThemeVariant(AppThemeVariant.studioMuzician);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(clearButton), clearPosition);
          expect(
            guitar
                ? container.read(fretboardProvider)
                : container.read(pianoProvider),
            same(stateBeforeTheme),
          );
          await tester.ensureVisible(clear);
          await tester.pumpAndSettle();
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(
            guitar
                ? container.read(fretboardProvider).selectedNotes
                : container.read(pianoProvider).selectedNotes,
            isEmpty,
          );
          expect(
            find.byKey(const Key('instrumentInspectorSetup')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(WorkspaceHeader),
              matching: find.text(guitar ? 'Fretboard' : 'Piano'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('actual tuning context honors live display spelling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MuzicianApp(),
      ),
    );
    final destination = find.byKey(const ValueKey('nav_Fretboard'));
    for (var i = 0; i < 30 && destination.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(destination);
    await tester.pumpAndSettle();
    container.read(fretboardProvider.notifier).setTuning(TuningName.ebStandard);
    await tester.pumpAndSettle();
    expect(find.text('D# Standard · Capo off'), findsOneWidget);
    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();
    expect(find.text('Eb Standard · Capo off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
