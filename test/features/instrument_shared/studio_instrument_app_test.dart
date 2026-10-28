import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/features/instrument_shared/instrument_screen.dart';
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
      const Size(320, 568),
      const Size(375, 667),
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
          if (guitar) {
            final board = find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint &&
                  widget.painter.runtimeType.toString() == '_FretboardPainter',
            );
            final paintedBounds = tester.getRect(board);
            final viewportBounds = tester.getRect(
              find.byKey(const Key('studioInstrumentCanvas')),
            );
            // Compact row 6 ends at y=190. The painter and its host must
            // contain it, rather than silencing overflow by cropping strings.
            expect(paintedBounds.height, greaterThanOrEqualTo(190));
            expect(
              paintedBounds.bottom,
              lessThanOrEqualTo(viewportBounds.bottom),
            );
          }
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
          final mode = find.byKey(const Key('instrumentViewMode'));
          expect(
            tester.getBottomLeft(mode).dy,
            lessThanOrEqualTo(
              tester
                  .getTopLeft(find.byKey(const Key('studioInstrumentCanvas')))
                  .dy,
            ),
          );
          expect(find.text('VIEW MODE'), findsNothing);
          expect(tester.getSize(mode).height, greaterThanOrEqualTo(44));
          expect(
            find.byType(
              guitar
                  ? InstrumentModeMenu<FretboardViewMode>
                  : InstrumentModeMenu<PianoViewMode>,
            ),
            findsOneWidget,
          );
          final selectionBefore = guitar
              ? container.read(fretboardProvider).selectedNotes
              : container.read(pianoProvider).selectedNotes;
          await tester.tap(find.byTooltip('View mode: Full'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('View mode-Solo')));
          await tester.pumpAndSettle();
          expect(find.byTooltip('View mode: Solo'), findsOneWidget);
          expect(
            guitar
                ? container.read(fretboardProvider).selectedNotes
                : container.read(pianoProvider).selectedNotes,
            selectionBefore,
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
              of: find.byType(
                size.height < 600 ? CompactAppBar : WorkspaceHeader,
              ),
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
    expect(find.byTooltip('D# Standard · Capo off'), findsOneWidget);
    await container
        .read(settingsProvider.notifier)
        .setNoteSpelling(NoteSpelling.flats);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Eb Standard · Capo off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
