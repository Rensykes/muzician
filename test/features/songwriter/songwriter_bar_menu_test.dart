import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';

void main() {
  testWidgets('showBarActionSheet renders items and invokes the tapped action',
      (tester) async {
    var tapped = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('open'),
              child: const SizedBox(),
              onPressed: () => showBarActionSheet(
                context: context,
                title: 'Bar',
                actions: [
                  BarAction(
                    key: const Key('act_a'),
                    label: 'Action A',
                    icon: Icons.edit,
                    onTap: () => tapped = 'a',
                  ),
                  BarAction(
                    key: const Key('act_del'),
                    label: 'Remove',
                    icon: Icons.delete,
                    destructive: true,
                    onTap: () => tapped = 'del',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('Action A'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.byKey(const Key('act_del')));
    await tester.pumpAndSettle();
    expect(tapped, 'del');
    expect(find.text('Action A'), findsNothing);
  });
}
