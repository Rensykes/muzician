import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart' show AudioAsset;
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/song_audio_repository.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  // NOTE: replace `notifier()` body's cast type if the notifier class differs.
  dynamic store() => c.read(songwriterProvider.notifier);

  String seedSectionWithAudioLane() {
    store().addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store().addLane(
      sectionId: sectionId,
      kind: SongLaneKind.audio,
      label: 'Sample',
    );
    return sectionId;
  }

  test('addAudioClip appends a clip and returns its id', () {
    seedSectionWithAudioLane();
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.id, clipId);
    expect(clip.assetId, 'a1');
    expect(clip.trimEndMs, 4000);
    expect(clip.fitMode, AudioFitMode.loop);
  });

  test('addAudioBlock places a block on the audio lane', () {
    final sectionId = seedSectionWithAudioLane();
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );
    final block = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .blocks
        .single;
    expect(block.audioClipId, clipId);
    expect(block.spanBars, 2);
  });

  test('setClipFitMode and setClipTrim mutate the clip', () {
    seedSectionWithAudioLane();
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().setClipFitMode(clipId: clipId, fitMode: AudioFitMode.oneShot);
    store().setClipTrim(clipId: clipId, trimStartMs: 250, trimEndMs: 3500);
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.fitMode, AudioFitMode.oneShot);
    expect(clip.trimStartMs, 250);
    expect(clip.trimEndMs, 3500);
  });

  test('removeAudioBlock drops the block and its clip', () {
    final sectionId = seedSectionWithAudioLane();
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);
    store().addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );
    final blockId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .blocks
        .single
        .id;

    store().removeAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
    );

    final lane = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio);
    expect(lane.blocks, isEmpty);
    expect(c.read(songwriterProvider).audioClips, isEmpty);
  });

  test(
    'removeAudioBlock reclaims the asset when no other clip references it',
    () async {
      final tmp = await Directory.systemTemp.createTemp('sw_audio_gc_test_');
      addTearDown(() => tmp.delete(recursive: true));

      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final container = ProviderContainer(
        overrides: [songwriterAudioRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // Seed section + audio lane.
      container
          .read(songwriterProvider.notifier)
          .addSection(label: 'A', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      container
          .read(songwriterProvider.notifier)
          .addLane(
            sectionId: sectionId,
            kind: SongLaneKind.audio,
            label: 'Sample',
          );
      final laneId = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.audio)
          .id;

      // Seed a real AudioAsset via addAudioAsset so there is something to GC.
      const asset = AudioAsset(
        id: 'asset-gc-1',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'test',
      );
      container.read(songwriterProvider.notifier).addAudioAsset(asset);
      final clipId = container
          .read(songwriterProvider.notifier)
          .addAudioClip(assetId: asset.id, durationMs: asset.durationMs);
      container
          .read(songwriterProvider.notifier)
          .addAudioBlock(
            sectionId: sectionId,
            laneId: laneId,
            audioClipId: clipId,
            startBar: 0,
            spanBars: 2,
          );
      final blockId = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.audio)
          .blocks
          .single
          .id;

      // Precondition: asset is present.
      expect(container.read(songwriterProvider).audioAssets, hasLength(1));

      container
          .read(songwriterProvider.notifier)
          .removeAudioBlock(
            sectionId: sectionId,
            laneId: laneId,
            blockId: blockId,
          );

      // Asset must have been removed from state.
      expect(container.read(songwriterProvider).audioAssets, isEmpty);
      // Clip must also be gone.
      expect(container.read(songwriterProvider).audioClips, isEmpty);
    },
  );
}
