import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/ui/save_browser_panel.dart' show SaveCardForTest;

void main() {
  testWidgets('save card shows name and chord label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SaveCardForTest(
          name: 'My Riff',
          instrument: 'fretboard',
          labelText: 'Cmaj7',
          noteChips: const [],
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('My Riff'), findsOneWidget);
    expect(find.text('Cmaj7'), findsOneWidget);
  });
}
