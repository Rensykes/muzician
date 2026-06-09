import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/section_lyrics_sheet.dart';

void main() {
  testWidgets('editor prefills with current lyrics and returns trimmed text',
      (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showSectionLyricsSheet(
                  context: ctx,
                  initial: 'verse one\n',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('sectionLyricsField'));
    expect(field, findsOneWidget);
    final TextField widget = tester.widget(field);
    expect(widget.controller!.text, 'verse one\n');

    await tester.enterText(field, 'verse one\nverse two\n');
    await tester.tap(find.byKey(const Key('sectionLyricsSave')));
    await tester.pumpAndSettle();

    expect(captured, 'verse one\nverse two');
  });

  testWidgets('clear button returns null', (tester) async {
    String? captured = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showSectionLyricsSheet(
                  context: ctx,
                  initial: 'existing',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sectionLyricsClear')));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
