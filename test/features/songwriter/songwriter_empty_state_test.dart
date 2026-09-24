import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_screen.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty Writer tab shows guidance', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SongwriterScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('songwriterEmptyHint')), findsOneWidget);
  });

  testWidgets('empty Writer action creates its default eight-bar section', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('writerEmptyAddSection')));
    await tester.pump();

    expect(container.read(songwriterProvider).sections.single.lengthBars, 8);
  });
}
