import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('section round-trips with lyrics field', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 8,
      order: 0,
      lyrics: 'Hello darkness my old friend\nIve come to talk',
    );
    final back = SongSection.fromJson(section.toJson());
    expect(back.lyrics, section.lyrics);
  });

  test('section defaults lyrics to null', () {
    const section = SongSection(id: 's2', lengthBars: 4, order: 0);
    expect(section.lyrics, isNull);
  });

  test('copyWith clears lyrics when clearLyrics: true', () {
    const section = SongSection(
      id: 's3',
      lengthBars: 4,
      order: 0,
      lyrics: 'first take',
    );
    final cleared = section.copyWith(clearLyrics: true);
    expect(cleared.lyrics, isNull);
  });

  test('copyWith preserves lyrics when not set', () {
    const section = SongSection(
      id: 's4',
      lengthBars: 4,
      order: 0,
      lyrics: 'verse one',
    );
    final next = section.copyWith(lengthBars: 8);
    expect(next.lyrics, 'verse one');
    expect(next.lengthBars, 8);
  });

  test('fromJson tolerates missing lyrics key', () {
    final back = SongSection.fromJson({
      'id': 's5',
      'lengthBars': 4,
      'order': 0,
    });
    expect(back.lyrics, isNull);
  });
}
