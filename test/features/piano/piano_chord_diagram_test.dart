import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano/piano_chord_diagram.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders label and note-name row', (tester) async {
    await tester.pumpWidget(
      host(
        PianoChordDiagram(
          midis: const [60, 64, 67], // C E G
          rootPc: 0,
          label: 'Root',
          noteLabels: const ['C', 'E', 'G'],
          isSelected: false,
          onPress: () {},
        ),
      ),
    );

    expect(find.text('Root'), findsOneWidget);
    expect(find.text('C E G'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tap invokes onPress', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        PianoChordDiagram(
          midis: const [60, 64, 67],
          rootPc: 0,
          label: '1 inv',
          noteLabels: const ['C', 'E', 'G'],
          isSelected: true,
          onPress: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('1 inv'));
    expect(tapped, isTrue);
  });

  testWidgets('open spacing paints the highest note across a third octave', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PianoChordDiagram(
          midis: const [71, 75, 90],
          rootPc: null,
          label: 'Open',
          noteLabels: const ['B', 'D#', 'F#'],
          isSelected: false,
          onPress: () {},
        ),
      ),
    );
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PianoChordDiagram),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(210, 60));
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(210, 60);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    });
    picture.dispose();
    // F# in the third C-aligned octave: black key at x=180, y=10.
    final pixel = (10 * 210 + 180) * 4;
    expect(bytes!.getUint8(pixel), greaterThan(80));
    expect(bytes.getUint8(pixel + 2), greaterThan(100));
  });

  testWidgets('empty voicing paints without throwing', (tester) async {
    await tester.pumpWidget(
      host(
        PianoChordDiagram(
          midis: const [],
          rootPc: null,
          label: 'Root',
          noteLabels: const [],
          isSelected: false,
          onPress: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
