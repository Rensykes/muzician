import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:muzician/store/writer_save_sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements WriterSaveSyncStorage {
  final values = <String, String>{};
  int? failAtOperation;
  int _operation = 0;

  void failAt(int operation) {
    _operation = 0;
    failAtOperation = operation;
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (_shouldFail()) throw StateError('simulated interrupted write');
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (_shouldFail()) throw StateError('simulated interrupted remove');
    values.remove(key);
    return true;
  }

  bool _shouldFail() {
    final operation = _operation++;
    if (operation != failAtOperation) return false;
    failAtOperation = null;
    return true;
  }
}

SongwriterProjectSnapshot _draft(String name, {int tempo = 120}) =>
    SongwriterProjectSnapshot(
      name: name,
      config: SongwriterConfig(tempo: tempo, beatsPerBar: 4, beatUnit: 4),
    );

String _encodeDrafts(Map<String, SongwriterProjectSnapshot> drafts) =>
    jsonEncode(drafts.map((key, value) => MapEntry(key, value.toJson())));

String _encodeBindings(Map<String, WriterSaveBinding> bindings) =>
    jsonEncode(bindings.map((key, value) => MapEntry(key, value.toJson())));

ProviderContainer _container(_MemoryStorage storage) => ProviderContainer(
  overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'deleting the selected project clears its Writer draft and binding',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _MemoryStorage();
      final container = _container(storage);
      addTearDown(container.dispose);

      final saveSystem = container.read(saveSystemProvider.notifier);
      await saveSystem.hydrate();
      final deletedId = saveSystem.createProject(
        'Delete me',
        const ProjectConfig(),
      )!;
      final retainedId = saveSystem.createProject(
        'Keep me',
        const ProjectConfig(),
      )!;
      container.read(songwriterProvider.notifier);
      saveSystem.selectProject(deletedId);

      final sessions = container.read(songwriterSessionsProvider.notifier);
      sessions.commitState({
        deletedId: _draft('Deleted draft', tempo: 133),
        retainedId: _draft('Retained draft', tempo: 88),
      });
      final bindings = container.read(writerSaveBindingProvider.notifier);
      bindings.commitState({
        deletedId: const WriterSaveBinding(activeSaveId: 'deleted-save'),
        retainedId: const WriterSaveBinding(activeSaveId: 'retained-save'),
      });

      await saveSystem.deleteProject(deletedId);

      expect(container.read(saveSystemProvider).selectedProjectId, isNull);
      expect(
        container.read(songwriterSessionsProvider).containsKey(deletedId),
        isFalse,
      );
      expect(
        container.read(writerSaveBindingProvider).containsKey(deletedId),
        isFalse,
      );
      expect(
        container.read(songwriterSessionsProvider)[retainedId]?.name,
        'Retained draft',
      );
      expect(
        container.read(writerSaveBindingProvider)[retainedId]?.activeSaveId,
        'retained-save',
      );
      expect(
        (jsonDecode(storage.values[songwriterSessionsStorageKey]!)
                as Map<String, dynamic>)
            .containsKey(deletedId),
        isFalse,
      );
      expect(
        (jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
                as Map<String, dynamic>)
            .containsKey(deletedId),
        isFalse,
      );
    },
  );

  test(
    'unselected project deletion rolls forward through journal replay',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _MemoryStorage();
      final container = _container(storage);
      addTearDown(container.dispose);

      final saveSystem = container.read(saveSystemProvider.notifier);
      await saveSystem.hydrate();
      final deletedId = saveSystem.createProject(
        'Delete me',
        const ProjectConfig(),
      )!;
      final selectedId = saveSystem.createProject(
        'Keep selected',
        const ProjectConfig(),
      )!;
      container.read(songwriterProvider.notifier);
      saveSystem.selectProject(selectedId);

      final sessions = <String, SongwriterProjectSnapshot>{
        deletedId: _draft('Deleted draft'),
        selectedId: _draft('Selected draft', tempo: 98),
      };
      final bindings = <String, WriterSaveBinding>{
        deletedId: const WriterSaveBinding(activeSaveId: 'deleted-save'),
        selectedId: const WriterSaveBinding(activeSaveId: 'selected-save'),
      };
      container.read(songwriterSessionsProvider.notifier).commitState(sessions);
      container.read(writerSaveBindingProvider.notifier).commitState(bindings);

      // Seed the last committed payloads, then interrupt after the Save System
      // write while the journal still owns the complete deletion transaction.
      await container
          .read(writerSaveSyncProvider.notifier)
          .persistSaveSystem(
            serialiseSaveSystemState(container.read(saveSystemProvider)),
          );
      storage.values[songwriterSessionsStorageKey] = _encodeDrafts(sessions);
      storage.values[writerSaveBindingsStorageKey] = _encodeBindings(bindings);
      storage.failAt(2);

      await expectLater(saveSystem.deleteProject(deletedId), throwsStateError);
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isTrue,
      );
      expect(container.read(saveSystemProvider).selectedProjectId, selectedId);
      expect(
        container.read(songwriterSessionsProvider).containsKey(deletedId),
        isFalse,
      );
      expect(
        container.read(writerSaveBindingProvider).containsKey(deletedId),
        isFalse,
      );

      final relaunched = _container(storage);
      addTearDown(relaunched.dispose);
      await relaunched
          .read(writerSaveSyncProvider.notifier)
          .replayPendingTransaction();

      final recoveredSaveSystem = deserialiseState(
        storage.values[saveSystemStorageKey]!,
      )!;
      expect(recoveredSaveSystem.selectedProjectId, selectedId);
      expect(
        recoveredSaveSystem.folders.any((folder) => folder.id == deletedId),
        isFalse,
      );
      expect(
        (jsonDecode(storage.values[songwriterSessionsStorageKey]!)
                as Map<String, dynamic>)
            .containsKey(deletedId),
        isFalse,
      );
      expect(
        (jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
                as Map<String, dynamic>)
            .containsKey(deletedId),
        isFalse,
      );
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isFalse,
      );
    },
  );
}
