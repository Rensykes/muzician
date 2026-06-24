import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/drum_library_sheet.dart';
import 'package:muzician/schema/rules/drum_presets.dart';

void main() {
  testWidgets('library sheet lists presets by category and fires onPick', (
    tester,
  ) async {
    DrumPreset? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDrumLibrarySheet(
                context: context,
                onPick: (p) => picked = p,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Rock'), findsWidgets);
    expect(find.byKey(const Key('preset_Four on the Floor')), findsOneWidget);

    await tester.tap(find.byKey(const Key('preset_Four on the Floor')));
    await tester.pumpAndSettle();

    expect(picked?.name, 'Four on the Floor');
  });
}
