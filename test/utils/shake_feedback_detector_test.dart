import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/shake_feedback_detector.dart';

void main() {
  // 2.6 g threshold, 3 confirming samples, 1.5 s cooldown.
  test('fires after three confirming samples, not before', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    expect(d.add(0, 0, 9.81, t), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 16))), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 32))), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 48))), isTrue);
  });

  // The loud sample before the quiet one must not count, so the run after the
  // break has to reach three samples on its own.
  test('a quiet sample breaks the run', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    d.add(30, 0, 0, t);
    d.add(0, 0, 9.81, t.add(const Duration(milliseconds: 16)));
    d.add(30, 0, 0, t.add(const Duration(milliseconds: 32)));
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 48))), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 64))), isTrue);
  });

  test('cooldown swallows the tail of one shake', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    for (var i = 0; i < 3; i++) {
      d.add(30, 0, 0, t.add(Duration(milliseconds: 16 * i)));
    }
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 64))), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 80))), isFalse);
  });

  // The tail above is too short to confirm a second run on its own, so this
  // pins the cooldown itself: a full run of samples inside it stays silent.
  test('a confirming run inside the cooldown does not fire', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    for (var i = 0; i < 3; i++) {
      expect(d.add(30, 0, 0, t.add(Duration(milliseconds: 16 * i))), i == 2);
    }
    for (var i = 3; i < 6; i++) {
      expect(d.add(30, 0, 0, t.add(Duration(milliseconds: 16 * i))), isFalse);
    }
  });

  test('a NaN magnitude never counts as loud', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    for (var i = 0; i < 3; i++) {
      expect(
        d.add(
          double.nan,
          double.nan,
          double.nan,
          t.add(Duration(milliseconds: 16 * i)),
        ),
        isFalse,
      );
    }
  });

  test('fires again once the cooldown has expired', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    // The first shake fires on its third sample at t + 32 ms.
    for (var i = 0; i < 3; i++) {
      expect(d.add(30, 0, 0, t.add(Duration(milliseconds: 16 * i))), i == 2);
    }
    final lastFire = t.add(const Duration(milliseconds: 32));
    // 1600 ms after that report the full run is outside the 1500 ms cooldown.
    expect(
      d.add(30, 0, 0, lastFire.add(const Duration(milliseconds: 1600))),
      isFalse,
    );
    expect(
      d.add(30, 0, 0, lastFire.add(const Duration(milliseconds: 1616))),
      isFalse,
    );
    expect(
      d.add(30, 0, 0, lastFire.add(const Duration(milliseconds: 1632))),
      isTrue,
    );
  });

  test('reset forgets the run and the cooldown', () {
    final d = ShakeFeedbackDetector();
    final t = DateTime(2026, 11, 8, 12);
    for (var i = 0; i < 3; i++) {
      d.add(30, 0, 0, t.add(Duration(milliseconds: 16 * i)));
    }
    d.add(30, 0, 0, t.add(const Duration(milliseconds: 48)));
    d.reset();
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 64))), isFalse);
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 80))), isFalse);
    // Fires well inside the original cooldown, which reset has forgotten.
    expect(d.add(30, 0, 0, t.add(const Duration(milliseconds: 96))), isTrue);
  });
}
