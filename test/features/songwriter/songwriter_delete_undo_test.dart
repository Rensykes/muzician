import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_section_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('deleting a section shows Undo and restores it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 8);
    final id = container.read(songwriterProvider).sections.single.id;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: SongwriterSectionCard(sectionId: id)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('removeSection_$id')));
    await tester.pumpAndSettle();
    expect(container.read(songwriterProvider).sections, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 600));
    final sections = container.read(songwriterProvider).sections;
    expect(sections.length, 1);
    expect(sections.single.label, 'Verse');
  });
}
