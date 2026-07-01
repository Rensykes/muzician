import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/features/songwriter/songwriter_audio_recorder_sheet.dart';

void main() {
  testWidgets('shows the three monitor toggles, all OFF by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioRecorderSheet(
              monitorTemplate: null,
              countInBarMs: 2000,
              countInBeats: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('sw-rec-toggle-backing')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sw-rec-toggle-metronome')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sw-rec-toggle-countin')), findsOneWidget);
    for (final w in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(w.value, isFalse);
    }
  });
}
