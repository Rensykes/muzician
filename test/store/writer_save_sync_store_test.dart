import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';
import 'package:muzician/store/writer_save_sync_store.dart';

class _MemoryStorage implements WriterSaveSyncStorage {
  final values = <String, String>{};
  final events = <String>[];
  int? failAtOperation;
  int? failAlsoAtOperation;
  Completer<void>? journalGate;
  Completer<void>? journalWriteStarted;
  int _operation = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    events.add('write:$key');
    if (key == writerSaveSyncJournalStorageKey && journalGate != null) {
      if (!(journalWriteStarted?.isCompleted ?? true)) {
        journalWriteStarted!.complete();
      }
      await journalGate!.future;
    }
    if (_shouldFail()) throw StateError('simulated interrupted write');
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    events.add('remove:$key');
    if (_shouldFail()) throw StateError('simulated interrupted remove');
    values.remove(key);
    return true;
  }

  bool _shouldFail() {
    final operation = _operation++;
    final shouldFail =
        operation == failAtOperation || operation == failAlsoAtOperation;
    if (operation == failAtOperation) failAtOperation = null;
    if (operation == failAlsoAtOperation) failAlsoAtOperation = null;
    return shouldFail;
  }
}

SaveSystemState _saveState({String? selectedProjectId}) => SaveSystemState(
  folders: const [],
  saves: const [],
  hydrated: true,
  selectedProjectId: selectedProjectId,
);

SongwriterProjectSnapshot _draft(String name) => SongwriterProjectSnapshot(
  name: name,
  config: const SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
);

Map<String, SongwriterProjectSnapshot> get _drafts => {'p': _draft('Draft')};

Map<String, Map<String, dynamic>> get _bindings => {
  'p': {'activeSaveId': 'named-save', 'alwaysOverwrite': false},
};

ProviderContainer _container(_MemoryStorage storage) => ProviderContainer(
  overrides: [writerSaveSyncStorageProvider.overrideWithValue(storage)],
);

Future<void> _commit(ProviderContainer container) => container
    .read(writerSaveSyncProvider.notifier)
    .commitWriterTransaction(
      projectId: 'p',
      saveSystemState: _saveState(selectedProjectId: 'p'),
      writerDrafts: _drafts,
      writerBindings: _bindings,
      commitMemory: () {},
    );

