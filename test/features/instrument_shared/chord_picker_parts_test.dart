import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/fretboard/chord_diagram.dart';
import 'package:muzician/features/fretboard/chord_voicing_picker.dart';
import 'package:muzician/features/instrument_shared/chord_picker_parts.dart';
import 'package:muzician/store/fretboard_store.dart';

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

  testWidgets(
    'committed voicing survives the selectedNotes listener (no wipe)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChordVoicingPicker()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select root C; quality defaults to maj, so voicings render.
      await tester.tap(find.text('C').first);
      await tester.pumpAndSettle();

      // Voicing cards (ChordDiagram) should now be present.
      final cards = find.byType(ChordDiagram);
      expect(cards, findsWidgets);

      // Tap the first voicing card. This calls notifier.loadVoicing(...),
      // which mutates selectedNotes synchronously and fires the
      // selectedNotes listener BEFORE the rebuild re-registers the closure.
      // With a stale committed snapshot the listener would wipe the commit:
      // deselect the card and reset _voicingCommitted to false.
      await tester.tap(cards.first);
      await tester.pumpAndSettle();

      // The commit must survive: the committed flag stays true and exactly one
      // voicing card remains selected (its index was not wiped to null).
      expect(container.read(fretboardChordCommittedProvider), isTrue);
      final selectedCards = tester
          .widgetList<ChordDiagram>(cards)
          .where((d) => d.isSelected)
          .length;
      expect(
        selectedCards,
        1,
        reason: 'committed voicing card should stay selected after commit',
      );

      // The committed chord (C) must be published to activeChordProvider.
      final active = container.read(activeChordProvider);
      expect(active, isNotNull);
      expect(active!.root, 'C');
      expect(container.read(fretboardProvider).selectedNotes, isNotEmpty);
    },
  );
}
