import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../song/song_audio_clip_body.dart';
import 'songwriter_audio_actions.dart';
import 'songwriter_audio_clip_sheet.dart';

IconData fitGlyph(AudioFitMode m) => switch (m) {
  AudioFitMode.loop => Icons.repeat,
  AudioFitMode.oneShot => Icons.play_arrow,
  AudioFitMode.stretch => Icons.swap_horiz,
};

class SongwriterAudioLaneRow extends ConsumerWidget {
  const SongwriterAudioLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    required this.clipsById,
    required this.assetsById,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final Map<String, AudioClip> clipsById;
  final Map<String, AudioAsset> assetsById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final ownerByBar = <int, SongBlock>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        ownerByBar[i] = b;
      }
    }
    final cells = <Widget>[];
    var i = 0;
    while (i < bars) {
      final owner = ownerByBar[i];
      if (owner != null && owner.startBar == i) {
        final span = owner.spanBars.clamp(1, bars - i);
        final clip = owner.audioClipId == null
            ? null
            : clipsById[owner.audioClipId];
        final asset = clip == null ? null : assetsById[clip.assetId];
        cells.add(
          Expanded(
            flex: span,
            child: GestureDetector(
              key: Key('sheetAudioTile_${owner.audioClipId ?? owner.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showSongwriterAudioClipSheet(
                context: context,
                sectionId: section.id,
                laneId: lane.id,
                clipId: owner.audioClipId!,
              ),
              onLongPress: () => ref
                  .read(songwriterProvider.notifier)
                  .removeAudioBlock(
                    sectionId: section.id,
                    laneId: lane.id,
                    blockId: owner.id,
                  ),
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: asset == null
                          ? Container(color: const Color(0xFF13314A))
                          : AudioClipBody(
                              name: asset.sourceLabel,
                              durationMs: clip!.trimEndMs - clip.trimStartMs,
                              format: asset.format,
                              peaks: asset.peaks,
                              isBroken: false,
                            ),
                    ),
                    if (clip != null)
                      Positioned(
                        right: 4,
                        top: 2,
                        child: Icon(
                          fitGlyph(clip.fitMode),
                          size: 12,
                          color: MuzicianTheme.textPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        i += span;
      } else if (owner != null) {
        i++;
      } else {
        final barIndex = i;
        cells.add(
          Expanded(
            flex: 1,
            child: GestureDetector(
              key: Key('sheetAudioEmpty_${lane.id}_$barIndex'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showSongwriterAudioPicker(
                ref,
                context: context,
                sectionId: section.id,
                laneId: lane.id,
                startBar: barIndex,
                sectionLengthBars: bars,
              ),
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: MuzicianTheme.glassBorder),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        );
        i++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            lane.label ?? 'Sample',
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(children: cells),
      ],
    );
  }
}
