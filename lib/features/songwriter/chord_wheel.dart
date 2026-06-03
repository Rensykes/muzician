import 'dart:math';
import 'dart:ui';

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
