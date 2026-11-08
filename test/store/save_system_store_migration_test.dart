import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legacyKeys = [
  '@muzician/save-system/v2',
  '@muzician/song_session/v1',
  '@muzician/songwriter_session/v1',
];
const _newKey = '@muzician/save-system/v3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy v2 / session blobs are wiped on first hydrate; v3 written',
    () async {
      SharedPreferences.setMockInitialValues({
        '@muzician/save-system/v2': jsonEncode({'folders': [], 'saves': []}),
        '@muzician/song_session/v1': jsonEncode({'config': {}}),
        '@muzician/songwriter_session/v1': jsonEncode({'name': 'x'}),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(saveSystemProvider.notifier).hydrate();

      final prefs = await SharedPreferences.getInstance();
      for (final key in _legacyKeys) {
        expect(prefs.containsKey(key), isFalse, reason: '$key should be wiped');
      }
      expect(
        prefs.containsKey(_newKey),
        isTrue,
        reason: 'v3 blob must be written',
      );

      final state = container.read(saveSystemProvider);
      expect(state.folders, isEmpty);
      expect(state.saves, isEmpty);
      expect(state.selectedProjectId, isNull);
      expect(state.hydrated, isTrue);
    },
  );

  test('v3 blob present: hydrate restores; no wipe', () async {
    SharedPreferences.setMockInitialValues({
      _newKey: jsonEncode({
        'folders': [],
        'saves': [],
        'selectedProjectId': null,
      }),
      '@muzician/save-system/v2': jsonEncode({'folders': [], 'saves': []}),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(saveSystemProvider.notifier).hydrate();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.containsKey('@muzician/save-system/v2'),
      isTrue,
      reason: 'legacy key retained when v3 already exists',
    );
  });

  test('hydrate persists the removal of Song saves', () async {
    SharedPreferences.setMockInitialValues({
      _newKey: jsonEncode({
        'folders': [],
        'saves': [
          {
            'id': 'song-1',
            'name': 'Old Song',
            'folderId': 'f',
            'snapshot': {'type': 'song', 'instrument': 'song', 'project': {}},
            'createdAt': 0,
            'updatedAt': 0,
            'order': 0,
          },
          {
            'id': 'keep-1',
            'name': 'Keep',
            'folderId': 'f',
            'snapshot': {
              'type': 'fretboard',
              'instrument': 'fretboard',
              'tuning': 'standard',
              'numFrets': 12,
              'capo': 0,
              'selectedCells': [],
              'selectedNotes': [],
              'viewMode': 'exact',
            },
            'createdAt': 0,
            'updatedAt': 0,
            'order': 1,
          },
        ],
        'selectedProjectId': null,
      }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(saveSystemProvider.notifier).hydrate();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_newKey)!;
    expect(raw.contains('song-1'), isFalse);
    expect(raw.contains('keep-1'), isTrue);
  });

  test('removed Song audio is wiped and Writer audio survives', () async {
    final root = Directory.systemTemp.createTempSync('audio_cleanup_');
    addTearDown(() => root.deleteSync(recursive: true));
    final songDir = Directory('${root.path}/song_audio')..createSync();
    File('${songDir.path}/take.wav').writeAsStringSync('song');
    final songTmp = Directory('${root.path}/song_audio_tmp')..createSync();
    final writerDir = Directory('${root.path}/songwriter_audio')..createSync();
    final writerFile = File('${writerDir.path}/take.wav')
      ..writeAsStringSync('writer');

    expect(
      await wipeRemovedSongAudioDir(documentsDirectory: () async => root),
      isTrue,
    );

    expect(songDir.existsSync(), isFalse);
    expect(songTmp.existsSync(), isFalse);
    expect(writerFile.existsSync(), isTrue);

    expect(
      await wipeRemovedSongAudioDir(
        documentsDirectory: () async => throw StateError('no docs'),
      ),
      isFalse,
    );
  });
}
