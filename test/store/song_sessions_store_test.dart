import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/piano_roll.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/song_sessions_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = '@muzician/song_sessions/v1';

SongProject _sample({int tempo = 120}) => SongProject(
      config: SongProjectConfig(
        tempo: tempo,
        timeSignature: const TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
        totalMeasures: 4,
      ),
      tracks: const [],
      clips: const [],
      notePatterns: const [],
      drumPatterns: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('hydrate empty → empty map', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songSessionsProvider.notifier).hydrate();
    expect(c.read(songSessionsProvider), isEmpty);
  });

  test('put/get/remove + persistence', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songSessionsProvider.notifier).hydrate();

    c.read(songSessionsProvider.notifier).put('proj-1', _sample(tempo: 96));
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(c.read(songSessionsProvider.notifier).get('proj-1')?.config.tempo, 96);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    expect(raw, isNotNull);
    final parsed = jsonDecode(raw!) as Map<String, dynamic>;
    expect((parsed['proj-1'] as Map<String, dynamic>)['config']['tempo'], 96);

    c.read(songSessionsProvider.notifier).remove('proj-1');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(c.read(songSessionsProvider.notifier).get('proj-1'), isNull);
  });

  test('hydrate restores map from disk', () async {
    final init = <String, Object>{
      _key: jsonEncode({'proj-x': _sample(tempo: 88).toJson()}),
    };
    SharedPreferences.setMockInitialValues(init);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(songSessionsProvider.notifier).hydrate();
    expect(c.read(songSessionsProvider.notifier).get('proj-x')?.config.tempo, 88);
  });
}
