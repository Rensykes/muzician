import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_playback.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/models/song_project.dart';

void main() {
  test('initial state is idle', () {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('stopPlayback resets state to idle', () {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    notifier.stopPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.idle,
    );
  });

  test('startPlayback with no clips completes quickly', () async {
    final container = ProviderContainer(
      overrides: [
        songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
        songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(songPlaybackProvider.notifier);
    await notifier.startPlayback();
    expect(
      container.read(songPlaybackProvider).status,
      SongPlaybackStatus.completed,
    );
  });

  test('schedules audio clip starts/stops as the transport ticks', () async {
    final sink = _RecordingAudioSink();
    final container = ProviderContainer(overrides: [
      songNotePlaybackSinkProvider.overrideWith((_) => (notes, vol) async {}),
      songDrumPlaybackSinkProvider.overrideWith((_) => (lanes, vol) async {}),
      songAudioClipSinkProvider.overrideWithValue(sink),
    ]);
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

  @override
  Future<void> startClip(
      {required AudioAsset asset, required int offsetMs}) async {
    startCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    stopCalls.add(_AudioCall(asset.id));
  }

  @override
  Future<void> stopAll() async {}
}
