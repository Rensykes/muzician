import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/store/songwriter_store.dart';

AudioAsset _asset(String id) => AudioAsset(
  id: id,
  durationMs: 1000,
  sampleRate: 44100,
  channels: 1,
  format: 'wav',
  peaks: const [1, 2],
  sourceLabel: 'Recording',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('addAudioAsset appends the asset', () {
    c.read(songwriterProvider.notifier).addAudioAsset(_asset('a1'));
    expect(c.read(songwriterProvider).audioAssets.single.id, 'a1');
  });

  test('addAudioAsset replaces an existing asset with the same id', () {
    final n = c.read(songwriterProvider.notifier);
    n.addAudioAsset(_asset('a1'));
    n.addAudioAsset(_asset('a1').copyWith(sourceLabel: 'Imported'));
    final assets = c.read(songwriterProvider).audioAssets;
    expect(assets.length, 1);
    expect(assets.single.sourceLabel, 'Imported');
  });
}
