library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_pattern_editor_launcher.dart';
import 'song_track_header.dart';

const double _kHeaderWidth = 220;

class SongArrangerTimeline extends ConsumerWidget {
  final int measureTicks;
  final int? currentPlaybackTick;

  const SongArrangerTimeline({
    super.key,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songProjectProvider);
    final orderedTracks = [...project.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));

    final clipLengths = <String, int>{};
    for (final clip in project.clips) {
      final len = song_rules.patternLengthForClip(project, clip);
      if (len != null) clipLengths[clip.id] = len;
    }

    return Column(
      children: [
        _MeasureRuler(
          totalMeasures: project.config.totalMeasures,
          measureTicks: measureTicks,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: orderedTracks.length,
            itemBuilder: (context, index) {
              final track = orderedTracks[index];
              final trackClips = project.clips
                  .where((clip) => clip.trackId == track.id)
                  .toList();
              return _TrackLane(
                track: track,
                clips: trackClips,
                clipLengths: clipLengths,
                measureTicks: measureTicks,
                totalMeasures: project.config.totalMeasures,
                currentPlaybackTick: currentPlaybackTick,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MeasureRuler extends StatelessWidget {
  final int totalMeasures;
  final int measureTicks;

  const _MeasureRuler({
    required this.totalMeasures,
    required this.measureTicks,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kHeaderWidth),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: totalMeasures,
              itemBuilder: (context, index) {
                return Container(
                  width: 60.0,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackLane extends ConsumerWidget {
  final SongTrack track;
  final List<SongClipInstance> clips;
  final Map<String, int> clipLengths;
  final int measureTicks;
  final int totalMeasures;
  final int? currentPlaybackTick;

  const _TrackLane({
    required this.track,
    required this.clips,
    required this.clipLengths,
    required this.measureTicks,
    required this.totalMeasures,
    required this.currentPlaybackTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SongTrackHeader(track: track),
        Container(
          height: 56,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: _kHeaderWidth),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalTicks = measureTicks * totalMeasures;
                    final tickWidth = totalTicks > 0
                        ? constraints.maxWidth / totalTicks
                        : 1.0;

                    return GestureDetector(
                      onTapDown: (details) {
                        final tapTick = (details.localPosition.dx / tickWidth)
                            .round()
                            .clamp(0, totalTicks > 0 ? totalTicks - 1 : 0);

                        final tappedClip = clips.firstWhere(
                          (clip) {
                            final end =
                                clip.startTick +
                                (clipLengths[clip.id] ?? measureTicks);
                            return tapTick >= clip.startTick && tapTick < end;
                          },
                          orElse: () => const SongClipInstance(
                            id: '',
                            trackId: '',
                            patternId: '',
                            patternType: SongPatternType.note,
                            startTick: -1,
                          ),
                        );

                        if (tappedClip.startTick >= 0) {
                          openClipEditor(context, ref, tappedClip);
                        } else {
                          if (track.type == SongTrackType.note) {
                            ref
                                .read(songProjectProvider.notifier)
                                .createEmptyNotePatternClip(
                                  trackId: track.id,
                                  startTick: tapTick,
                                );
                          } else {
                            ref
                                .read(songProjectProvider.notifier)
                                .createEmptyDrumPatternClip(
                                  trackId: track.id,
                                  startTick: tapTick,
                                );
                          }
                        }
                      },
                      child: CustomPaint(
                        painter: _ClipLanePainter(
                          clips: clips,
                          clipLengths: clipLengths,
                          measureTicks: measureTicks,
                          totalMeasures: totalMeasures,
                          trackColor: track.type == SongTrackType.note
                              ? MuzicianTheme.sky
                              : MuzicianTheme.orange,
                          currentPlaybackTick: currentPlaybackTick,
                        ),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClipLanePainter extends CustomPainter {
  final List<SongClipInstance> clips;
  final Map<String, int> clipLengths;
  final int measureTicks;
  final int totalMeasures;
  final Color trackColor;
  final int? currentPlaybackTick;

  const _ClipLanePainter({
    required this.clips,
    required this.clipLengths,
    required this.measureTicks,
    required this.totalMeasures,
    required this.trackColor,
    required this.currentPlaybackTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalTicks = measureTicks * totalMeasures;
    if (totalTicks == 0) return;

    final tickWidth = size.width / totalTicks;

    final measureLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    for (var m = 0; m <= totalMeasures; m++) {
      final x = m * measureTicks * tickWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), measureLinePaint);
    }

    for (final clip in clips) {
      final clipPaint = Paint()
        ..color = trackColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final clipBorderPaint = Paint()
        ..color = trackColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      final left = clip.startTick * tickWidth;
      final length = clipLengths[clip.id] ?? measureTicks;
      final right = left + length * tickWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 1, 6, right - 1, size.height - 6),
        const Radius.circular(6),
      );

      canvas.drawRRect(rect, clipPaint);
      canvas.drawRRect(rect, clipBorderPaint);
    }

    if (currentPlaybackTick != null) {
      final cursorPaint = Paint()
        ..color = MuzicianTheme.sky
        ..strokeWidth = 2;
      final cx = currentPlaybackTick! * tickWidth;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), cursorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClipLanePainter oldDelegate) =>
      clips != oldDelegate.clips ||
      clipLengths != oldDelegate.clipLengths ||
      totalMeasures != oldDelegate.totalMeasures ||
      trackColor != oldDelegate.trackColor ||
      currentPlaybackTick != oldDelegate.currentPlaybackTick;
}
