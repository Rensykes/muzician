import 'dart:convert';

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

  test('legacy v2 / session blobs are wiped on first hydrate; v3 written', () async {
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
    expect(prefs.containsKey(_newKey), isTrue, reason: 'v3 blob must be written');

    final state = container.read(saveSystemProvider);
    expect(state.folders, isEmpty);
    expect(state.saves, isEmpty);
    expect(state.selectedProjectId, isNull);
    expect(state.hydrated, isTrue);
  });

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
    expect(prefs.containsKey('@muzician/save-system/v2'), isTrue,
        reason: 'legacy key retained when v3 already exists');
  });
}
