import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/writer_save_choice_dialog.dart';

void main() {
  testWidgets('returns overwrite with dontAskAgain when checkbox + overwrite',
      (tester) async {
    WriterSaveChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result =
                  await showWriterSaveChoiceDialog(context, saveName: 'X'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAlwaysCheckbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();
    expect(result!.action, WriterSaveAction.overwrite);
    expect(result!.dontAskAgain, true);
  });

  testWidgets('returns saveAsNew', (tester) async {
    WriterSaveChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result =
                  await showWriterSaveChoiceDialog(context, saveName: 'X'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAsNew')));
    await tester.pumpAndSettle();
    expect(result!.action, WriterSaveAction.saveAsNew);
    expect(result!.dontAskAgain, false);
  });
}
