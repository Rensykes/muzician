import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty Writer tab shows guidance', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SongwriterScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('songwriterEmptyHint')), findsOneWidget);
  });
}
