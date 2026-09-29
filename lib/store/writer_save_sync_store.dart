/// Shared serialization and crash-recovery queue for Writer save transactions.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/save_system.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';

/// True while a Writer-created project is being prepared, written, and
/// published as one staged transaction.
final writerProjectWriteFenceProvider = StateProvider<bool>((_) => false);

const writerSaveSyncJournalStorageKey = '@muzician/writer_save_sync/v1';

/// The only storage operations used by the shared persistence queue.
///
/// Keeping this small interface injectable lets the store tests simulate a
/// process stop at each journal boundary.
abstract interface class WriterSaveSyncStorage {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
  Future<bool> remove(String key);
}

class SharedPreferencesWriterSaveSyncStorage implements WriterSaveSyncStorage {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<bool> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(key, value);
  }

  @override
  Future<bool> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove(key);
  }
}

final writerSaveSyncStorageProvider = Provider<WriterSaveSyncStorage>(
  (ref) => SharedPreferencesWriterSaveSyncStorage(),
);

/// A validated, roll-forward transaction journal.
class WriterSaveSyncJournal {
  final String projectId;
  final String saveSystemPayload;
  final String writerDraftsPayload;
  final String writerBindingsPayload;

  const WriterSaveSyncJournal({
    required this.projectId,
    required this.saveSystemPayload,
    required this.writerDraftsPayload,
    required this.writerBindingsPayload,
  });

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'saveSystem': saveSystemPayload,
    'writerDrafts': writerDraftsPayload,
    'writerBindings': writerBindingsPayload,
  };

  String encode() => jsonEncode(toJson());

  static WriterSaveSyncJournal? decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final projectId = json['projectId'] as String?;
      final saveSystemPayload = json['saveSystem'] as String?;
      final writerDraftsPayload = json['writerDrafts'] as String?;
      final writerBindingsPayload = json['writerBindings'] as String?;
      if (projectId == null ||
          projectId.isEmpty ||
          saveSystemPayload == null ||
          writerDraftsPayload == null ||
          writerBindingsPayload == null ||
          !_isValidSaveSystemPayload(saveSystemPayload) ||
          !_isValidWriterDraftsPayload(writerDraftsPayload) ||
          !_isValidWriterBindingsPayload(writerBindingsPayload)) {
        return null;
      }
      return WriterSaveSyncJournal(
        projectId: projectId,
        saveSystemPayload: saveSystemPayload,
        writerDraftsPayload: writerDraftsPayload,
        writerBindingsPayload: writerBindingsPayload,
      );
    } catch (_) {
      return null;
    }
  }
}

bool _isValidSaveSystemPayload(String raw) => deserialiseState(raw) != null;

bool _isValidWriterDraftsPayload(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    for (final value in json.values) {
      SongwriterProjectSnapshot.fromJson(value as Map<String, dynamic>);
    }
    return true;
  } catch (_) {
    return false;
  }
}

