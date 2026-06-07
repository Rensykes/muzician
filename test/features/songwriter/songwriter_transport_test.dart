import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('play button starts the transport', (tester) async {
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(
          label: 'A',
          lengthBars: 1,
        );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('songwriterPlay')));
    await tester.pump();
    expect(
      container.read(songwriterPlaybackProvider).status,
      isNot(SongwriterPlaybackStatus.idle),
    );
    container.read(songwriterPlaybackProvider.notifier).stopPlayback();
    await tester.pump(const Duration(milliseconds: 600));
  });
}
