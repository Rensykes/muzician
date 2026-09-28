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

  test('clip chord segments stay separate from Writer Harmony blocks', () {
    seedSectionWithAudioLane();
    final clipId = store().addAudioClip(assetId: 'a1', durationMs: 4000);

    final segmentId = store().addChordSegment(
      clipId: clipId,
      startTick: 0,
      spanTicks: 16,
      chordSymbol: 'C',
      chordQuality: '',
      chordRootPc: 0,
      chordNotes: const ['C', 'E', 'G'],
    );

    final project = c.read(songwriterProvider);
    final harmonyLane = project.sections.single.lanes.singleWhere(
      (lane) => lane.kind == SongLaneKind.harmony,
    );
    expect(project.audioClips.single.segments.single.id, segmentId);
    expect(project.audioClips.single.segments.single.chordSymbol, 'C');
    expect(harmonyLane.blocks, isEmpty);
    expect(
      project.sections.single.lanes.where(
        (lane) => lane.kind == SongLaneKind.save,
      ),
      isEmpty,
    );
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

  test('stretch rerender keeps assets reachable through Writer history', () {
    seedSectionWithAudioLane();
    final n = store();
    const source = AudioAsset(
      id: 'source',
      durationMs: 2000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [],
      sourceLabel: 'Source',
    );
    const previousStretch = AudioAsset(
      id: 'previous-stretch',
      durationMs: 3000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [],
      sourceLabel: 'Previous stretch',
    );
    const nextStretch = AudioAsset(
      id: 'next-stretch',
      durationMs: 4000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [],
      sourceLabel: 'Next stretch',
    );
    n.addAudioAsset(source);
    final clipId = n.addAudioClip(assetId: source.id, durationMs: 2000);
    n.setClipStretchedAsset(clipId: clipId, stretchedAsset: previousStretch);
    n.setTempo(132); // Undo retains the pre-rerender clip and its asset.

    n.setClipStretchedAsset(
      clipId: clipId,
      stretchedAsset: nextStretch,
      removeAssetId: previousStretch.id,
    );

    final current = c.read(songwriterProvider);
    expect(current.audioClips.single.stretchedAssetId, nextStretch.id);
    expect(
      current.audioAssets.map((asset) => asset.id),
      contains(previousStretch.id),
    );
    expect(n.undo(), isTrue);
    expect(
      c.read(songwriterProvider).audioClips.single.stretchedAssetId,
      previousStretch.id,
    );
    expect(
      c.read(songwriterProvider).audioAssets.map((asset) => asset.id),
      contains(previousStretch.id),
    );
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
    'removeAudioBlock retains referenced assets while undo can restore them',
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

      // The undo snapshot still contains the clip and source asset.
      expect(
        container.read(songwriterProvider).audioAssets.map((asset) => asset.id),
        contains(asset.id),
      );
      expect(container.read(songwriterProvider).audioClips, isEmpty);
      expect(container.read(songwriterProvider.notifier).undo(), isTrue);
      expect(container.read(songwriterProvider).audioClips, hasLength(1));
      expect(
        container.read(songwriterProvider).audioAssets.map((asset) => asset.id),
        contains(asset.id),
      );
    },
  );

  test(
    'removeAudioBlock retains stretch assets needed by undo history',
    () async {
      final tmp = await Directory.systemTemp.createTemp('sw_stretch_gc_');
      addTearDown(() => tmp.delete(recursive: true));
      final repo = SongAudioRepository.testWith(rootDirectory: tmp);
      final container = ProviderContainer(
        overrides: [songwriterAudioRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final n = container.read(songwriterProvider.notifier);
      n.addSection(label: 'A', lengthBars: 4);
      final sectionId = container.read(songwriterProvider).sections.single.id;
      n.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
      final laneId = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.audio)
          .id;
      const src = AudioAsset(
        id: 'src1',
        durationMs: 1000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'src',
      );
      n.addAudioAsset(src);
      final clipId = n.addAudioClip(
        assetId: src.id,
        durationMs: src.durationMs,
      );
      n.addAudioBlock(
        sectionId: sectionId,
        laneId: laneId,
        audioClipId: clipId,
        startBar: 0,
        spanBars: 2,
      );
      const stretched = AudioAsset(
        id: 'src1s',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [],
        sourceLabel: 'Stretched',
      );
      n.setClipStretchedAsset(clipId: clipId, stretchedAsset: stretched);
      expect(container.read(songwriterProvider).audioAssets, hasLength(2));

      final blockId = container
          .read(songwriterProvider)
          .sections
          .single
          .lanes
          .firstWhere((l) => l.kind == SongLaneKind.audio)
          .blocks
          .single
          .id;
      n.removeAudioBlock(
        sectionId: sectionId,
        laneId: laneId,
        blockId: blockId,
      );

      // Both assets remain reachable through the retained pre-removal snapshot.
      expect(
        container.read(songwriterProvider).audioAssets.map((asset) => asset.id),
        containsAll([src.id, stretched.id]),
      );
      expect(container.read(songwriterProvider).audioClips, isEmpty);
      expect(n.undo(), isTrue);
      expect(container.read(songwriterProvider).audioClips, hasLength(1));
      expect(
        container.read(songwriterProvider).audioAssets.map((asset) => asset.id),
        containsAll([src.id, stretched.id]),
      );
    },
  );
}
