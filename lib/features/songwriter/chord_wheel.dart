import 'dart:math';

import 'package:flutter/material.dart';

import '../../schema/rules/songwriter_rules.dart';

const _wedgeCount = 7;
const _innerRadiusFraction = 0.3;

/// Returns the degree index (0..6) of the wedge at [localPoint] inside a
/// chord wheel of [size], or null when the tap is outside the wheel ring
/// (inside the inner hole or outside the outer edge).
int? chordWheelHitTest(Offset localPoint, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  final outerRadius = size.shortestSide / 2;
  final innerRadius = outerRadius * _innerRadiusFraction;
  final delta = localPoint - center;
  final dist = delta.distance;
  if (dist < innerRadius || dist > outerRadius) return null;

  // atan2 gives angle from +x axis (3 o'clock), counter-clockwise positive.
  // We want clockwise from -y (12 o'clock): rotate by +pi/2.
  var angle = atan2(delta.dy, delta.dx) + pi / 2;
  if (angle < 0) angle += 2 * pi;

  final wedgeAngle = 2 * pi / _wedgeCount;
  final degree = (angle / wedgeAngle).floor() % _wedgeCount;
  return degree;
}

/// A radial diatonic chord picker. Shows 7 wedges (one per scale degree)
/// labeled with the chord symbol and Roman numeral. Tapping a wedge invokes
/// [onPick] with the corresponding [DiatonicTriad].
class ChordWheel extends StatelessWidget {
  const ChordWheel({
    super.key,
    required this.keyRootPc,
    required this.scaleName,
    required this.onPick,
  });
  final int keyRootPc;
  final String scaleName;
  final ValueChanged<DiatonicTriad> onPick;

  @override
  Widget build(BuildContext context) {
    final triads = diatonicTriads(keyRootPc, scaleName);
    if (triads.isEmpty) {
      return const Center(child: Text('Set a key to use the chord wheel'));
    }
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapUp: (details) {
        final size = context.size;
        if (size == null) return;
        final degree = chordWheelHitTest(details.localPosition, size);
        if (degree != null && degree < triads.length) {
          onPick(triads[degree]);
        }
      },
      child: CustomPaint(
        painter: _ChordWheelPainter(
          triads: triads,
          majorColor: scheme.primary,
          minorColor: scheme.secondary,
          dimColor: Colors.grey,
          textColor: scheme.onPrimary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ChordWheelPainter extends CustomPainter {
  _ChordWheelPainter({
    required this.triads,
    required this.majorColor,
    required this.minorColor,
    required this.dimColor,
    required this.textColor,
  });
  final List<DiatonicTriad> triads;
  final Color majorColor;
  final Color minorColor;
  final Color dimColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.shortestSide / 2 - 4;
    final innerRadius = outerRadius * _innerRadiusFraction;
    final wedgeAngle = 2 * pi / _wedgeCount;

    for (var d = 0; d < triads.length; d++) {
      final triad = triads[d];
      // Wedge d boundary starts at -pi/2 + d * wedge (matches hit-test).
      final startAngle = -pi / 2 + d * wedgeAngle;

      final fill = Paint()
        ..color = _colorForQuality(triad.quality)
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(
          center.dx + innerRadius * cos(startAngle),
          center.dy + innerRadius * sin(startAngle),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: outerRadius),
          startAngle,
          wedgeAngle,
          false,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: innerRadius),
          startAngle + wedgeAngle,
          -wedgeAngle,
          false,
        )
        ..close();
      canvas.drawPath(path, fill);

      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final midAngle = startAngle + wedgeAngle / 2;
      final labelRadius = (innerRadius + outerRadius) / 2;
      final labelCenter = Offset(
        center.dx + labelRadius * cos(midAngle),
        center.dy + labelRadius * sin(midAngle),
      );

      final symbolPainter = TextPainter(
        text: TextSpan(
          text: triad.symbol,
          style: TextStyle(
              color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      symbolPainter.paint(
        canvas,
        labelCenter -
            Offset(symbolPainter.width / 2, symbolPainter.height + 1),
      );

      final numeralPainter = TextPainter(
        text: TextSpan(
          text: triad.romanNumeral,
          style: TextStyle(
              color: textColor.withValues(alpha: 0.7), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      numeralPainter.paint(
        canvas,
        labelCenter - Offset(numeralPainter.width / 2, -1),
      );
    }
  }

  Color _colorForQuality(String quality) {
    if (quality == 'dim' || quality == 'aug') return dimColor;
    if (quality == 'm') return minorColor;
    return majorColor;
  }

  @override
  bool shouldRepaint(_ChordWheelPainter old) =>
      old.triads != triads ||
      old.majorColor != majorColor ||
      old.minorColor != minorColor;
}
