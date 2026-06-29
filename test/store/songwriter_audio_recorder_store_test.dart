import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart' show AudioAsset, DrumLaneId;
import 'package:muzician/schema/rules/songwriter_playback_rules.dart'
    show SongwriterAuditionBed;
import 'package:muzician/store/drum_pattern_playback_store.dart';
import 'package:muzician/store/song_audio_recorder_store.dart'
    show
        SongAudioRecorderDriver,
        SongAudioRecorderStatus,
        songAudioRecorderDriverProvider;
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/song_playback_store.dart' show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_recorder_store.dart';
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/utils/wav_writer.dart';

class _FakeDriver implements SongAudioRecorderDriver {
  bool started = false;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> start() async => started = true;
  @override
  Future<Uint8List> stop() async => writeWavPcm16Mono(
    Int16List.fromList(List<int>.filled(4410, 0)),
    sampleRate: 44100,
  );
  @override
  Future<void> dispose() async {}
}

class _FakeClipSink implements SongAudioClipSink {
  int startCount = 0;
  int stopAllCount = 0;
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async => startCount++;
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async => stopAllCount++;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sw_rec_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('record -> ready exposes a ~100ms asset', () async {
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
      ],
    );
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(countInMs: 0);
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.recording,
    );
    await n.stop();
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.ready,
    );

    final asset = n.consumePendingAsset();
    expect(asset, isNotNull);
    expect(asset!.durationMs, inInclusiveRange(90, 110));
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.idle,
    );
  });

  SongwriterRecordMonitor monitor({
    required bool backing,
    required bool metronome,
  }) => SongwriterRecordMonitor(
    backing: backing,
    metronome: metronome,
    tempo: 6000, // fast: many ticks per 200ms window
    beatTicks: 4,
    measureTicks: 16,
    loopTicks: 16,
    loopMs: 1000,
    bed: const (
      loopTicks: 16,
      notesByTick: {
        0: [60, 64, 67],
      },
      drumByTick: {
        0: [DrumLaneId.kick],
      },
    ),
    clips: const [],
  );

  test('monitor backing fires bed notes + drums while recording', () async {
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final clip = _FakeClipSink();
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
        songwriterAudioClipSinkProvider.overrideWithValue(clip),
        songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
        drumPatternPlaybackSinkProvider.overrideWithValue(
          (l, v) async => drums.add(l),
        ),
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: monitor(backing: true, metronome: false));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(notes, isNotEmpty);
    expect(notes.first, containsAll(<int>[60, 64, 67]));
    expect(drums, isNotEmpty);
    await n.cancel();
  });

  test('monitor metronome-only clicks without bed notes', () async {
    var clicks = 0;
    final notes = <List<int>>[];
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
        songwriterAudioClipSinkProvider.overrideWithValue(_FakeClipSink()),
        songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
        drumPatternPlaybackSinkProvider.overrideWithValue((l, v) async {}),
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async => clicks++,
        ),
      ],
    );
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: monitor(backing: false, metronome: true));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(clicks, greaterThan(0));
    expect(notes, isEmpty);
    await n.cancel();
  });

  test('stop tears the monitor down (clip stopAll, loop ends)', () async {
    final clip = _FakeClipSink();
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
        songwriterAudioClipSinkProvider.overrideWithValue(clip),
        songwriterNoteSinkProvider.overrideWithValue((_) {}),
        drumPatternPlaybackSinkProvider.overrideWithValue((l, v) async {}),
        songwriterMetronomeSinkProvider.overrideWithValue(
          ({required bool accent}) async {},
        ),
      ],
    );
    addTearDown(c.dispose);

    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start(monitor: monitor(backing: true, metronome: true));
    await n.stop();
    expect(clip.stopAllCount, greaterThanOrEqualTo(1));
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.ready,
    );
  });

  test('no monitor keeps current behaviour (no clip sink calls)', () async {
    final clip = _FakeClipSink();
    final c = ProviderContainer(
      overrides: [
        songAudioRecorderDriverProvider.overrideWithValue(_FakeDriver()),
        songwriterAudioRepositoryProvider.overrideWithValue(
          SongAudioRepository.testWith(
            rootDirectory: tmp,
            subdir: 'songwriter_audio',
          ),
        ),
        songwriterAudioClipSinkProvider.overrideWithValue(clip),
      ],
    );
    addTearDown(c.dispose);
    final n = c.read(songwriterAudioRecorderProvider.notifier);
    await n.start();
    expect(
      c.read(songwriterAudioRecorderProvider).status,
      SongAudioRecorderStatus.recording,
    );
    expect(clip.startCount, 0);
    await n.cancel();
  });
}
