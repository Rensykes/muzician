import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_save_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('save panel captures the current songwriter project',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'V', lengthBars: 8);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
    ));
    await tester.pump(const Duration(milliseconds: 600)); // drain debounce
    await tester.pumpAndSettle();

    final snap = songwriterCaptureForTest(container);
    expect(snap.instrument, 'songwriter');
    expect(snap.sections.single.label, 'V');
  });
}
