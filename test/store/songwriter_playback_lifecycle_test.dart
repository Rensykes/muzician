import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/harmony_lane_instrument.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer containerFor(_PreparingSink sink) {
    final container = ProviderContainer(
      overrides: [
        songwriterAudioClipSinkProvider.overrideWithValue(sink),
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required accent}) async {},
        ),
      ],
    );
    container
        .read(songwriterProvider.notifier)
        .addSection(label: 'A', lengthBars: 1);
    return container;
  }

  test(
    'Play during preparation is idempotent and Stop prevents a late start',
    () async {
      final sink = _PreparingSink();
      final container = containerFor(sink);
      addTearDown(container.dispose);
      final transport = container.read(songwriterPlaybackProvider.notifier);
      final first = transport.startPlayback(
        tickDurationOverride: Duration.zero,
      );
      expect(
        container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.playing,
      );
      await transport.startPlayback(tickDurationOverride: Duration.zero);
      expect(sink.prepareCalls, 1);
      transport.stopPlayback();
      sink.prepared.complete();
      await first;
      expect(
        container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.idle,
      );
    },
  );

  test(
    'failed preparation releases ownership and leaves transport idle',
    () async {
      final sink = _PreparingSink();
      final container = containerFor(sink);
      addTearDown(container.dispose);
      final playback = container
          .read(songwriterPlaybackProvider.notifier)
          .startPlayback();
      final stopsBeforeFailure = sink.stopCalls;
      final assertion = expectLater(playback, throwsStateError);
      sink.prepared.completeError(StateError('prepare failed'));
      await assertion;
      expect(
        container.read(songwriterPlaybackProvider).status,
        SongwriterPlaybackStatus.idle,
      );
      expect(sink.stopCalls, stopsBeforeFailure + 1);
    },
  );

  test('dispose invalidates an in-flight preparation', () async {
    final sink = _PreparingSink();
    final container = containerFor(sink);
    final playback = container
        .read(songwriterPlaybackProvider.notifier)
        .startPlayback();
    final stopsBeforeDispose = sink.stopCalls;
    container.dispose();
    sink.prepared.complete();
    await playback;
    expect(sink.stopCalls, stopsBeforeDispose + 1);
  });

  test(
    'Fretboard Harmony uses guitar sink and never rings past a short bar',
    () async {
      final guitar = <Duration>[];
      final piano = <Duration>[];
      final container = ProviderContainer(
        overrides: [
          songwriterGuitarNoteSinkProvider.overrideWithValue(
            (notes, volume, pan, {duration}) => guitar.add(duration!),
          ),
          songwriterNoteSinkProvider.overrideWithValue(
            (notes, volume, pan, {duration}) => piano.add(duration!),
          ),
          songwriterMetronomeSinkProvider.overrideWithValue(
            ({required accent}) async {},
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(songwriterProvider.notifier)
          .loadProject(
            const SongwriterProjectSnapshot(
              config: SongwriterConfig(tempo: 300, beatsPerBar: 1, beatUnit: 4),
              sections: [
                SongSection(
                  id: 'section',
                  lengthBars: 2,
                  order: 0,
                  lanes: [
                    SongLane(
                      id: 'harmony',
                      kind: SongLaneKind.harmony,
                      order: 0,
                      harmonyInstrument: HarmonyLaneInstrument.fretboard,
                      blocks: [
                        SongBlock(
                          id: 'chord',
                          startBar: 0,
                          spanBars: 2,
                          chordRootPc: 0,
                          chordQuality: '',
                          chordNotes: ['C', 'E', 'G'],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
      await container
          .read(songwriterPlaybackProvider.notifier)
          .startPlayback(tickDurationOverride: const Duration(milliseconds: 1));
      expect(piano, isEmpty);
      expect(guitar, [
        const Duration(milliseconds: 4),
        const Duration(milliseconds: 4),
      ]);
      expect(container.read(songwriterPlaybackProvider).currentTick, 8);
    },
  );
}

class _PreparingSink implements SongAudioClipSink {
  final prepared = Completer<void>();
  var prepareCalls = 0;
  var stopCalls = 0;
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) {
    prepareCalls++;
    return prepared.future;
  }

  @override
  Future<void> stopAll() async {
    stopCalls++;
  }

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1,
    double balance = 0,
    bool loop = false,
  }) async {}
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
}
