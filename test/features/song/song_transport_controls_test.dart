import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/song/song_screen.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() => ProviderContainer(
  overrides: [
    songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
    songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
    songMetronomeSinkProvider.overrideWith(
      (_) => ({required bool accent}) async {},
    ),
  ],
);

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SongScreen()),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tempo multiplier chip cycles the playback multiplier',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    final chip = find.byKey(const Key('tempoMultiplierChip'));
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 0.75);

    await tester.tap(chip);
    await tester.pump();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 0.5);

    await tester.tap(chip);
    await tester.pump();
    expect(container.read(songPlaybackProvider).tempoMultiplier, 1.0);
  });

  testWidgets('metronome toggle flips the settings flag', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    final before = container.read(settingsProvider).metronomeEnabled;
    await tester.tap(find.byKey(const Key('songMetronomeToggle')));
    await tester.pump();
    expect(container.read(settingsProvider).metronomeEnabled, !before);
  });

  testWidgets('count-in toggle flips playback state', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.byKey(const Key('countInToggle')));
    await tester.pump();
    expect(container.read(songPlaybackProvider).countInEnabled, isTrue);
  });

  testWidgets('loop chip appears when a region is set and clears on tap',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.byKey(const Key('loopChip')), findsNothing);

    container.read(songPlaybackProvider.notifier).setLoopRegion(0, 16);
    await tester.pump();
    expect(find.byKey(const Key('loopChip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('loopChip')));
    await tester.pump();
    expect(container.read(songPlaybackProvider).hasLoop, isFalse);
    expect(find.byKey(const Key('loopChip')), findsNothing);
  });
}
