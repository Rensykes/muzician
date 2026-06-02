import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  test('hydrate restores a persisted session', () async {
    SharedPreferences.setMockInitialValues({});

    // First container: add a section, let the debounce flush.
    final c1 = ProviderContainer();
    c1.read(songwriterProvider.notifier).addSection(label: 'Chorus', lengthBars: 8);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    c1.dispose();

    // Second container: hydrate from the same mock prefs.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    await c2.read(songwriterProvider.notifier).hydrate();
    final sections = c2.read(songwriterProvider).sections;
    expect(sections.single.label, 'Chorus');
  });
}
