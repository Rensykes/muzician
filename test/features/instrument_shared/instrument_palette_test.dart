import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/chord_diagram.dart';
import 'package:muzician/features/fretboard/fretboard.dart';
import 'package:muzician/features/piano/piano_chord_diagram.dart';
import 'package:muzician/features/piano/piano_keyboard.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'native diagrams repaint on palette change and selected MIDI stays selected',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
      final notes = container.read(pianoProvider);
      final variant = ValueNotifier(AppThemeVariant.studio);
      addTearDown(variant.dispose);
      final body = Column(
        children: [
          SizedBox(
            height: fretboardBoardHeight,
            child: const GuitarFretboard(hideToolbar: true),
          ),
          const PianoKeyboard(hideToolbar: true),
          Row(
            children: [
              ChordDiagram(
                voicing: const ChordVoicing(
                  positions: [0, 1, 0, 2, 3, null],
                  baseFret: 1,
                ),
                rootNote: 'C',
                openNotes: const ['E', 'B', 'G', 'D', 'A', 'E'],
                isSelected: true,
                onPress: () {},
              ),
              PianoChordDiagram(
                midis: const [60, 64, 67],
                rootPc: 0,
                label: 'Root',
                noteLabels: const ['C', 'E', 'G'],
                isSelected: true,
                onPress: () {},
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ValueListenableBuilder<AppThemeVariant>(
            valueListenable: variant,
            builder: (_, value, _) => MaterialApp(
              theme: StudioTheme.data(value),
              home: Scaffold(body: SingleChildScrollView(child: body)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final names = [
        '_FretboardPainter',
        '_ChordDiagramPainter',
        '_PianoChordPainter',
      ];
      Finder painter(String name) => find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == name,
      );
      final old = {
        for (final name in names)
          name: tester.widget<CustomPaint>(painter(name)).painter!,
      };
      final c4 = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == 'C4, MIDI 60, melody note',
      );
      Color keyColor() {
        final key = tester.widget<Container>(
          find
              .descendant(
                of: c4,
                matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration,
                ),
              )
              .first,
        );
        return (key.decoration! as BoxDecoration).color!;
      }

      expect(keyColor(), StudioPalette.studio.sky);
      variant.value = AppThemeVariant.studioMuzician;
      await tester.pumpAndSettle();
      for (final name in names) {
        final next = tester.widget<CustomPaint>(painter(name)).painter!;
        expect(next.shouldRepaint(old[name]!), isTrue, reason: name);
      }
      expect(keyColor(), StudioPalette.studioMuzician.sky);
      expect(container.read(pianoProvider), same(notes));
      expect(tester.takeException(), isNull);
    },
  );
}
