import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_playback.dart';
import 'package:muzician/schema/rules/song_rules.dart' as song_rules;
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/models/song_project.dart';

ProviderContainer _container({SongAudioClipSink? audioSink}) {
  final container = ProviderContainer(
    overrides: [
      songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
      songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      if (audioSink != null)
        songAudioClipSinkProvider.overrideWithValue(audioSink),
    ],
  );
  return container;
}

void main() {
  test('initial state is idle', () {
    final container = _container();
    addTearDown(container.dispose);
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('stopPlayback resets state to idle', () {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    notifier.stopPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('startPlayback with no clips completes quickly', () async {
    final container = _container();
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    await notifier.startPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.completed,
    );
  });

  group('seek', () {
    test('parks the cursor at the given tick while idle', () {
      final container = _container();
      addTearDown(container.dispose);
      // Ensure the project is long enough that tick 8 is in range.
      container.read(songProjectProvider.notifier).setTotalMeasures(4);
      container.read(songPlaybackProvider.notifier).seek(8);
      final state = container.read(songPlaybackProvider);
      expect(state.status, SongPlaybackStatus.idle);
      expect(state.currentTick, 8);
    });

    test('clamps negative ticks to zero', () {
      final container = _container();
      addTearDown(container.dispose);
      container.read(songPlaybackProvider.notifier).seek(-5);
      expect(container.read(songPlaybackProvider).currentTick, 0);
    });

    test('clamps beyond the end of the project', () {
      final container = _container();
      addTearDown(container.dispose);
      final config = container.read(songProjectProvider).config;
      final maxTick = song_rules.songTotalTicks(config) - 1;
      container.read(songPlaybackProvider.notifier).seek(999999);
      expect(container.read(songPlaybackProvider).currentTick, maxTick);
    });
  });

  test('schedules audio clip starts/stops as the transport ticks', () async {
    final sink = _RecordingAudioSink();
    final container = _container(audioSink: sink);
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    project.setTempo(240); // 240 BPM keeps the loop fast
    final trackId = project.addTrack(SongTrackType.audio);
    project.addAudioClip(
      trackId: trackId,
      startTick: 0,
      asset: const AudioAsset(
        id: 'a-fast',
        durationMs: 60,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: '',
      ),
    );

    await container.read(songPlaybackProvider.notifier).startPlayback();

    expect(sink.startCalls, isNotEmpty);
    expect(sink.stopCalls, isNotEmpty);
    expect(sink.startCalls.first.assetId, 'a-fast');
  });
}

class _AudioCall {
  final String assetId;
  const _AudioCall(this.assetId);
}

class _RecordingAudioSink implements SongAudioClipSink {
  final List<_AudioCall> startCalls = [];
  final List<_AudioCall> stopCalls = [];
  final List<String> preparedAssetIds = [];

  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {
    preparedAssetIds.addAll(assets.map((a) => a.id));
  }

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
  }) async {
    startCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    stopCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopAll() async {}
}
