import 'dart:math';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/chord_wheel.dart';

void main() {
  // The wheel divides 360° into 7 equal wedges. Wedge 0 starts at 12 o'clock
  // (boundary). A tap slightly clockwise from 12 o'clock should hit degree 0.
  test('tap just clockwise of 12 o\'clock returns degree 0', () {
    const size = Size(200, 200);
    // Center is (100,100). Slightly right of 12 o'clock direction.
    final degree = chordWheelHitTest(const Offset(110, 30), size);
    expect(degree, 0);
  });

  test('tap in center (inside inner radius) returns null', () {
    const size = Size(200, 200);
    final degree = chordWheelHitTest(const Offset(100, 100), size);
    expect(degree, isNull);
  });

  test('tap outside the wheel returns null', () {
    const size = Size(200, 200);
    final degree = chordWheelHitTest(const Offset(0, 0), size);
    expect(degree, isNull);
  });

  test('each of the 7 wedges can be hit', () {
    const size = Size(200, 200);
    const center = Offset(100, 100);
    const radius = 80.0;
    final wedgeAngle = 2 * pi / 7;
    final hit = <int>{};
    for (var d = 0; d < 7; d++) {
      // Aim for the middle of each wedge: boundary at -pi/2 + d*wedge,
      // middle at -pi/2 + (d+0.5)*wedge.
      final angle = -pi / 2 + (d + 0.5) * wedgeAngle;
      final point = center + Offset(radius * cos(angle), radius * sin(angle));
      final result = chordWheelHitTest(point, size);
      expect(result, isNotNull, reason: 'wedge $d should be hit');
      hit.add(result!);
    }
    expect(hit, {0, 1, 2, 3, 4, 5, 6});
  });
}
