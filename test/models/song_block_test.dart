import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('save-reference block round-trips', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 4,
      saveId: 'save-123',
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.id, 'b1');
    expect(back.spanBars, 4);
    expect(back.saveId, 'save-123');
    expect(back.embedded, isNull);
    expect(back.romanNumeral, isNull);
    expect(back.endBar, 4);
  });

  test('harmony block carries chord extras', () {
    const b = SongBlock(
      id: 'h1',
      startBar: 0,
      spanBars: 2,
      chordSymbol: 'Cmaj7',
      chordQuality: 'maj7',
      chordRootPc: 0,
      chordNotes: ['C', 'E', 'G', 'B'],
      romanNumeral: 'I',
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.chordSymbol, 'Cmaj7');
    expect(back.chordNotes, ['C', 'E', 'G', 'B']);
    expect(back.romanNumeral, 'I');
  });
}
