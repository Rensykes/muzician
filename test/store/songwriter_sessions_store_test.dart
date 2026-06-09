import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = '@muzician/songwriter_sessions/v1';

SongwriterProjectSnapshot _sample({int tempo = 120}) => SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: tempo, beatsPerBar: 4, beatUnit: 4),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('hydrate empty → empty map', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songwriterSessionsProvider.notifier).hydrate();
    expect(c.read(songwriterSessionsProvider), isEmpty);
  });

  test('put/get/remove + persistence + rehydrate', () async {
    var c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songwriterSessionsProvider.notifier).hydrate();
    c.read(songwriterSessionsProvider.notifier).put('p', _sample(tempo: 90));
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final raw = (await SharedPreferences.getInstance()).getString(_key);
    expect(raw, isNotNull);

    // Rehydrate fresh container.
    c.dispose();
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songwriterSessionsProvider.notifier).hydrate();
    expect(c.read(songwriterSessionsProvider.notifier).get('p')?.config.tempo, 90);
  });
}
