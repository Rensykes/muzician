import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
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
}
