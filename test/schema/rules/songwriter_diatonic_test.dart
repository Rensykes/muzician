// test/schema/rules/songwriter_diatonic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('diatonicTriads for C major yields I C, ii Dm, ... vii° Bdim', () {
    final triads = diatonicTriads(0, 'major');
    expect(triads.length, 7);

    expect(triads[0].rootPc, 0);
    expect(triads[0].quality, '');
    expect(triads[0].symbol, 'C');
    expect(triads[0].romanNumeral, 'I');
    expect(triads[0].notes, ['C', 'E', 'G']);

    expect(triads[1].symbol, 'Dm');
    expect(triads[1].romanNumeral, 'ii');

    expect(triads[2].symbol, 'Em');
    expect(triads[2].romanNumeral, 'iii');

    expect(triads[3].symbol, 'F');
    expect(triads[3].romanNumeral, 'IV');

    expect(triads[4].symbol, 'G');
    expect(triads[4].romanNumeral, 'V');

    expect(triads[5].symbol, 'Am');
    expect(triads[5].romanNumeral, 'vi');

    expect(triads[6].symbol, 'Bdim');
    expect(triads[6].romanNumeral, 'vii°');
    expect(triads[6].quality, 'dim');
  });

  test('diatonicTriads for A minor yields i Am, ii° Bdim, ... VII G', () {
    final triads = diatonicTriads(9, 'minor'); // A = pc 9
    expect(triads.length, 7);

    expect(triads[0].symbol, 'Am');
    expect(triads[0].romanNumeral, 'i');

    expect(triads[1].symbol, 'Bdim');
    expect(triads[1].romanNumeral, 'ii°');

    expect(triads[2].symbol, 'C');
    expect(triads[2].romanNumeral, 'III');
  });

  test('diatonicTriads returns empty for unknown scale', () {
    expect(diatonicTriads(0, 'nonexistent'), isEmpty);
  });
}
