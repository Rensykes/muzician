import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_detection_panel.dart';
import 'package:muzician/store/piano_store.dart';

void main() {
  testWidgets('Piano: empty selection collapses the panel', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsNothing);
  });

  testWidgets('Piano: selecting 2 keys shows DETECTION header', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(pianoProvider.notifier);
    final keys = notifier.getKeys();
    final c4 = keys.firstWhere((k) => k.midiNote == 60);
    final e4 = keys.firstWhere((k) => k.midiNote == 64);
    notifier.toggleKey(c4.keyIndex, c4.midiNote, c4.noteName);
    notifier.toggleKey(e4.keyIndex, e4.midiNote, e4.noteName);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SharedDetectionPanel(binding: pianoBinding)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DETECTION'), findsOneWidget);
  });
}