bool _isValidWriterBindingsPayload(String raw) {
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    for (final value in json.values) {
      final binding = value as Map<String, dynamic>;
      binding['activeSaveId'] as String?;
      binding['alwaysOverwrite'] as bool?;
      binding['materializedBaselineJson'] as String?;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Returns true only when [raw] is a complete transaction journal.
bool isValidWriterSaveSyncJournal(String raw) =>
    WriterSaveSyncJournal.decode(raw) != null;

class WriterSaveSyncNotifier extends Notifier<bool> {
  late WriterSaveSyncStorage _storage;
  Future<void> _tail = Future<void>.value();
  bool _storageNeedsRecovery = false;

  /// True after a failed transaction until a journal replay checks storage.
  @override
  bool build() {
    _storage = ref.read(writerSaveSyncStorageProvider);
    return false;
  }

  /// Commits in-memory state synchronously, then persists its captured payloads
  /// in journal → Save System → Writer draft → bindings → journal removal order.
  ///
  /// The caller prepares each immutable next value before invoking this method.
  /// [commitMemory] must only assign those prepared values and must not enqueue
  /// persistence itself.
  Future<void> commitWriterTransaction({
    required String projectId,
    required SaveSystemState saveSystemState,
    required Map<String, SongwriterProjectSnapshot> writerDrafts,
    required Map<String, Map<String, dynamic>> writerBindings,
    required void Function() commitMemory,
  }) {
    if (ref.read(writerProjectWriteFenceProvider)) {
      return Future<void>.error(
        StateError('Writer project writes are fenced during project creation.'),
      );
    }
    final journal = WriterSaveSyncJournal(
      projectId: projectId,
      saveSystemPayload: serialiseSaveSystemState(saveSystemState),
      writerDraftsPayload: jsonEncode(
        writerDrafts.map((key, value) => MapEntry(key, value.toJson())),
      ),
      writerBindingsPayload: jsonEncode(writerBindings),
    );

    // Queue the transaction before assigning state so any synchronous store
    // listeners append their writes after its journal. No storage work can run
    // until this synchronous method returns to the event loop.
    final completion = _enqueue(() => _writeTransaction(journal));
    commitMemory();
    return completion;
  }

  /// Persists a prepared project switch before publishing its in-memory state.
  /// A failed write before journal acceptance leaves memory untouched. Once
  /// the journal is accepted, failures roll forward by replaying that exact
  /// payload; failed replay leaves the caller's fence in place for recovery.
  Future<void> commitWriterTransactionAfterPersist({
    required String projectId,
    required SaveSystemState saveSystemState,
    required Map<String, SongwriterProjectSnapshot> writerDrafts,
    required Map<String, Map<String, dynamic>> writerBindings,
    required void Function() commitMemory,
  }) async {
    if (!ref.read(writerProjectWriteFenceProvider)) {
      throw StateError('A project write fence is required for staged commit.');
    }
    final journal = _makeJournal(
      projectId: projectId,
      saveSystemState: saveSystemState,
      writerDrafts: writerDrafts,
      writerBindings: writerBindings,
    );
    var accepted = false;
    try {
      await _enqueue(
        () => _writeTransaction(journal, onAccepted: () => accepted = true),
      );
    } catch (error) {
      if (!accepted) rethrow;
      try {
        await replayPendingTransaction();
      } catch (replayError) {
        Error.throwWithStackTrace(
          StateError(
            'Writer project transaction was accepted but recovery failed: '
            '$replayError',
          ),
          StackTrace.current,
        );
      }
    }
    commitMemory();
  }

  WriterSaveSyncJournal _makeJournal({
    required String projectId,
    required SaveSystemState saveSystemState,
    required Map<String, SongwriterProjectSnapshot> writerDrafts,
    required Map<String, Map<String, dynamic>> writerBindings,
  }) => WriterSaveSyncJournal(
    projectId: projectId,
    saveSystemPayload: serialiseSaveSystemState(saveSystemState),
    writerDraftsPayload: jsonEncode(
      writerDrafts.map((key, value) => MapEntry(key, value.toJson())),
    ),
    writerBindingsPayload: jsonEncode(writerBindings),
  );

  /// Adds an ordinary Save System write to the same queue as Writer commits.
  Future<void> persistSaveSystem(String payload) =>
      ref.read(writerProjectWriteFenceProvider)
      ? Future<void>.value()
      : _enqueue(() => _writeString(saveSystemStorageKey, payload));

  /// Adds an ordinary Writer draft write to the shared queue.
  Future<void> persistWriterDrafts(String payload) =>
      ref.read(writerProjectWriteFenceProvider)
      ? Future<void>.value()
      : _enqueue(() => _writeString(songwriterSessionsStorageKey, payload));

  /// Removes the Writer draft key through the shared queue.
  Future<void> removeWriterDrafts() => ref.read(writerProjectWriteFenceProvider)
      ? Future<void>.value()
      : _enqueue(() => _remove(songwriterSessionsStorageKey));

  /// Adds an ordinary named-save binding write to the shared queue.
  Future<void> persistWriterBindings(String payload) =>
      ref.read(writerProjectWriteFenceProvider)
      ? Future<void>.value()
      : _enqueue(() => _writeString(writerSaveBindingsStorageKey, payload));

  /// Waits for every storage operation already admitted to the shared queue.
  Future<void> drain() => _tail;

  /// Replays a pending transaction before store hydration exposes workspaces.
  /// A missing journal means no complete transaction was durably accepted.
  Future<void> replayPendingTransaction() => _enqueue(() async {
    try {
      final raw = await _storage.read(writerSaveSyncJournalStorageKey);
      if (raw == null) {
        _storageNeedsRecovery = false;
        state = false;
        return;
      }
      final journal = WriterSaveSyncJournal.decode(raw);
      if (journal == null) {
        throw const FormatException('Invalid Writer save transaction journal.');
      }
      await _applyTransaction(journal);
      await _remove(writerSaveSyncJournalStorageKey);
      _storageNeedsRecovery = false;
      state = false;
    } catch (_) {
      _storageNeedsRecovery = true;
      state = true;
      rethrow;
    }
  }, allowRecovery: true);

  Future<void> _writeTransaction(
    WriterSaveSyncJournal journal, {
    void Function()? onAccepted,
  }) async {
    var accepted = false;
    try {
      await _writeString(writerSaveSyncJournalStorageKey, journal.encode());
      accepted = true;
      onAccepted?.call();
      _storageNeedsRecovery = true;
      state = true;
      await _applyTransaction(journal);
      await _remove(writerSaveSyncJournalStorageKey);
      _storageNeedsRecovery = false;
      state = false;
    } catch (_) {
      _storageNeedsRecovery = accepted;
      state = accepted;
      rethrow;
    }
  }

  Future<void> _applyTransaction(WriterSaveSyncJournal journal) async {
    await _writeString(saveSystemStorageKey, journal.saveSystemPayload);
    await _writeString(
      songwriterSessionsStorageKey,
      journal.writerDraftsPayload,
    );
    await _writeString(
      writerSaveBindingsStorageKey,
      journal.writerBindingsPayload,
    );
  }

  Future<void> _writeString(String key, String value) async {
    if (!await _storage.write(key, value)) {
      throw StateError('Could not persist $key.');
    }
  }

  Future<void> _remove(String key) async {
    if (!await _storage.remove(key)) {
      throw StateError('Could not remove $key.');
    }
  }

  Future<void> _enqueue(
    Future<void> Function() operation, {
    bool allowRecovery = false,
  }) {
    final next = _tail.then((_) async {
      if (_storageNeedsRecovery && !allowRecovery) {
        throw StateError(
          'Writer save storage needs recovery before more writes can run.',
        );
      }
      await operation();
    });
    // Keep the queue usable after an individual caller receives an error.
    // The storage-recovery flag blocks unsafe ordinary writes until replay.
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

const songwriterSessionsStorageKey = '@muzician/songwriter_sessions/v1';
const writerSaveBindingsStorageKey = '@muzician/writer_save_bindings/v1';

final writerSaveSyncProvider = NotifierProvider<WriterSaveSyncNotifier, bool>(
  WriterSaveSyncNotifier.new,
);
