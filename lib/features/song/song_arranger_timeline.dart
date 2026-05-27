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
const double _kTickWidth = 4.0;

class SongArrangerTimeline extends ConsumerStatefulWidget {
  final int measureTicks;
  final int? currentPlaybackTick;

  const SongArrangerTimeline({
    super.key,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  ConsumerState<SongArrangerTimeline> createState() =>
      _SongArrangerTimelineState();
}

class _SongArrangerTimelineState extends ConsumerState<SongArrangerTimeline> {
  late final ScrollController _hScroll;

  @override
  void initState() {
    super.initState();
    _hScroll = ScrollController();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songProjectProvider);
    final orderedTracks = [...project.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));

    final clipLengths = <String, int>{};
    for (final clip in project.clips) {
      final len = song_rules.patternLengthForClip(project, clip);
      if (len != null) clipLengths[clip.id] = len;
    }

    final totalTicks = widget.measureTicks * project.config.totalMeasures;
    final timelineWidth = totalTicks * _kTickWidth;

    return Column(
      children: [
        _MeasureRuler(
          totalMeasures: project.config.totalMeasures,
          measureTicks: widget.measureTicks,
          timelineWidth: timelineWidth,
          hScroll: _hScroll,
          currentPlaybackTick: widget.currentPlaybackTick,
        ),
        Expanded(
          child: ListView.builder(
            controller: ScrollController(),
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
                measureTicks: widget.measureTicks,
                totalMeasures: project.config.totalMeasures,
                timelineWidth: timelineWidth,
                hScroll: _hScroll,
                currentPlaybackTick: widget.currentPlaybackTick,
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
  final double timelineWidth;
  final ScrollController hScroll;
  final int? currentPlaybackTick;

  const _MeasureRuler({
    required this.totalMeasures,
    required this.measureTicks,
    required this.timelineWidth,
    required this.hScroll,
    required this.currentPlaybackTick,
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
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: timelineWidth,
                height: 28,
                child: CustomPaint(
                  painter: _RulerPainter(
                    totalMeasures: totalMeasures,
                    measureTicks: measureTicks,
                    currentPlaybackTick: currentPlaybackTick,
                  ),
                  size: Size(timelineWidth, 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final int totalMeasures;
  final int measureTicks;
  final int? currentPlaybackTick;

  const _RulerPainter({
    required this.totalMeasures,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measureWidth = measureTicks * _kTickWidth;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    for (var m = 0; m <= totalMeasures; m++) {
      final x = m * measureWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      if (m < totalMeasures) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${m + 1}',
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 6));
      }
    }

    if (currentPlaybackTick != null) {
      final cx = currentPlaybackTick! * _kTickWidth;
      final cursorPaint = Paint()
        ..color = MuzicianTheme.sky
        ..strokeWidth = 2;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), cursorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      totalMeasures != oldDelegate.totalMeasures ||
      currentPlaybackTick != oldDelegate.currentPlaybackTick;
}

class _TrackLane extends ConsumerWidget {
  final SongTrack track;
  final List<SongClipInstance> clips;
  final Map<String, int> clipLengths;
  final int measureTicks;
  final int totalMeasures;
  final double timelineWidth;
  final ScrollController hScroll;
  final int? currentPlaybackTick;

  const _TrackLane({
    required this.track,
    required this.clips,
    required this.clipLengths,
    required this.measureTicks,
    required this.totalMeasures,
    required this.timelineWidth,
    required this.hScroll,
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
                child: SingleChildScrollView(
                  controller: hScroll,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: timelineWidth,
                    height: 56,
                    child: GestureDetector(
                      onTapDown: (details) {
                        final tapTick = (details.localPosition.dx / _kTickWidth)
                            .round()
                            .clamp(0, measureTicks * totalMeasures - 1);

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
                        size: Size(timelineWidth, 56),
                      ),
                    ),
                  ),
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
    final measureLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    for (var m = 0; m <= totalMeasures; m++) {
      final x = m * measureTicks * _kTickWidth;
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

      final left = clip.startTick * _kTickWidth;
      final length = clipLengths[clip.id] ?? measureTicks;
      final right = left + length * _kTickWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 1, 6, right - 1, size.height - 6),
        const Radius.circular(6),
      );

      canvas.drawRRect(rect, clipPaint);
      canvas.drawRRect(rect, clipBorderPaint);
    }

    if (currentPlaybackTick != null) {
      final cx = currentPlaybackTick! * _kTickWidth;
      final cursorPaint = Paint()
        ..color = MuzicianTheme.sky
        ..strokeWidth = 2;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), cursorPaint);

      final path = Path()
        ..moveTo(cx - 5, 0)
        ..lineTo(cx + 5, 0)
        ..lineTo(cx, 6)
        ..close();
      canvas.drawPath(path, Paint()..color = MuzicianTheme.sky);
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
