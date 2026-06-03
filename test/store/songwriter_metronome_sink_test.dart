import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/store/songwriter_playback_store.dart';

void main() {
  test('metronome sink provider is overridable for tests', () {
    final hits = <bool>[];
    final container = ProviderContainer(overrides: [
      songwriterMetronomeSinkProvider.overrideWithValue(
        ({required bool accent}) async => hits.add(accent),
      ),
    ]);
    addTearDown(container.dispose);
    final sink = container.read(songwriterMetronomeSinkProvider);
    sink(accent: true);
    sink(accent: false);
    expect(hits, [true, false]);
  });
}
