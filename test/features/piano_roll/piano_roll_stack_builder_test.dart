import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/piano_roll/piano_roll_stack_builder.dart';
import 'package:muzician/store/piano_roll_store.dart';

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 700, child: PianoRollStackBuilder()),
      ),
    ),
  );
}

void main() {
  testWidgets('shows Canonico and Avanzato tabs', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.text('Canonico'), findsOneWidget);
    expect(find.text('Avanzato'), findsOneWidget);
  });

  testWidgets('header shows recognized chord summary', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.textContaining('C'), findsWidgets);
    expect(find.textContaining('maj'), findsWidgets);
  });

  testWidgets('switching tabs preserves final notes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    expect(find.textContaining('C4'), findsWidgets);
    expect(find.textContaining('E4'), findsWidgets);
    expect(find.textContaining('G4'), findsWidgets);
  });

  testWidgets('Add Stack button exists', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(pianoRollProvider.notifier).setPitchRange(48, 84);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    expect(find.text('Add Stack'), findsOneWidget);
  });

  testWidgets('Avanzato shows edit and remove buttons, no duplicate', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    // Note rows should show edit and remove icons
    expect(find.byIcon(Icons.edit_rounded), findsWidgets);
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    // No duplicate icon
    expect(find.byIcon(Icons.content_copy_rounded), findsNothing);
  });

  testWidgets('Avanzato shows Add note button', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    expect(find.text('Add note'), findsOneWidget);
  });

  testWidgets('Add note opens wizard state and hides editable note rows', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('Degree shortcuts'), findsNothing);
  });

  testWidgets('Edit note opens wizard state and hides editable note rows', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Edit note'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('Degree shortcuts'), findsNothing);
  });

  testWidgets('wizard preview keeps flat spelling consistent with picker', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    final wizard = find.byKey(const ValueKey('stack-builder-note-wizard-card'));
    await tester.tap(find.descendant(of: wizard, matching: find.text('Db')));
    await tester.pump();

    expect(find.descendant(of: wizard, matching: find.text('Db4')), findsOne);
    expect(
      find.descendant(of: wizard, matching: find.text('C#4')),
      findsNothing,
    );
  });

  testWidgets('wizard note choices are compact instead of one per row', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    final wizard = find.byKey(const ValueKey('stack-builder-note-wizard-card'));
    final c = tester.getTopLeft(
      find.descendant(of: wizard, matching: find.text('C')).first,
    );
    final db = tester.getTopLeft(
      find.descendant(of: wizard, matching: find.text('Db')),
    );

    expect((c.dy - db.dy).abs(), lessThan(1));
  });

  testWidgets('Degree shortcuts section shown in Avanzato', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Avanzato'));
    await tester.pump();

    expect(find.text('Degree shortcuts'), findsOneWidget);
  });
}
