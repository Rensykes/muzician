import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_slice_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

/// Ids returned by [seedAudioSourceBlock].
class _SeededAudio {
  const _SeededAudio({
    required this.sectionId,
    required this.laneId,
    required this.assetId,
    required this.clipId,
    required this.blockId,
  });
  final String sectionId;
  final String laneId;
  final String assetId;
  final String clipId;
  final String blockId;
}

/// Seeds a section with one audio lane carrying a single 1-bar source
/// clip+block at [startBar], using the real store API. Mirrors the seeding in
/// `test/store/songwriter_audio_playback_test.dart`.
_SeededAudio seedAudioSourceBlock(
  SongwriterNotifier store, {
  required int sectionLengthBars,
  required int startBar,
}) {
  store.addSection(label: 'A', lengthBars: sectionLengthBars);
  final section = store.state.sections.single;
  final sectionId = section.id;

  final laneId = store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);

  const assetId = 'asset1';
  store.addAudioAsset(
    const AudioAsset(
      id: assetId,
      durationMs: 2000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [1, 2, 3],
      sourceLabel: 'Recording',
    ),
  );

  final clipId = store.addAudioClip(assetId: assetId, durationMs: 2000);
  store.addAudioBlock(
    sectionId: sectionId,
    laneId: laneId,
    audioClipId: clipId,
    startBar: startBar,
    spanBars: 1,
  );

  final lane = store.state.sections
      .firstWhere((s) => s.id == sectionId)
      .lanes
      .firstWhere((l) => l.id == laneId);
  final blockId = lane.blocks.firstWhere((b) => b.audioClipId == clipId).id;

  return _SeededAudio(
    sectionId: sectionId,
    laneId: laneId,
    assetId: assetId,
    clipId: clipId,
    blockId: blockId,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('scatterSlices replaces source with consecutive 1-bar stretch clips', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(songwriterProvider.notifier);

    // --- Seed: 4-bar section, audio lane, one source clip+block at bar 0. ---
    final ids = seedAudioSourceBlock(store, sectionLengthBars: 4, startBar: 0);

    final placedIds = store.scatterSlices(
      sectionId: ids.sectionId,
      laneId: ids.laneId,
      sourceBlockId: ids.blockId,
      slices: const [
        PlacedSlice(trimStartMs: 0, trimEndMs: 500, bar: 0),
        PlacedSlice(trimStartMs: 500, trimEndMs: 1000, bar: 1),
        PlacedSlice(trimStartMs: 1000, trimEndMs: 1500, bar: 2),
      ],
    );

    expect(placedIds.length, 3);
    final project = container.read(songwriterProvider);
    final lane = project.sections
        .firstWhere((s) => s.id == ids.sectionId)
        .lanes
        .firstWhere((l) => l.id == ids.laneId);
    final audioBlocks = lane.blocks.where((b) => b.audioClipId != null).toList()
      ..sort((a, b) => a.startBar.compareTo(b.startBar));
    expect(audioBlocks.map((b) => b.startBar), [0, 1, 2]);
    expect(audioBlocks.every((b) => b.spanBars == 1), isTrue);
    // Source block gone.
    expect(audioBlocks.any((b) => b.id == ids.blockId), isFalse);
    // All slice clips share the source asset and are stretch-fit.
    for (final b in audioBlocks) {
      final clip = project.audioClips.firstWhere((c) => c.id == b.audioClipId);
      expect(clip.assetId, ids.assetId);
      expect(clip.fitMode, AudioFitMode.stretch);
    }
  });
}
