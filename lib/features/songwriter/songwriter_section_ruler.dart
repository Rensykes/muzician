import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart' show SongSection;
import '../../schema/rules/songwriter_playback_rules.dart'
    show activePositionForBar, sectionBarGlobalTick;
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import 'songwriter_playhead.dart';

/// A bar ruler at the top of a section card. Tapping/dragging parks the playback
/// start ([songwriterStartTickProvider]); the header Play button resumes from
/// it. Draws a parked marker at the set bar and overlays the live
/// [SongwriterRowPlayhead] during playback.
class SongwriterSectionRuler extends ConsumerWidget {
  const SongwriterSectionRuler({
    super.key,
    required this.section,
    required this.instanceIndex,
  });
  final SongSection section;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(songwriterProvider.select((p) => p.sections));
    final config = ref.watch(songwriterProvider.select((p) => p.config));
    final startTick = ref.watch(songwriterStartTickProvider);
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final measureTicks = config.ticksPerBeat * config.beatsPerBar;

    int? markerBar;
    final pos = activePositionForBar(sections, startTick ~/ measureTicks);
    if (pos != null &&
        pos.sectionId == section.id &&
        pos.instanceIndex == instanceIndex) {
      markerBar = pos.localBar;
    }

    void setStartFromDx(double dx, double width) {
      final cell = width / bars;
      final b = (dx / cell).floor().clamp(0, bars - 1);
      ref
          .read(songwriterStartTickProvider.notifier)
          .setTick(
            sectionBarGlobalTick(
              sections,
              config,
              section.id,
              b,
              instanceIndex: instanceIndex,
            ),
          );
    }

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final cell = w / bars;
        return GestureDetector(
          key: Key('sectionRuler_${section.id}_$instanceIndex'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setStartFromDx(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => setStartFromDx(d.localPosition.dx, w),
          child: SizedBox(
            height: 18,
            width: w,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RulerPainter(
                      bars: bars,
                      lineColor: Colors.white.withValues(alpha: 0.18),
                      numberColor: MuzicianTheme.textMuted,
                    ),
                  ),
                ),
                if (markerBar != null)
                  Positioned(
                    left: markerBar * cell,
                    top: 0,
                    bottom: 0,
                    child: const SizedBox(
                      key: Key('sectionRulerMarker'),
                      width: 10,
                      child: CustomPaint(painter: _MarkerPainter()),
                    ),
                  ),
                Positioned.fill(
                  child: SongwriterRowPlayhead(
                    sectionId: section.id,
                    instanceIndex: instanceIndex,
                    rowStartBar: 0,
                    barsInRow: bars,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.bars,
    required this.lineColor,
    required this.numberColor,
  });
  final int bars;
  final Color lineColor;
  final Color numberColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars < 1 ? 1 : bars;
    final cell = size.width / n;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      final x = i * cell;
      if (i > 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(color: numberColor, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 2));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.bars != bars ||
      old.lineColor != lineColor ||
      old.numberColor != numberColor;
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = MuzicianTheme.sky;
    // A small downward flag at the top-left plus a full-height line.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(8, 0)
      ..lineTo(0, 7)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, size.height),
      p..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => false;
}
