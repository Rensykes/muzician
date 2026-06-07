import 'package:flutter/material.dart';

import '../../theme/muzician_theme.dart';

/// Bar-number ruler. Leads with [gutter] px (to align with the lane gutter),
/// then one evenly-sized cell per bar showing its 1-based number.
class BarRuler extends StatelessWidget {
  const BarRuler({super.key, required this.lengthBars, required this.gutter});
  final int lengthBars;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    const style = TextStyle(
      color: MuzicianTheme.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          SizedBox(width: gutter),
          Expanded(
            child: Row(
              children: [
                for (var b = 1; b <= bars; b++)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('$b', style: style),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint vertical gridlines at each bar boundary, painted behind lane blocks.
class BarGridPainter extends CustomPainter {
  BarGridPainter({required this.lengthBars, required this.color});
  final int lengthBars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    final barWidth = size.width / bars;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i < bars; i++) {
      final x = i * barWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(BarGridPainter old) =>
      old.lengthBars != lengthBars || old.color != color;
}

class PlayheadPainter extends CustomPainter {
  PlayheadPainter({
    required this.bar,
    required this.lengthBars,
    required this.color,
  });
  final double bar;
  final int lengthBars;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = lengthBars < 1 ? 1 : lengthBars;
    final x = (bar / bars) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(PlayheadPainter old) =>
      old.bar != bar || old.lengthBars != lengthBars || old.color != color;
}
