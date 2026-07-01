import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../store/songwriter_playback_store.dart';
import '../../theme/muzician_theme.dart';

/// Vertical playhead line over one horizontal bar-row during playback.
///
/// Renders only while this row holds the active playback bar. The active
/// section/instance/bar comes from [songwriterActivePositionProvider] (bar
/// resolution); the within-bar fraction comes from
/// [songwriterPlayheadFracProvider] (per-tick) so the line sweeps smoothly.
/// Wrapped in [IgnorePointer] so it never steals taps from the row's cells.
///
/// [rowStartBar]/[barsInRow] describe this row's slice of the section: the
/// chord grid wraps at 4 bars per row, so it passes a slice; the audio lane is
/// a single flat row, so it passes `rowStartBar: 0, barsInRow: <section bars>`.
class SongwriterRowPlayhead extends ConsumerWidget {
  const SongwriterRowPlayhead({
    super.key,
    required this.sectionId,
    required this.instanceIndex,
    required this.rowStartBar,
    required this.barsInRow,
    this.highlightActiveBar = false,
  });
  final String sectionId;
  final int instanceIndex;
  final int rowStartBar;
  final int barsInRow;

  /// When true, also tints the active bar's full-height column. Used by the
  /// audio lane (whose clip tiles have no per-bar cell highlight of their own);
  /// the chord grid leaves it false since its cells already highlight.
  final bool highlightActiveBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(songwriterActivePositionProvider);
    if (active == null ||
        active.sectionId != sectionId ||
        active.instanceIndex != instanceIndex ||
        active.localBar < rowStartBar ||
        active.localBar >= rowStartBar + barsInRow) {
      return const SizedBox.shrink();
    }
    final frac = ref.watch(songwriterPlayheadFracProvider);
    final col = (active.localBar - rowStartBar) + frac;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PlayheadLinePainter(
            col: col,
            barsInRow: barsInRow,
            color: MuzicianTheme.sky,
            highlightActiveBar: highlightActiveBar,
          ),
        ),
      ),
    );
  }
}

class _PlayheadLinePainter extends CustomPainter {
  _PlayheadLinePainter({
    required this.col,
    required this.barsInRow,
    required this.color,
    required this.highlightActiveBar,
  });
  final double col;
  final int barsInRow;
  final Color color;
  final bool highlightActiveBar;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = barsInRow < 1 ? 1 : barsInRow;
    final barWidth = size.width / bars;
    if (highlightActiveBar) {
      final bandX = col.floor() * barWidth;
      canvas.drawRect(
        Rect.fromLTWH(bandX, 0, barWidth, size.height),
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }
    final x = (col / bars) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PlayheadLinePainter old) =>
      old.col != col ||
      old.barsInRow != barsInRow ||
      old.color != color ||
      old.highlightActiveBar != highlightActiveBar;
}
