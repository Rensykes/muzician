import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_audio_picker_sheet.dart';

void main() {
  testWidgets('shows Record audio and Import audio entries', (tester) async {
    var recordTapped = false;
    var importTapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongAudioPickerSheet(
              trackId: 't1',
              startTick: 0,
              recordSupported: true,
              onRecord: () => recordTapped = true,
              onImport: () => importTapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Record audio'), findsOneWidget);
    expect(find.text('Import audio file'), findsOneWidget);

    await tester.tap(find.text('Record audio'));
    await tester.tap(find.text('Import audio file'));
    expect(recordTapped, isTrue);
    expect(importTapped, isTrue);
  });

  testWidgets('hides Record entry when not supported (web)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongAudioPickerSheet(
              trackId: 't1',
              startTick: 0,
              recordSupported: false,
              onRecord: () {},
              onImport: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Record audio'), findsNothing);
    expect(find.text('Import audio file'), findsOneWidget);
  });
}
