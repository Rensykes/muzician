import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_playback_store.dart' show SongAudioClipSink;
import 'package:muzician/store/songwriter_audio_sink.dart';
import 'package:muzician/store/songwriter_playback_store.dart';
import 'package:muzician/store/songwriter_store.dart';

class _RecordingSink implements SongAudioClipSink {
  final started = <(String, bool)>[];
  final stopped = <String>[];
  @override
  Future<void> prepare(Iterable<AudioAsset> assets) async {}
  @override
  Future<void> startClip({
    required AudioAsset asset,
    required int offsetMs,
    double volume = 1.0,
    bool loop = false,
  }) async => started.add((asset.id, loop));
  @override
  Future<void> stopClip({required AudioAsset asset}) async =>
      stopped.add(asset.id);
  @override
  Future<void> stopAll() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('transport starts and stops a looped audio clip', (tester) async {
    final sink = _RecordingSink();
    final c = ProviderContainer(
      overrides: [songwriterAudioClipSinkProvider.overrideWithValue(sink)],
    );
    addTearDown(c.dispose);

    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 1);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    store.addAudioAsset(
      const AudioAsset(
        id: 'a1',
        durationMs: 800,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [1],
        sourceLabel: 'r',
      ),
    );
    final clipId = store.addAudioClip(assetId: 'a1', durationMs: 800);
    store.setClipFitMode(clipId: clipId, fitMode: AudioFitMode.loop);
    store.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 1,
    );

    await tester.runAsync(
      () => c
          .read(songwriterPlaybackProvider.notifier)
          .startPlayback(
            tickDurationOverride: const Duration(microseconds: 200),
          ),
    );
    await tester.pump();

    expect(sink.started.map((e) => e.$1), contains('a1'));
    expect(sink.started.firstWhere((e) => e.$1 == 'a1').$2, isTrue); // loop
    expect(sink.stopped, contains('a1'));
  });
}
