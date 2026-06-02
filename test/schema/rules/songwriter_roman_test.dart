import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  // Key of C major (keyRootPc 0).
  test('diatonic majors and minors in C major', () {
    expect(romanNumeralFor(0, 'major', 0, 'major'), 'I');
    expect(romanNumeralFor(2, 'minor', 0, 'major'), 'ii');
    expect(romanNumeralFor(4, 'minor', 0, 'major'), 'iii');
    expect(romanNumeralFor(5, 'major', 0, 'major'), 'IV');
    expect(romanNumeralFor(7, 'major', 0, 'major'), 'V');
    expect(romanNumeralFor(9, 'minor', 0, 'major'), 'vi');
    expect(romanNumeralFor(11, 'dim', 0, 'major'), 'vii°');
  });

  test('non-diatonic root returns null', () {
    expect(romanNumeralFor(1, 'major', 0, 'major'), isNull); // C# not in C major
  });

  test('null key returns null', () {
    expect(romanNumeralFor(0, 'major', null, null), isNull);
  });
}
