import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setSectionLyrics writes lyrics on the target section only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    notifier.addSection(label: 'Chorus', lengthBars: 4);

    final verseId = container.read(songwriterProvider).sections.first.id;
    final chorusId = container.read(songwriterProvider).sections.last.id;

    notifier.setSectionLyrics(verseId, 'line one\nline two');

    final state = container.read(songwriterProvider);
    expect(state.sections.first.lyrics, 'line one\nline two');
    expect(state.sections.last.lyrics, isNull);
    expect(state.sections.last.id, chorusId);
  });

  test('setSectionLyrics with null clears lyrics', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final id = container.read(songwriterProvider).sections.first.id;

    notifier.setSectionLyrics(id, 'temp');
    notifier.setSectionLyrics(id, null);

    expect(container.read(songwriterProvider).sections.first.lyrics, isNull);
  });

  test('setSectionLyrics is a no-op when sectionId is unknown', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final before = container.read(songwriterProvider);

    notifier.setSectionLyrics('nonexistent', 'ignored');

    final after = container.read(songwriterProvider);
    expect(after.sections.length, before.sections.length);
    expect(after.sections.first.lyrics, isNull);
  });
}
