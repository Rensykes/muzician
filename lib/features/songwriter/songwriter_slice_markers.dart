import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// Draggable cut markers over the clip waveform. [markers] are fractions in
/// [0,1] across the width. Tapping empty space calls [onAdd] with the tapped
/// fraction; dragging a marker calls [onMove]; a marker dragged out (or
/// long-pressed) calls [onDelete]. Pure presentation — the editor owns state.
class SongwriterSliceMarkers extends StatelessWidget {
  const SongwriterSliceMarkers({
    super.key,
    required this.markers,
    required this.onAdd,
    required this.onMove,
    required this.onDelete,
  });
  final List<double> markers;
  final void Function(double fraction) onAdd;
  final void Function(int index, double fraction) onMove;
  final void Function(int index) onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => onAdd((d.localPosition.dx / w).clamp(0.0, 1.0)),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _MarkerPainter(markers, MuzicianTheme.sky),
                  ),
                ),
              ),
              for (var i = 0; i < markers.length; i++)
                Positioned(
                  left: (markers[i] * w - 11).clamp(0.0, w - 22),
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    key: Key('sliceMarker_$i'),
                    onHorizontalDragUpdate: (d) => onMove(
                      i,
                      ((markers[i] * w) + d.delta.dx).clamp(0.0, w) / w,
                    ),
                    onLongPress: () => onDelete(i),
                    child: const SizedBox(
                      width: 22,
                      child: Center(
                        child: SizedBox(
                          width: 2,
                          child: ColoredBox(color: MuzicianTheme.sky),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.markers, this.color);
  final List<double> markers;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final m in markers) {
      final x = m * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.markers != markers || old.color != color;
}
