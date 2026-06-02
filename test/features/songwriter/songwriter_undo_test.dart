import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_undo.dart';

void main() {
  testWidgets('showUndoSnack shows the message and fires onUndo when tapped',
      (tester) async {
    var undone = false;
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

    showUndoSnack(ctx, 'Section deleted', () => undone = true);
    await tester.pumpAndSettle(); // let the snackbar slide fully into view
    expect(find.text('Section deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, true);
  });
}
