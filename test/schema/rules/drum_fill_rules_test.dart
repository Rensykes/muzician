import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/drum_fill_rules.dart';

void main() {
  group('everyN', () {
    test('every 4 ticks over 16 fills the beats', () {
      expect(everyN(16, 4), [0, 4, 8, 12]);
    });

    test('offset shifts the start', () {
      expect(everyN(16, 4, offset: 2), [2, 6, 10, 14]);
    });

    test('step 1 fills every tick', () {
      final ticks = everyN(16, 1);
      expect(ticks.length, 16);
      expect(ticks.first, 0);
      expect(ticks.last, 15);
    });

    test('step larger than length yields only the offset start', () {
      expect(everyN(16, 32), [0]);
      expect(everyN(16, 32, offset: 4), [4]);
    });

    test('zero / negative guards return empty', () {
      expect(everyN(16, 0), isEmpty);
      expect(everyN(0, 4), isEmpty);
    });

    test('offset at or beyond length yields empty', () {
      expect(everyN(16, 4, offset: 16), isEmpty);
    });
  });

  group('euclid', () {
    test('4 over 16 is evenly spaced', () {
      expect(euclid(16, 4), [0, 4, 8, 12]);
    });

    test('classic 3 over 8 (tresillo)', () {
      expect(euclid(8, 3), [0, 3, 6]);
    });

    test('5 over 16', () {
      expect(euclid(16, 5), [0, 3, 6, 9, 12]);
    });

    test('hits >= length fills everything', () {
      expect(euclid(4, 4), [0, 1, 2, 3]);
      expect(euclid(4, 5), [0, 1, 2, 3]);
    });

    test('single hit lands on 0', () {
      expect(euclid(4, 1), [0]);
    });

    test('rotation shifts and re-sorts', () {
      expect(euclid(16, 4, rotation: 1), [1, 5, 9, 13]);
    });

    test('zero / negative guards return empty', () {
      expect(euclid(16, 0), isEmpty);
      expect(euclid(0, 4), isEmpty);
    });
  });
}