void main() {
  test('Writer transaction writes journal and all payloads in order', () async {
    final storage = _MemoryStorage();
    final container = _container(storage);
    addTearDown(container.dispose);

    var committed = false;
    final saveState = _saveState(selectedProjectId: 'p');
    final completion = container
        .read(writerSaveSyncProvider.notifier)
        .commitWriterTransaction(
          projectId: 'p',
          saveSystemState: saveState,
          writerDrafts: _drafts,
          writerBindings: _bindings,
          commitMemory: () => committed = true,
        );

    expect(committed, isTrue);
    await completion;

    expect(storage.events, [
      'write:$writerSaveSyncJournalStorageKey',
      'write:$saveSystemStorageKey',
      'write:$songwriterSessionsStorageKey',
      'write:$writerSaveBindingsStorageKey',
      'remove:$writerSaveSyncJournalStorageKey',
    ]);
    expect(
      storage.values.containsKey(writerSaveSyncJournalStorageKey),
      isFalse,
    );
    expect(
      deserialiseState(
        storage.values[saveSystemStorageKey]!,
      )!.selectedProjectId,
      'p',
    );
    expect(
      (jsonDecode(storage.values[songwriterSessionsStorageKey]!)
          as Map<String, dynamic>)['p']['name'],
      'Draft',
    );
    expect(
      (jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
          as Map<String, dynamic>)['p']['alwaysOverwrite'],
      isFalse,
    );
  });

  for (var failedOperation = 0; failedOperation < 5; failedOperation++) {
    test(
      'replays after storage interruption at stage $failedOperation',
      () async {
        final storage = _MemoryStorage()
          ..failAtOperation = failedOperation
          ..values[saveSystemStorageKey] = serialiseSaveSystemState(
            _saveState(selectedProjectId: 'old'),
          )
          ..values[songwriterSessionsStorageKey] = jsonEncode({
            'p': _draft('Old draft').toJson(),
          })
          ..values[writerSaveBindingsStorageKey] = jsonEncode({
            'p': {'activeSaveId': 'old-save', 'alwaysOverwrite': true},
          });
        final interrupted = _container(storage);
        addTearDown(interrupted.dispose);

        await expectLater(_commit(interrupted), throwsStateError);
        expect(interrupted.read(writerSaveSyncProvider), failedOperation != 0);

        final relaunched = _container(storage);
        addTearDown(relaunched.dispose);
        await relaunched
            .read(writerSaveSyncProvider.notifier)
            .replayPendingTransaction();

        if (failedOperation == 0) {
          // The journal never completed, so this transaction was not accepted.
          expect(
            deserialiseState(
              storage.values[saveSystemStorageKey]!,
            )!.selectedProjectId,
            'old',
          );
          expect(
            SongwriterProjectSnapshot.fromJson(
              ((jsonDecode(storage.values[songwriterSessionsStorageKey]!)
                      as Map<String, dynamic>)['p']
                  as Map<String, dynamic>),
            ).name,
            'Old draft',
          );
          expect(
            ((jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
                    as Map<String, dynamic>)['p']
                as Map<String, dynamic>)['alwaysOverwrite'],
            isTrue,
          );
        } else {
          expect(
            storage.values.containsKey(writerSaveSyncJournalStorageKey),
            isFalse,
          );
          expect(
            deserialiseState(
              storage.values[saveSystemStorageKey]!,
            )!.selectedProjectId,
            'p',
          );
          expect(
            SongwriterProjectSnapshot.fromJson(
              ((jsonDecode(storage.values[songwriterSessionsStorageKey]!)
                      as Map<String, dynamic>)['p']
                  as Map<String, dynamic>),
            ).name,
            'Draft',
          );
          expect(
            ((jsonDecode(storage.values[writerSaveBindingsStorageKey]!)
                    as Map<String, dynamic>)['p']
                as Map<String, dynamic>)['alwaysOverwrite'],
            isFalse,
          );
        }
        expect(relaunched.read(writerSaveSyncProvider), isFalse);
      },
    );
  }

  test('ordinary writes wait behind the complete transaction', () async {
    final storage = _MemoryStorage();
    final container = _container(storage);
    addTearDown(container.dispose);

    final notifier = container.read(writerSaveSyncProvider.notifier);
    final first = notifier.commitWriterTransaction(
      projectId: 'p',
      saveSystemState: _saveState(selectedProjectId: 'p'),
      writerDrafts: _drafts,
      writerBindings: _bindings,
      commitMemory: () {},
    );
    final newerSaveState = _saveState(selectedProjectId: 'newer');
    final later = notifier.persistSaveSystem(
      serialiseSaveSystemState(newerSaveState),
    );

    await Future.wait([first, later]);
    expect(
      deserialiseState(
        storage.values[saveSystemStorageKey]!,
      )!.selectedProjectId,
      'newer',
    );
    expect(storage.events.last, 'write:$saveSystemStorageKey');
  });

  test(
    'staged transaction publishes only after its payloads are durable',
    () async {
      final storage = _MemoryStorage()
        ..journalGate = Completer<void>()
        ..journalWriteStarted = Completer<void>();
      final container = _container(storage);
      addTearDown(container.dispose);
      container.read(writerProjectWriteFenceProvider.notifier).state = true;
      var committed = false;

      final completion = container
          .read(writerSaveSyncProvider.notifier)
          .commitWriterTransactionAfterPersist(
            projectId: 'p',
            saveSystemState: _saveState(selectedProjectId: 'p'),
            writerDrafts: _drafts,
            writerBindings: _bindings,
            commitMemory: () => committed = true,
          );
      await storage.journalWriteStarted!.future;
      expect(committed, isFalse);
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isFalse,
      );

      storage.journalGate!.complete();
      await completion;
      expect(committed, isTrue);
      expect(container.read(writerProjectWriteFenceProvider), isTrue);
      expect(
        deserialiseState(
          storage.values[saveSystemStorageKey]!,
        )!.selectedProjectId,
        'p',
      );
    },
  );

  test('staged pre-acceptance failure leaves memory unpublished', () async {
    final storage = _MemoryStorage()..failAtOperation = 0;
    final container = _container(storage);
    addTearDown(container.dispose);
    container.read(writerProjectWriteFenceProvider.notifier).state = true;
    var committed = false;

    await expectLater(
      container
          .read(writerSaveSyncProvider.notifier)
          .commitWriterTransactionAfterPersist(
            projectId: 'p',
            saveSystemState: _saveState(selectedProjectId: 'p'),
            writerDrafts: _drafts,
            writerBindings: _bindings,
            commitMemory: () => committed = true,
          ),
      throwsStateError,
    );
    expect(committed, isFalse);
    expect(container.read(writerSaveSyncProvider), isFalse);
    expect(
      storage.values.containsKey(writerSaveSyncJournalStorageKey),
      isFalse,
    );
  });

  test('staged accepted failure replays before publishing memory', () async {
    final storage = _MemoryStorage()..failAtOperation = 2;
    final container = _container(storage);
    addTearDown(container.dispose);
    container.read(writerProjectWriteFenceProvider.notifier).state = true;
    var committed = false;

    await container
        .read(writerSaveSyncProvider.notifier)
        .commitWriterTransactionAfterPersist(
          projectId: 'p',
          saveSystemState: _saveState(selectedProjectId: 'p'),
          writerDrafts: _drafts,
          writerBindings: _bindings,
          commitMemory: () => committed = true,
        );

    expect(committed, isTrue);
    expect(container.read(writerSaveSyncProvider), isFalse);
    expect(container.read(writerProjectWriteFenceProvider), isTrue);
    expect(
      storage.values.containsKey(writerSaveSyncJournalStorageKey),
      isFalse,
    );
    expect(
      (jsonDecode(storage.values[songwriterSessionsStorageKey]!)
          as Map<String, dynamic>)['p']['name'],
      'Draft',
    );
  });

  test(
    'staged failed replay leaves the caller fence and memory untouched',
    () async {
      final storage = _MemoryStorage()
        ..failAtOperation = 2
        ..failAlsoAtOperation = 3;
      final container = _container(storage);
      addTearDown(container.dispose);
      container.read(writerProjectWriteFenceProvider.notifier).state = true;
      var committed = false;

      await expectLater(
        container
            .read(writerSaveSyncProvider.notifier)
            .commitWriterTransactionAfterPersist(
              projectId: 'p',
              saveSystemState: _saveState(selectedProjectId: 'p'),
              writerDrafts: _drafts,
              writerBindings: _bindings,
              commitMemory: () => committed = true,
            ),
        throwsStateError,
      );
      expect(committed, isFalse);
      expect(container.read(writerSaveSyncProvider), isTrue);
      expect(container.read(writerProjectWriteFenceProvider), isTrue);
      expect(
        storage.values.containsKey(writerSaveSyncJournalStorageKey),
        isTrue,
      );
    },
  );
}
