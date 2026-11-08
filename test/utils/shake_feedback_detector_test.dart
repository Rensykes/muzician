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
