import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpSheet(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('repeat pill is visible even at x1', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;

    await pumpSheet(tester, container);

    expect(find.byKey(Key('repeatPill_${section.id}')), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });

  testWidgets('section shows existing lyrics for its verse', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionLyric(
      sectionId: section.id,
      verseIndex: 0,
      text: 'hello world',
    );

    await pumpSheet(tester, container);

    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('tapping the lyrics block edits the verse via the dialog', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;

    await pumpSheet(tester, container);

    await tester.tap(find.byKey(Key('sectionLyrics_${section.id}_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('sectionLyricsField')),
      'new lyrics',
    );
    await tester.tap(find.byKey(const Key('sectionLyricsSave')));
    await tester.pumpAndSettle();

    expect(container.read(songwriterProvider).sections.first.lyrics, [
      'new lyrics',
    ]);
  });

  testWidgets('a 2-verse section exposes a lyrics block per verse', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);

    await pumpSheet(tester, container);

    expect(find.byKey(Key('sectionLyrics_${section.id}_0')), findsOneWidget);
    expect(find.byKey(Key('sectionLyrics_${section.id}_1')), findsOneWidget);
  });
}
