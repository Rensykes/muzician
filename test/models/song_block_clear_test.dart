import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('copyWith can clear saveId', () {
    final b = const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1')
        .copyWith(clearSaveId: true);
    expect(b.saveId, isNull);
  });

  test('copyWith can clear embedded', () {
    final b = const SongBlock(id: 'b', startBar: 0, spanBars: 1, saveId: 's1')
        .copyWith(clearEmbedded: true);
    expect(b.embedded, isNull);
    expect(b.saveId, 's1');
  });
}
