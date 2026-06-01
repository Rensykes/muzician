import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/instrument_shared/shared_scale_picker.dart';
import 'package:muzician/store/fretboard_store.dart';
import 'package:muzician/store/piano_store.dart';

// Label for the Major scale pill, from scaleGroups[ScaleCategory.common].
const _majorLabel = 'Major';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Fretboard binding: selecting root+scale shows named chip', (
    tester,
  ) async {
    await _pump(tester, SharedScalePicker(binding: fretboardBinding));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_majorLabel).first);
    await tester.pumpAndSettle();
    expect(find.text('C major'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
  });

  testWidgets('Piano binding: selecting root+scale shows named chip', (
    tester,
  ) async {
    await _pump(tester, SharedScalePicker(binding: pianoBinding));
    await tester.tap(find.text('C').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_majorLabel).first);
    await tester.pumpAndSettle();
    expect(find.text('C major'), findsOneWidget);
    expect(find.text('✕'), findsOneWidget);
  });
}
