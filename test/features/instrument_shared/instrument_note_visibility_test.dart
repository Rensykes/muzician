import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/models/piano.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CircleCanvas implements Canvas {
  final centers = <Offset>[];

  @override
  void drawCircle(Offset center, double radius, Paint paint) {
    // Exclude fret position markers (radius 5).
    if (radius > 5) centers.add(center);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: StudioTheme.data(AppThemeVariant.studio),
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    for (final input in FretboardInputMode.values) {
      testWidgets('Fretboard Full/Solo controls bubbles in $input at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(fretboardProvider.notifier);
        notifier.setInputMode(input);
        notifier.setCapo(2);
        notifier.toggleCell(0, 2, 'F#');
        notifier.toggleFocusedNote('F#');
        await tester.pumpWidget(
          _host(container, const GuitarFretboard(hideToolbar: true)),
        );
        await tester.pumpAndSettle();

        Set<Offset> paintedPositions() {
          final paint = tester.widget<CustomPaint>(
            find.byWidgetPredicate(
              (w) =>
                  w is CustomPaint &&
                  w.painter.runtimeType.toString() == '_FretboardPainter',
            ),
          );
          final canvas = _CircleCanvas();
          paint.painter!.paint(canvas, paint.size);
          return canvas.centers.toSet();
        }

        expect(paintedPositions(), hasLength(6 * 25));
        notifier.setViewMode(FretboardViewMode.exactFocus);
        await tester.pump();
        expect(paintedPositions(), hasLength(1));
        // Selected physical fret 2, including capo, remains in place.
        expect(paintedPositions().single, const Offset(190, 36));
        notifier.clearSelectedNotes();
        await tester.pump();
        expect(paintedPositions(), isEmpty);
        notifier.setViewMode(FretboardViewMode.exact);
        await tester.pump();
        expect(paintedPositions(), hasLength(6 * 25));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Piano Solo keeps all keys but only selected labels at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pianoProvider.notifier);
      notifier.loadExactMidis([36, 37]);
      notifier.toggleFocusedNote('C');
      await tester.pumpWidget(
        _host(container, const PianoKeyboard(hideToolbar: true)),
      );
      await tester.pumpAndSettle();
      final keys = find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label?.contains('MIDI') ?? false),
      );
      expect(keys, findsNWidgets(61));
      expect(find.byType(Text), findsNWidgets(61));
      notifier.setViewMode(PianoViewMode.exactFocus);
      await tester.pump();
      expect(keys, findsNWidgets(61));
      expect(find.byType(Text), findsNWidgets(2));
      expect(find.text('C2'), findsOneWidget);
      expect(find.text('C#2'), findsOneWidget);
      expect(find.text('C3'), findsNothing);
      notifier.clearSelectedNotes();
      await tester.pump();
      expect(keys, findsNWidgets(61));
      expect(find.byType(Text), findsNothing);
      // Unlabelled keys still expose accessible names and selection handlers.
      final unlabelled = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'D2, MIDI 38',
      );
      final gesture = tester.widget<GestureDetector>(
        find.descendant(of: unlabelled, matching: find.byType(GestureDetector)),
      );
      expect(gesture.onTap, isNotNull);
      notifier.setViewMode(PianoViewMode.exact);
      await tester.pump();
      expect(find.byType(Text), findsNWidgets(61));
      expect(tester.takeException(), isNull);
    });
  }
}
