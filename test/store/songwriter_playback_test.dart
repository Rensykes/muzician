import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('playback fires a metronome accent on each bar downbeat', () async {
    final accents = <bool>[];
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider.overrideWithValue(
        ({required bool accent}) async => accents.add(accent),
      ),
    ]);
    addTearDown(container.dispose);

    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 1);
    sw.addSection(label: 'B', lengthBars: 1);

    final transport = container.read(songwriterPlaybackProvider.notifier);
    await transport.startPlayback(tickDurationOverride: Duration.zero);

    expect(accents.length, greaterThanOrEqualTo(2));
    expect(accents.where((a) => a).length, 2);
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.completed);
  });

  test('stopPlayback halts the clock', () async {
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider
          .overrideWithValue(({required bool accent}) async {}),
    ]);
    addTearDown(container.dispose);
    final sw = container.read(songwriterProvider.notifier);
    sw.addSection(label: 'A', lengthBars: 4);
    final transport = container.read(songwriterPlaybackProvider.notifier);
    transport.stopPlayback();
    expect(container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.idle);
  });
}
