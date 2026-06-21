import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('section lyrics round-trip through JSON', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 8,
      order: 0,
      repeat: 2,
      lyrics: ['verse one', 'verse two'],
    );
    final restored = SongSection.fromJson(section.toJson());
    expect(restored.lyrics, ['verse one', 'verse two']);
  });

  test('section lyrics default to empty and survive copyWith', () {
    const section = SongSection(id: 's1', lengthBars: 4, order: 0);
    expect(section.lyrics, isEmpty);
    final updated = section.copyWith(lyrics: ['hi']);
    expect(updated.lyrics, ['hi']);
    // copyWith without lyrics preserves them.
    expect(updated.copyWith(label: 'V').lyrics, ['hi']);
  });

  test('missing lyrics key in JSON decodes to empty list', () {
    final restored = SongSection.fromJson({
      'id': 's1',
      'lengthBars': 4,
      'order': 0,
    });
    expect(restored.lyrics, isEmpty);
  });
}
