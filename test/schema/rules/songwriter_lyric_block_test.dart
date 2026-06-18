import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';

void main() {
  test('makeLyricBlock stores text in first verse, no chord', () {
    final b = makeLyricBlock(startBar: 2, spanBars: 1, text: 'la la');
    expect(b.startBar, 2);
    expect(b.spanBars, 1);
    expect(b.lyrics, ['la la']);
    expect(b.chordSymbol, isNull);
    expect(b.isSilent, isFalse);
    expect(b.id, isNotEmpty);
  });

  test('makeLyricBlock allocates one empty verse per verseCount when no text', () {
    final b = makeLyricBlock(startBar: 0, spanBars: 4, verseCount: 3);
    expect(b.lyrics, ['', '', '']);
  });
}
