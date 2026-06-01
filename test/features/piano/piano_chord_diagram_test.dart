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
