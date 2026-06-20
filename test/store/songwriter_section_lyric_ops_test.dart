import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setSectionLyric writes per-verse text, growing the list as needed', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;

    // Write verse index 1 first — list grows with a leading empty entry.
    n.setSectionLyric(sectionId: s, verseIndex: 1, text: 'second verse');
    expect(c.read(songwriterProvider).sections.single.lyrics,
        ['', 'second verse']);

    n.setSectionLyric(sectionId: s, verseIndex: 0, text: 'first verse');
    expect(c.read(songwriterProvider).sections.single.lyrics,
        ['first verse', 'second verse']);
  });

  test('clearing the last verse trims trailing empties', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;
    n.setSectionLyric(sectionId: s, verseIndex: 0, text: 'a');
    n.setSectionLyric(sectionId: s, verseIndex: 1, text: 'b');

    n.setSectionLyric(sectionId: s, verseIndex: 1, text: '');
    expect(c.read(songwriterProvider).sections.single.lyrics, ['a']);
  });

  test('negative verse index is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final s = c.read(songwriterProvider).sections.single.id;
    n.setSectionLyric(sectionId: s, verseIndex: -1, text: 'nope');
    expect(c.read(songwriterProvider).sections.single.lyrics, isEmpty);
  });
}
