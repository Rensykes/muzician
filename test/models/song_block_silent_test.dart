import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongBlock round-trips isSilent flag', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 1,
      isSilent: true,
      lyrics: ['(instrumental)'],
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.isSilent, isTrue);
    expect(back.lyrics, ['(instrumental)']);
    expect(back.chordSymbol, isNull);
  });

  test('copyWith toggles isSilent', () {
    const b = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
    expect(b.copyWith(isSilent: true).isSilent, isTrue);
  });

  test('fromJson defaults isSilent to false when absent', () {
    final back = SongBlock.fromJson({
      'id': 'b1',
      'startBar': 0,
      'spanBars': 1,
    });
    expect(back.isSilent, isFalse);
  });
}
