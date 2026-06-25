import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../store/songwriter_stretch_controller.dart';
import '../../theme/muzician_theme.dart';
import '../song/song_audio_clip_body.dart';
import '../_mockup_shell.dart' show showWidgetSheet;
import 'songwriter_audio_lane_row.dart' show fitGlyph;

Future<void> showSongwriterAudioClipSheet({
  required BuildContext context,
  required String sectionId,
  required String laneId,
  required String clipId,
}) => showWidgetSheet(
  context: context,
  title: 'Audio Clip',
  child: SongwriterAudioClipBody(
    sectionId: sectionId,
    laneId: laneId,
    clipId: clipId,
  ),
);

class SongwriterAudioClipBody extends ConsumerWidget {
  const SongwriterAudioClipBody({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.clipId,
  });
  final String sectionId;
  final String laneId;
  final String clipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final clip = project.audioClips.where((c) => c.id == clipId).firstOrNull;
    if (clip == null) return const SizedBox.shrink();
    final asset = project.audioAssets
        .where((a) => a.id == clip.assetId)
        .firstOrNull;
    final section = project.sections
        .where((s) => s.id == sectionId)
        .firstOrNull;
    final block = section?.lanes
        .where((l) => l.id == laneId)
        .expand((l) => l.blocks)
        .where((b) => b.audioClipId == clipId)
        .firstOrNull;
    if (asset == null || section == null || block == null) {
      return const SizedBox.shrink();
    }
    final store = ref.read(songwriterProvider.notifier);
    final maxSpan = section.lengthBars <= 1 ? 1 : section.lengthBars - 1;

    void rerenderIfStretch() {
      final cur = ref
          .read(songwriterProvider)
          .audioClips
          .where((c) => c.id == clipId)
          .firstOrNull;
      if (cur != null && cur.fitMode == AudioFitMode.stretch) {
        ref.read(songwriterStretchControllerProvider).rerender(clipId);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 80,
            child: _TrimWaveform(
              asset: asset,
              clip: clip,
              onTrim: (startMs, endMs) {
                store.setClipTrim(
                  clipId: clipId,
                  trimStartMs: startMs,
                  trimEndMs: endMs,
                );
                rerenderIfStretch();
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final mode in AudioFitMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ChoiceChip(
                    key: Key('clipFit_${mode.name}'),
                    avatar: Icon(fitGlyph(mode), size: 16),
                    label: Text(mode.name),
                    selected: clip.fitMode == mode,
                    onSelected: (_) {
                      store.setClipFitMode(clipId: clipId, fitMode: mode);
                      if (mode == AudioFitMode.stretch) {
                        ref
                            .read(songwriterStretchControllerProvider)
                            .rerender(clipId);
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('clipSpanMinus'),
                icon: const Icon(Icons.remove),
                onPressed: () {
                  store.setBlockPlacement(
                    sectionId: sectionId,
                    laneId: laneId,
                    blockId: block.id,
                    startBar: block.startBar,
                    spanBars: (block.spanBars - 1).clamp(1, maxSpan),
                  );
                  rerenderIfStretch();
                },
              ),
              Text(
                '${block.spanBars} bar(s)',
                style: const TextStyle(color: MuzicianTheme.textPrimary),
              ),
              IconButton(
                key: const ValueKey('clipSpanPlus'),
                icon: const Icon(Icons.add),
                onPressed: () {
                  store.setBlockPlacement(
                    sectionId: sectionId,
                    laneId: laneId,
                    blockId: block.id,
                    startBar: block.startBar,
                    spanBars: (block.spanBars + 1).clamp(1, maxSpan),
                  );
                  rerenderIfStretch();
                },
              ),
            ],
          ),
          if (ref.watch(songwriterStretchProcessingProvider).contains(clipId))
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Stretching…',
                    style: TextStyle(color: MuzicianTheme.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrimWaveform extends StatefulWidget {
  const _TrimWaveform({
    required this.asset,
    required this.clip,
    required this.onTrim,
  });
  final AudioAsset asset;
  final AudioClip clip;
  final void Function(int startMs, int endMs) onTrim;
  @override
  State<_TrimWaveform> createState() => _TrimWaveformState();
}

class _TrimWaveformState extends State<_TrimWaveform> {
  late double _start = widget.asset.durationMs == 0
      ? 0.0
      : widget.clip.trimStartMs / widget.asset.durationMs;
  late double _end = widget.asset.durationMs == 0
      ? 1.0
      : (widget.clip.trimEndMs == 0
                ? widget.asset.durationMs
                : widget.clip.trimEndMs) /
            widget.asset.durationMs;

  void _commit() => widget.onTrim(
    (_start * widget.asset.durationMs).round(),
    (_end * widget.asset.durationMs).round(),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        return Stack(
          children: [
            Positioned.fill(
              child: AudioClipBody(
                name: widget.asset.sourceLabel,
                durationMs: widget.asset.durationMs,
                format: widget.asset.format,
                peaks: widget.asset.peaks,
                isBroken: false,
              ),
            ),
            _handle(w, _start, const Key('clipTrimStart'), (nx) {
              setState(() => _start = nx.clamp(0.0, _end - 0.02));
            }),
            _handle(w, _end, const Key('clipTrimEnd'), (nx) {
              setState(() => _end = nx.clamp(_start + 0.02, 1.0));
            }),
          ],
        );
      },
    );
  }

  Widget _handle(
    double w,
    double frac,
    Key key,
    void Function(double nx) onMove,
  ) {
    return Positioned(
      left: (frac * w - 8).clamp(0.0, w - 16),
      top: 0,
      bottom: 0,
      child: GestureDetector(
        key: key,
        onHorizontalDragUpdate: (d) => onMove(((frac * w) + d.delta.dx) / w),
        onHorizontalDragEnd: (_) => _commit(),
        child: Container(
          width: 16,
          alignment: Alignment.center,
          child: Container(width: 3, color: MuzicianTheme.sky),
        ),
      ),
    );
  }
}
