import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/songwriter_stretch_controller.dart';
import 'package:muzician/utils/wav_writer.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('stretch_ctl_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('rerender stamps a stretchedAssetId sized to the span', () async {
    final repo = SongAudioRepository.testWith(
      rootDirectory: tmp,
      subdir: 'songwriter_audio',
    );
    final c = ProviderContainer(
      overrides: [songwriterAudioRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);

    final wav = writeWavPcm16Mono(
      Int16List.fromList(List<int>.filled(44100, 1000)),
      sampleRate: 44100,
    );
    final src = await repo.writeRecording(wav); // 1s source

    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    store.addAudioAsset(src);
    final clipId = store.addAudioClip(
      assetId: src.id,
      durationMs: src.durationMs,
    );
    store.setClipFitMode(clipId: clipId, fitMode: AudioFitMode.stretch);
    store.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );

    await c.read(songwriterStretchControllerProvider).rerender(clipId);

    final clip = c
        .read(songwriterProvider)
        .audioClips
        .firstWhere((x) => x.id == clipId);
    expect(clip.stretchedAssetId, isNotNull);
    final stretched = c
        .read(songwriterProvider)
        .audioAssets
        .firstWhere((a) => a.id == clip.stretchedAssetId);
    expect(
      stretched.durationMs,
      inInclusiveRange(3900, 4100),
    ); // 2 bars @120bpm
    expect(
      c.read(songwriterStretchProcessingProvider).contains(clipId),
      isFalse,
    );
  });
}
