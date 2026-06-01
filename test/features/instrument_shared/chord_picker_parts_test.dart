import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/instrument_shared/chord_picker_parts.dart';

void main() {
  testWidgets('ChordPickerHeader renders title + active badge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChordPickerHeader(title: 'CHORD VOICINGS', root: 'C', quality: 'm7'),
        ),
      ),
    );
    expect(find.text('CHORD VOICINGS'), findsOneWidget);
    expect(find.textContaining('C'), findsWidgets);
  });

  testWidgets('RootPillRow reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RootPillRow(
            selectedRoot: null,
            accent: Colors.green,
            onTap: (r) => tapped = r,
          ),
        ),
      ),
    );
    await tester.tap(find.text('C').first);
    expect(tapped, 'C');
  });
}
