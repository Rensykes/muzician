import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('help button starts the Writer coach tour', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SongwriterScreenSheet()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('writerHelpButton')));
    await tester.pumpAndSettle();

    expect(find.text('Header'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });
}
