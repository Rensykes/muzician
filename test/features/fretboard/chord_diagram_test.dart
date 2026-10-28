import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/chord_diagram.dart';
import 'package:muzician/models/fretboard.dart';

void main() {
  for (final baseFret in [1, 12]) {
    for (final selected in [false, true]) {
      testWidgets('centers strings at fret $baseFret with selected=$selected', (
        tester,
      ) async {
        var pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ChordDiagram(
                  voicing: ChordVoicing(
                    positions: [baseFret, null, 0, null, 0, baseFret],
                    baseFret: baseFret,
                  ),
                  openNotes: const ['E', 'B', 'G', 'D', 'A', 'E'],
                  isSelected: selected,
                  onPress: () => pressed = true,
                ),
              ),
            ),
          ),
        );
        final paintFinder = find.descendant(
          of: find.byType(ChordDiagram),
          matching: find.byType(CustomPaint),
        );
        final paintSize = tester.getSize(paintFinder);
        final painter = tester.widget<CustomPaint>(paintFinder).painter!;
        final recorder = ui.PictureRecorder();
        // Render at 2x to retain half-pixel border inset geometry.
        final canvas = Canvas(recorder)..scale(2);
        painter.paint(canvas, paintSize);
        final picture = recorder.endRecording();
        final width = (paintSize.width * 2).round();
        final height = (paintSize.height * 2).round();
        final ByteData? bytes = await tester.runAsync(() async {
          final image = await picture.toImage(width, height);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!;
        });
        picture.dispose();
        // This row intersects strings only, below the dots and fret label.
        final y = (paintSize.height * 2 * .85).floor();
        final painted = [
          for (var x = 0; x < width; x++)
            if (bytes!.getUint8((y * width + x) * 4 + 3) > 0) x,
        ];
        expect(painted, isNotEmpty);
        expect(
          painted.first,
          closeTo(width - 1 - painted.last, 1),
          reason: 'The string grid must have equal left and right gutters.',
        );
        await tester.tap(find.byType(ChordDiagram));
        expect(pressed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
