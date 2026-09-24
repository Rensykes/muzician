import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/theme/muzician_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('header does not overflow at a narrow phone width',
      (tester) async {
    // Force a narrow logical width (≈ small phone). A RenderFlex overflow in
    // the header Row would be reported as a FlutterError and fail this test.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // A wider key label ('A# major') exercises the tightest case.
    container.read(songwriterProvider.notifier).setKey(10, 'major');
    container.read(songwriterProvider.notifier).setTempo(120);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600)); // drain debounce
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Title was dropped; the key chip still renders (key set to A# major).
    expect(find.textContaining('major'), findsOneWidget);
  });

  testWidgets('Writer undo and redo are keyboard accessible', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(songwriterProvider.notifier);
    final initialTempo = container.read(songwriterProvider).config.tempo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
      ),
    );
    await tester.pumpAndSettle();

    Semantics semanticsFor(String label) => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .singleWhere((semantics) => semantics.properties.label == label);

    Future<void> openMenu() async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }

    Future<void> focusAction(String label) async {
      tester.binding.focusManager.primaryFocus?.unfocus();
      for (var attempt = 0; attempt < 20; attempt++) {
        if (semanticsFor(label).properties.focused == true) return;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(semanticsFor(label).properties.focused, isTrue);
    }

    void expectVisibleFocus(String label) {
      final tile = tester.widget<Container>(
        find.byKey(Key('writerMenuTile_${label.toLowerCase()}')),
      );
      final border = (tile.decoration! as BoxDecoration).border!;
      expect(border.top.color, MuzicianTheme.sky);
      expect(border.top.width, 1.5);
    }

    await openMenu();
    expect(semanticsFor('Undo').properties.button, isTrue);
    expect(semanticsFor('Undo').properties.enabled, isFalse);
    expect(semanticsFor('Redo').properties.button, isTrue);
    expect(semanticsFor('Redo').properties.enabled, isFalse);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    final editedTempo = initialTempo == 121 ? 122 : 121;
    notifier.setTempo(editedTempo);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(notifier.canUndo, isTrue);

    await openMenu();
    expect(semanticsFor('Undo').properties.enabled, isTrue);
    expect(semanticsFor('Redo').properties.enabled, isFalse);
    await focusAction('Undo');
    expect(semanticsFor('Undo').properties.focused, isTrue);
    expectVisibleFocus('Undo');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(songwriterProvider).config.tempo, initialTempo);
    expect(notifier.canRedo, isTrue);

    await openMenu();
    expect(semanticsFor('Redo').properties.enabled, isTrue);
    await focusAction('Redo');
    expect(semanticsFor('Redo').properties.focused, isTrue);
    expectVisibleFocus('Redo');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(container.read(songwriterProvider).config.tempo, editedTempo);

    await openMenu();
    await tester.tap(find.byKey(const Key('writerMenuTile_undo')));
    await tester.pumpAndSettle();
    expect(container.read(songwriterProvider).config.tempo, initialTempo);
  });
}
