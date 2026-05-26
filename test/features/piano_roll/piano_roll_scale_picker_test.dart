import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_scale_picker.dart';
import 'package:muzician/store/piano_roll_store.dart';

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Material(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: const SizedBox(
            width: 800,
            height: 600,
            child: PianoRollScalePicker(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selected scale pill persists after picker rebuild', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Pre-set an active scale
    container.read(pianoRollActiveScaleProvider.notifier).state = (
      root: 'C',
      scaleName: 'major',
    );

    await tester.pumpWidget(_wrap(container));
    // First pump: post-frame callback fires, restores local state
    await tester.pump();
    // Second pump: setState from callback triggers rebuild
    await tester.pump();

    // Pill should show the selected scale (C Major)
    expect(find.text('C Major'), findsOneWidget);

    // Re-simulate drawer close/reopen by rebuilding widget tree
    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump();

    // Pill should still be visible
    expect(find.text('C Major'), findsOneWidget);
  });

  testWidgets('pending scale prefill takes priority over active then clears', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Set active to C major
    container.read(pianoRollActiveScaleProvider.notifier).state = (
      root: 'C',
      scaleName: 'major',
    );
    // Set pending to D dorian
    container.read(pianoRollPendingScaleProvider.notifier).state = (
      root: 'D',
      scaleName: 'dorian',
    );

    await tester.pumpWidget(_wrap(container));
    // First pump: post-frame callback fires (pending takes priority)
    await tester.pump();
    // Second pump: rebuild from setState
    await tester.pump();

    // Pending prefill should take priority -> D Dorian shown
    expect(find.text('D Dorian'), findsOneWidget);

    // After processing, pending should be null
    expect(container.read(pianoRollPendingScaleProvider), isNull);
    // Active should now be updated to pending value
    final activeAfter = container.read(pianoRollActiveScaleProvider);
    expect(activeAfter, isNotNull);
    expect(activeAfter!.root, 'D');
    expect(activeAfter.scaleName, 'dorian');
  });

  testWidgets('clear resets active and removes selected scale pill', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Set active scale
    container.read(pianoRollActiveScaleProvider.notifier).state = (
      root: 'C',
      scaleName: 'major',
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pump();
    await tester.pump();

    // Pill should be visible
    expect(find.text('C Major'), findsOneWidget);

    // Tap the clear (✕) button on the pill
    await tester.tap(find.text('✕'));
    await tester.pump();

    // Pill should be gone (C Major no longer visible)
    expect(find.text('C Major'), findsNothing);
    // Active should be null
    expect(container.read(pianoRollActiveScaleProvider), isNull);
  });
}
