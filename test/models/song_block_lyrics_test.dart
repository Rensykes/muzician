import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongBlock default lyrics is empty list, isSilent false', () {
    const b = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
    expect(b.lyrics, isEmpty);
    expect(b.isSilent, isFalse);
  });

  test('SongBlock round-trips lyrics list', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 2,
      chordSymbol: 'C',
      lyrics: ['hello', 'goodbye', ''],
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.lyrics, ['hello', 'goodbye', '']);
  });

  test('copyWith replaces lyrics list when provided', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 1,
      lyrics: ['one'],
    );
    final next = b.copyWith(lyrics: ['one', 'two']);
    expect(next.lyrics, ['one', 'two']);
  });

  test('fromJson tolerates missing lyrics key', () {
    final back = SongBlock.fromJson({
      'id': 'b1',
      'startBar': 0,
      'spanBars': 1,
    });
    expect(back.lyrics, isEmpty);
  });
}
