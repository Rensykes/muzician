import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chip renders the project name', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setProjectName('Song A');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Song A'), findsOneWidget);
  });

  testWidgets('tap chip → dialog → submit → setProjectName fires',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('projectNameChip')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('projectNameField')), 'Song B');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(songwriterProvider).name, 'Song B');
  });

  testWidgets('whitespace-only name is rejected', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setProjectName('Song A');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('projectNameChip')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('projectNameField')), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(container.read(songwriterProvider).name, 'Song A');
  });
}
