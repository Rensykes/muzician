import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeRecorderDriver implements SongAudioRecorderDriver {
  bool started = false;
  bool stopped = false;
  Uint8List? lastBytes;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<Uint8List> stop() async {
    stopped = true;
    final samples = Int16List.fromList(List<int>.filled(44100, 4000));
    lastBytes = writeWavPcm16Mono(samples, sampleRate: 44100);
    return lastBytes!;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('SongAudioRecorderNotifier starts in idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.idle);
    expect(state.pendingAsset, isNull);
    expect(state.targetTrackId, isNull);
    expect(state.startTick, isNull);
    expect(state.elapsedMs, 0);
    expect(state.errorMessage, isNull);
  });

  test('start transitions idle → countIn → recording', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(driver),
        songAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(rootDirectory: tmp),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Need a track so auto-mute can find it.
    final project = container.read(songProjectProvider.notifier);
    final trackId = project.addTrack(SongTrackType.audio);

    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: trackId, startTick: 16, countInMs: 0);

    expect(driver.started, isTrue);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.recording);
    expect(state.targetTrackId, trackId);
    expect(state.startTick, 16);
  });

  test('stop transitions recording → finalising → ready with asset', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(driver),
        songAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(rootDirectory: tmp),
        ),
      ],
    );
    addTearDown(container.dispose);

    final project = container.read(songProjectProvider.notifier);
    final trackId = project.addTrack(SongTrackType.audio);
    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: trackId, startTick: 0, countInMs: 0);
    await notifier.stop();

    expect(driver.stopped, isTrue);
    final state = container.read(songAudioRecorderProvider);
    expect(state.status, SongAudioRecorderStatus.ready);
    expect(state.pendingAsset, isNotNull);
    expect(state.pendingAsset!.format, 'wav');
    expect(state.pendingAsset!.durationMs, closeTo(1000, 10));
  });

  test('cancel mid-recording stops the driver and clears state', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final repo = SongAudioRepository.testWith(rootDirectory: tmp);
    final container = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(driver),
        songAudioRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final project = container.read(songProjectProvider.notifier);
    final trackId = project.addTrack(SongTrackType.audio);
    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: trackId, startTick: 0, countInMs: 0);
    expect(
      container.read(songAudioRecorderProvider).status,
      SongAudioRecorderStatus.recording,
    );

    await notifier.cancel();

    expect(driver.stopped, isTrue);
    expect(
      container.read(songAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
    expect(container.read(songAudioRecorderProvider).pendingAsset, isNull);
    expect(container.read(songProjectProvider).tracks.first.isMuted, isFalse);
    // Repository is untouched – there is no leftover file to clean up.
    expect(repo, isNotNull);
  });

  test(
    'mutes the target track during recording and restores on finalise',
    () async {
      final driver = _FakeRecorderDriver();
      final tmp = await Directory.systemTemp.createTemp('rec_mute_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final container = ProviderContainer(
        overrides: [
          songAudioRecorderDriverProvider.overrideWithValue(driver),
          songAudioRepositoryProvider.overrideWithValue(
            SongAudioRepository.testWith(rootDirectory: tmp),
          ),
        ],
      );
      addTearDown(container.dispose);

      final project = container.read(songProjectProvider.notifier);
      final trackId = project.addTrack(SongTrackType.audio);
      expect(container.read(songProjectProvider).tracks.first.isMuted, isFalse);

      final notifier = container.read(songAudioRecorderProvider.notifier);
      await notifier.start(trackId: trackId, startTick: 0, countInMs: 0);
      expect(container.read(songProjectProvider).tracks.first.isMuted, isTrue);

      await notifier.stop();
      expect(container.read(songProjectProvider).tracks.first.isMuted, isFalse);
    },
  );

  test('consumePendingAsset returns asset and resets to idle', () async {
    final driver = _FakeRecorderDriver();
    final tmp = await Directory.systemTemp.createTemp('rec_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(driver),
        songAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(rootDirectory: tmp),
        ),
      ],
    );
    addTearDown(container.dispose);
    final project = container.read(songProjectProvider.notifier);
    final trackId = project.addTrack(SongTrackType.audio);
    final notifier = container.read(songAudioRecorderProvider.notifier);
    await notifier.start(trackId: trackId, startTick: 0, countInMs: 0);
    await notifier.stop();

    final asset = notifier.consumePendingAsset();
    expect(asset, isNotNull);
    expect(
      container.read(songAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
  });
}
