import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';
import 'package:muzician/store/songwriter_store.dart';

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
}
