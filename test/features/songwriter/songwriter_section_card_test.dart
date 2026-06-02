import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_section_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('section card shows label and an add-lane button', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(label: 'Chorus', lengthBars: 8);
    final id = container.read(songwriterProvider).sections.single.id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: SongwriterSectionCard(sectionId: id))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Chorus'), findsOneWidget);
    expect(find.byKey(Key('addLane_$id')), findsOneWidget);
    // drain the store's 500 ms debounce timer so no pending timer assertion fires
    await tester.pump(const Duration(milliseconds: 600));
  });
}
