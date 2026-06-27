import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_playback_store.dart' show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_audition_store.dart';
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/drum_pattern_playback_store.dart';

class _FakeSink implements SongAudioClipSink {
  int startCount = 0;
  int stopAllCount = 0;
  bool? lastLoop;
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async {
    startCount++;
    lastLoop = loop;
  }
  @override
  Future<void> stopClip({required AudioAsset asset}) async {}
  @override
  Future<void> stopAll() async {
    stopAllCount++;
  }
}

void main() {
  // AudioAsset fields: id, durationMs, sampleRate, channels, format, peaks,
  // sourceLabel (no 'path' field — verified against lib/models/song_project.dart).
  const asset = AudioAsset(
    id: 'a1',
    sourceLabel: 'take',
    format: 'wav',
    durationMs: 2000,
    sampleRate: 44100,
    channels: 1,
    peaks: [],
  );

  test('alone mode starts the looping clip and fires no bed events', () async {
    final sink = _FakeSink();
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
      songwriterNoteSinkProvider.overrideWithValue((n) => notes.add(n)),
      drumPatternPlaybackSinkProvider
          .overrideWithValue((l, v) async => drums.add(l)),
    ]);
    addTearDown(container.dispose);

    final n = container.read(songwriterAudioAuditionProvider.notifier);
    await n.start(
      asset: asset,
      trimStartMs: 100,
      tempo: 120,
      mode: SongwriterAudioAuditionMode.alone,
    );

    expect(sink.startCount, 1);
    expect(sink.lastLoop, isTrue);
    expect(notes, isEmpty);
    expect(drums, isEmpty);

    n.stop();
    expect(sink.stopAllCount, 1);
    expect(
      container.read(songwriterAudioAuditionProvider).status,
      SongwriterAudioAuditionStatus.idle,
    );
  });

  test('with-section is a no-op when the bed is empty', () async {
    final sink = _FakeSink();
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(container.dispose);
    final n = container.read(songwriterAudioAuditionProvider.notifier);
    await n.start(
      asset: asset,
      trimStartMs: 0,
      tempo: 120,
      mode: SongwriterAudioAuditionMode.withSection,
      bed: (loopTicks: 0, notesByTick: const {}, drumByTick: const {}),
    );
    expect(sink.startCount, 0);
    expect(
      container.read(songwriterAudioAuditionProvider).status,
      SongwriterAudioAuditionStatus.idle,
    );
  });

  test('with-section fires bed note + drum events under the recording',
      () async {
    final sink = _FakeSink();
    final notes = <List<int>>[];
    final drums = <List<DrumLaneId>>[];
    final container = ProviderContainer(overrides: [
      songwriterAudioClipSinkProvider.overrideWithValue(sink),
      songwriterNoteSinkProvider.overrideWithValue((nn) => notes.add(nn)),
      drumPatternPlaybackSinkProvider
          .overrideWithValue((l, v) async => drums.add(l)),
    ]);
    addTearDown(container.dispose);

    final n = container.read(songwriterAudioAuditionProvider.notifier);
    unawaited(n.start(
      asset: asset,
      trimStartMs: 0,
      tempo: 6000, // Fast tempo so many ticks fire within the 200ms window.
      mode: SongwriterAudioAuditionMode.withSection,
      bed: (
        loopTicks: 16,
        notesByTick: const {
          0: [60, 64, 67],
        },
        drumByTick: const {
          0: [DrumLaneId.kick],
        },
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    n.stop();

    expect(sink.startCount, 1);
    expect(sink.lastLoop, isTrue);
    expect(notes, isNotEmpty);
    expect(notes.first, containsAll(<int>[60, 64, 67]));
    expect(drums, isNotEmpty);
    expect(drums.first, contains(DrumLaneId.kick));
  });
}
