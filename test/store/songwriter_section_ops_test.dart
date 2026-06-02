import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rename, resize, repeat, remove a section', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final id = c.read(songwriterProvider).sections.single.id;

    n.renameSection(id, 'Verse');
    n.setSectionLength(id, 16);
    n.setSectionRepeat(id, 2);
    var s = c.read(songwriterProvider).sections.single;
    expect(s.label, 'Verse');
    expect(s.lengthBars, 16);
    expect(s.repeat, 2);

    n.removeSection(id);
    expect(c.read(songwriterProvider).sections, isEmpty);
  });

  test('reorderSections moves a section and renumbers order', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'A', lengthBars: 4);
    n.addSection(label: 'B', lengthBars: 4);
    n.addSection(label: 'C', lengthBars: 4);
    n.reorderSections(2, 0);
    expect(c.read(songwriterProvider).sections.map((s) => s.label).toList(),
        ['C', 'A', 'B']);
    expect(c.read(songwriterProvider).sections.map((s) => s.order).toList(),
        [0, 1, 2]);
  });

  test('renameSection(null) clears the label', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'X', lengthBars: 4);
    final id = c.read(songwriterProvider).sections.single.id;
    n.renameSection(id, null);
    expect(c.read(songwriterProvider).sections.single.label, isNull);
  });
}
