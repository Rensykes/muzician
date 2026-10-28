import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show OrdinalSortKey, SemanticsProperties;

import '../../schema/rules/songwriter_rules.dart';
import '../../theme/studio_theme.dart';
import '../../utils/note_utils.dart';

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
    this.spelling = NoteSpelling.sharps,
    required this.onPick,
  });
  final int keyRootPc;
  final String scaleName;
  final NoteSpelling spelling;
  final ValueChanged<DiatonicTriad> onPick;

  @override
  Widget build(BuildContext context) {
    final triads = diatonicTriads(keyRootPc, scaleName);
    if (triads.isEmpty) {
      return const Center(
        child: Text(
          'This scale does not support the seven-degree chord wheel.',
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      excludeFromSemantics: true,
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
          keyRootPc: keyRootPc,
          scaleName: scaleName,
          triads: triads,
          majorColor: StudioPalette.of(context).isStudio
              ? StudioPalette.of(context).dialogBg
              : scheme.primary,
          minorColor: StudioPalette.of(context).isStudio
              ? StudioPalette.of(context).surface
              : scheme.secondary,
          dimColor: StudioPalette.of(context).isStudio
              ? StudioPalette.of(context).scaffoldBg
              : Colors.grey.shade600,
          textColor: StudioPalette.of(context).textPrimary,
          spelling: spelling,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
          onPick: onPick,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ChordWheelPainter extends CustomPainter {
  _ChordWheelPainter({
    required this.keyRootPc,
    required this.scaleName,
    required this.triads,
    required this.majorColor,
    required this.minorColor,
    required this.dimColor,
    required this.textColor,
    required this.spelling,
    required this.textScaler,
    required this.textDirection,
    required this.onPick,
  });
  final int keyRootPc;
  final String scaleName;
  final List<DiatonicTriad> triads;
  final Color majorColor;
  final Color minorColor;
  final Color dimColor;
  final Color textColor;
  final NoteSpelling spelling;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final ValueChanged<DiatonicTriad> onPick;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    final outerRadius = size.shortestSide / 2 - 4;
    final innerRadius = outerRadius * _innerRadiusFraction;
    return <CustomPainterSemantics>[
      for (var degree = 0; degree < triads.length; degree++)
        _degreeSemantics(
          degree,
          triads[degree],
          size,
          innerRadius,
          outerRadius,
        ),
    ];
  };

  CustomPainterSemantics _degreeSemantics(
    int degree,
    DiatonicTriad triad,
    Size size,
    double innerRadius,
    double outerRadius,
  ) {
    final symbol = formatRecognizedChordLabel(
      symbol: triad.symbol,
      rootPc: triad.rootPc,
      quality: triad.quality,
      spelling: spelling,
    );
    return CustomPainterSemantics(
      key: ValueKey('chord-wheel-degree-$degree'),
      rect: _semanticTargetRect(
        _degreeLabelCenter(degree, size, innerRadius, outerRadius),
        size,
      ),
      properties: SemanticsProperties(
        label: '${triad.romanNumeral}, $symbol chord',
        button: true,
        textDirection: textDirection,
        sortKey: OrdinalSortKey(degree.toDouble()),
        onTap: () => onPick(triad),
      ),
    );
  }

  Rect _semanticTargetRect(Offset center, Size size) {
    final width = min(44.0, size.width);
    final height = min(44.0, size.height);
    return Rect.fromLTWH(
      (center.dx - width / 2).clamp(0.0, size.width - width).toDouble(),
      (center.dy - height / 2).clamp(0.0, size.height - height).toDouble(),
      width,
      height,
    );
  }

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

      final labelCenter = _degreeLabelCenter(d, size, innerRadius, outerRadius);

      final symbolPainter = TextPainter(
        text: TextSpan(
          text: formatRecognizedChordLabel(
            symbol: triad.symbol,
            rootPc: triad.rootPc,
            quality: triad.quality,
            spelling: spelling,
          ),
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      symbolPainter.paint(
        canvas,
        labelCenter - Offset(symbolPainter.width / 2, symbolPainter.height + 1),
      );

      final numeralPainter = TextPainter(
        text: TextSpan(
          text: triad.romanNumeral,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
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
      old.minorColor != minorColor ||
      old.dimColor != dimColor ||
      old.textColor != textColor ||
      old.spelling != spelling ||
      old.textScaler != textScaler;

  @override
  bool shouldRebuildSemantics(_ChordWheelPainter old) =>
      old.keyRootPc != keyRootPc ||
      old.scaleName != scaleName ||
      old.triads != triads ||
      old.spelling != spelling ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection ||
      old.onPick != onPick;
}

Offset _degreeLabelCenter(
  int degree,
  Size size,
  double innerRadius,
  double outerRadius,
) {
  final wedgeAngle = 2 * pi / _wedgeCount;
  final midAngle = -pi / 2 + (degree + 0.5) * wedgeAngle;
  final labelRadius = (innerRadius + outerRadius) / 2;
  final center = Offset(size.width / 2, size.height / 2);
  return Offset(
    center.dx + labelRadius * cos(midAngle),
    center.dy + labelRadius * sin(midAngle),
  );
}
