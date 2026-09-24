import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_undo.dart';

void main() {
  testWidgets('showUndoSnack shows the message and fires onUndo when tapped', (
    tester,
  ) async {
    var undone = false;
    final revision = ValueNotifier<int>(1);
    addTearDown(revision.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    showUndoSnack(
      ctx,
      'Section deleted',
      historyRevision: revision,
      expectedRevision: 1,
      onUndo: () => undone = true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Section deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, true);
  });

  testWidgets('showUndoSnack dismisses when a later edit changes history', (
    tester,
  ) async {
    var undone = false;
    final revision = ValueNotifier<int>(1);
    addTearDown(revision.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    showUndoSnack(
      ctx,
      'Section deleted',
      historyRevision: revision,
      expectedRevision: 1,
      onUndo: () => undone = true,
    );
    await tester.pump();
    revision.value++;
    await tester.pump();

    expect(find.text('Section deleted'), findsNothing);
    expect(undone, isFalse);
  });
}
