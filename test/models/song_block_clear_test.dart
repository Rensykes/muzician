import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('copyWith can clear saveId', () {
    final b = const SongBlock(
      id: 'b',
      startBar: 0,
      spanBars: 1,
      saveId: 's1',
    ).copyWith(clearSaveId: true);
    expect(b.saveId, isNull);
  });

  test('copyWith can clear embedded', () {
    final b = const SongBlock(
      id: 'b',
      startBar: 0,
      spanBars: 1,
      saveId: 's1',
    ).copyWith(clearEmbedded: true);
    expect(b.embedded, isNull);
    expect(b.saveId, 's1');
  });

  test(
    'copyWith can clear recognized identity while retaining exact notes',
    () {
      const original = SongBlock(
        id: 'b',
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: ['C', 'E', 'G'],
        romanNumeral: 'I',
      );

      final exact = original.copyWith(clearChordIdentity: true);

      expect(exact.chordSymbol, 'C');
      expect(exact.chordNotes, ['C', 'E', 'G']);
      expect(exact.chordQuality, isNull);
      expect(exact.chordRootPc, isNull);
      expect(exact.romanNumeral, isNull);
    },
  );
}
