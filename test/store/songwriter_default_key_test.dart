import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh project defaults to C major', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cfg = c.read(songwriterProvider).config;
    expect(cfg.keyRoot, 0);
    expect(cfg.keyScaleName, 'major');
  });

  test('newProject resets to C major', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.setKey(null, null); // clear
    await n.newProject();
    final cfg = c.read(songwriterProvider).config;
    expect(cfg.keyRoot, 0);
    expect(cfg.keyScaleName, 'major');
  });
}
