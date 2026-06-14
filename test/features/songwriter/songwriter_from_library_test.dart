import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('add-bar sheet offers a "From library" button', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Tap the first empty bar cell (· placeholder) to open the add sheet.
    await tester.tap(find.text('·').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fromLibraryButton')), findsOneWidget);
  });

  test('addLibraryBlockAt inserts a save block at the given bar', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;

    n.addLibraryBlockAt(sectionId: sectionId, saveId: 'save_42', startBar: 2);

    final section = container
        .read(songwriterProvider)
        .sections
        .firstWhere((s) => s.id == sectionId);
    final saveLane =
        section.lanes.firstWhere((l) => l.kind == SongLaneKind.save);
    final block = saveLane.blocks.single;
    expect(block.saveId, 'save_42');
    expect(block.startBar, 2);
  });
}
