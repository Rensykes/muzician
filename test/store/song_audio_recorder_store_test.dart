import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_audio_recorder_store.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_playback_store.dart';
import 'package:muzician/store/song_project_store.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeRecorderDriver implements SongAudioRecorderDriver {
  bool started = false;
  bool stopped = false;
  Uint8List? lastBytes;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> start({bool manageIosAudioSession = true}) async {
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

class _DeferredStopRecorderDriver extends _FakeRecorderDriver {
  final stopCompleter = Completer<Uint8List>();

  @override
  Future<Uint8List> stop() {
    stopped = true;
    return stopCompleter.future;
  }
}

class _FakeClipSink extends NoopSongAudioClipSink {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1,
    double balance = 0,
    bool loop = false,
  }) async {
    starts++;
  }

  @override
  Future<void> stopClip({required AudioAsset asset}) async {
    stops++;
  }
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

  test(
    're-record deletes the prior take and keeps the same destination',
    () async {
      final driver = _FakeRecorderDriver();
      final tmp = await Directory.systemTemp.createTemp('rec_rerecord_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final container = ProviderContainer(
        overrides: [
          songAudioRecorderDriverProvider.overrideWithValue(driver),
          songAudioRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final trackId = container
          .read(songProjectProvider.notifier)
          .addTrack(SongTrackType.audio);
      final notifier = container.read(songAudioRecorderProvider.notifier);

      await notifier.start(trackId: trackId, startTick: 12);
      await notifier.stop();
      final firstTake = container.read(songAudioRecorderProvider).pendingAsset!;
      final firstFile = await repo.resolvePath(firstTake.id, firstTake.format);
      expect(firstFile.existsSync(), isTrue);

      await notifier.rerecord();
      expect(firstFile.existsSync(), isFalse);
      expect(
        container.read(songAudioRecorderProvider).status,
        SongAudioRecorderStatus.recording,
      );
      expect(container.read(songAudioRecorderProvider).targetTrackId, trackId);
      expect(container.read(songAudioRecorderProvider).startTick, 12);

      await notifier.stop();
      final secondTake = container
          .read(songAudioRecorderProvider)
          .pendingAsset!;
      expect(secondTake.id, isNot(firstTake.id));
      expect(
        (await repo.resolvePath(secondTake.id, secondTake.format)).existsSync(),
        isTrue,
      );
      await notifier.cancel();
      expect(
        (await repo.resolvePath(secondTake.id, secondTake.format)).existsSync(),
        isFalse,
      );
      expect(container.read(songProjectProvider).clips, isEmpty);
    },
  );

  test(
    'cancel during finalising removes a file produced after cancellation',
    () async {
      final driver = _DeferredStopRecorderDriver();
      final tmp = await Directory.systemTemp.createTemp(
        'rec_finalising_cancel_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final container = ProviderContainer(
        overrides: [
          songAudioRecorderDriverProvider.overrideWithValue(driver),
          songAudioRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final trackId = container
          .read(songProjectProvider.notifier)
          .addTrack(SongTrackType.audio);
      final notifier = container.read(songAudioRecorderProvider.notifier);
      await notifier.start(trackId: trackId, startTick: 0);

      final finalising = notifier.stop();
      expect(
        container.read(songAudioRecorderProvider).status,
        SongAudioRecorderStatus.finalising,
      );
      await notifier.cancel();
      driver.stopCompleter.complete(
        writeWavPcm16Mono(Int16List(4410), sampleRate: 44100),
      );
      await finalising;

      expect(
        container.read(songAudioRecorderProvider).status,
        SongAudioRecorderStatus.idle,
      );
      final directory = Directory('${tmp.path}/song_audio');
      expect(directory.existsSync(), isTrue);
      expect(directory.listSync(), isEmpty);
      expect(container.read(songProjectProvider).clips, isEmpty);
    },
  );

  test(
    'pending take can be auditioned and stopped before acceptance',
    () async {
      final driver = _FakeRecorderDriver();
      final sink = _FakeClipSink();
      final tmp = await Directory.systemTemp.createTemp('rec_preview_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final container = ProviderContainer(
        overrides: [
          songAudioRecorderDriverProvider.overrideWithValue(driver),
          songAudioClipSinkProvider.overrideWithValue(sink),
          songAudioRepositoryProvider.overrideWithValue(
            SongAudioRepository.testWith(rootDirectory: tmp),
          ),
        ],
      );
      addTearDown(container.dispose);
      final trackId = container
          .read(songProjectProvider.notifier)
          .addTrack(SongTrackType.audio);
      final notifier = container.read(songAudioRecorderProvider.notifier);
      await notifier.start(trackId: trackId, startTick: 0);
      await notifier.stop();

      await notifier.previewPendingTake();
      expect(sink.starts, 1);
      expect(container.read(songAudioRecorderProvider).isPreviewing, isTrue);
      await notifier.stopPreview();
      expect(sink.stops, greaterThanOrEqualTo(1));
      expect(container.read(songAudioRecorderProvider).pendingAsset, isNotNull);
      await notifier.cancel();
    },
  );
}
