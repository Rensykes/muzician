import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $finder.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'landscape uses the rail, portrait the bar, and switching keeps workspaces',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ProviderScope(child: MuzicianApp()));
      await _pumpUntil(tester, find.byType(IndexedStack));

      expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
      expect(find.byKey(const Key('studioBottomNavBar')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('nav_Roll')));
      await tester.pump(const Duration(milliseconds: 100));
      final stack = find.byType(IndexedStack).first;
      expect(tester.widget<IndexedStack>(stack).index, 2);
      final elementBefore = tester.element(stack);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('studioNavigationRail')), findsNothing);
      expect(find.byKey(const Key('studioBottomNavBar')), findsOneWidget);
      final stackAfter = find.byType(IndexedStack).first;
      expect(tester.widget<IndexedStack>(stackAfter).index, 2);
      expect(identical(tester.element(stackAfter), elementBefore), isTrue);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('studioNavigationRail')), findsOneWidget);
      expect(
        identical(
          tester.element(find.byType(IndexedStack).first),
          elementBefore,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
