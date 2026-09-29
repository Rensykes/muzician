library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/save_system.dart';
import 'persisted_data_recovery_store.dart';
import 'save_system_store.dart';
import 'songwriter_store.dart';
import 'writer_save_sync_store.dart' as writer_sync;
export 'writer_save_sync_store.dart' show writerSaveBindingsStorageKey;

const _kDebounce = Duration(milliseconds: 500);

/// Per-project link between the live Writer project and a named [SaveEntry].
class WriterSaveBinding {
  final String? activeSaveId;
  final bool alwaysOverwrite;
  final String? materializedBaselineJson;

  const WriterSaveBinding({
    this.activeSaveId,
    this.alwaysOverwrite = false,
    this.materializedBaselineJson,
  });

  WriterSaveBinding copyWith({
    String? activeSaveId,
    bool? alwaysOverwrite,
    String? materializedBaselineJson,
  }) => WriterSaveBinding(
    activeSaveId: activeSaveId ?? this.activeSaveId,
    alwaysOverwrite: alwaysOverwrite ?? this.alwaysOverwrite,
    materializedBaselineJson:
        materializedBaselineJson ?? this.materializedBaselineJson,
  );

  Map<String, dynamic> toJson() => {
    'activeSaveId': activeSaveId,
    'alwaysOverwrite': alwaysOverwrite,
    if (materializedBaselineJson != null)
      'materializedBaselineJson': materializedBaselineJson,
  };

  factory WriterSaveBinding.fromJson(Map<String, dynamic> json) =>
      WriterSaveBinding(
        activeSaveId: json['activeSaveId'] as String?,
        alwaysOverwrite: json['alwaysOverwrite'] as bool? ?? false,
        materializedBaselineJson: json['materializedBaselineJson'] as String?,
      );
}

class WriterSaveBindingNotifier
    extends Notifier<Map<String, WriterSaveBinding>> {
  Timer? _debounce;
  bool _hydrated = false;
  bool _projectWritesPaused = false;

  @override
  Map<String, WriterSaveBinding> build() {
    ref.onDispose(() => _debounce?.cancel());
    return const {};
  }

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(writer_sync.writerSaveBindingsStorageKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = map.map(
          (k, v) => MapEntry(
            k,
            WriterSaveBinding.fromJson(v as Map<String, dynamic>),
          ),
        );
        state = parsed;
      } catch (_) {
        throw MalformedPersistedPayload(
          storageKey: writer_sync.writerSaveBindingsStorageKey,
          raw: raw,
        );
      }
    }
    _hydrated = true;
  }

  /// Applies bindings captured by a shared Writer transaction and discards any
  /// older debounced write.
  void commitState(Map<String, WriterSaveBinding> next) {
    _debounce?.cancel();
    _debounce = null;
    state = Map.unmodifiable(next);
  }

  /// Binds [projectId] to [saveId] and RESETS alwaysOverwrite. Called on load
  /// and on save (new or save-as-new).
  void bind(String projectId, String saveId) {
    if (_projectWritesPaused ||
        ref.read(writer_sync.writerProjectWriteFenceProvider)) {
      return;
    }
    state = {...state, projectId: WriterSaveBinding(activeSaveId: saveId)};
    _schedulePersist();
  }

  void setAlwaysOverwrite(String projectId, bool value) {
    if (_projectWritesPaused ||
        ref.read(writer_sync.writerProjectWriteFenceProvider)) {
      return;
    }
    final cur = state[projectId] ?? const WriterSaveBinding();
    state = {...state, projectId: cur.copyWith(alwaysOverwrite: value)};
    _schedulePersist();
  }

  void clear(String projectId) {
    if (_projectWritesPaused ||
        ref.read(writer_sync.writerProjectWriteFenceProvider)) {
      return;
    }
    final next = {...state}..remove(projectId);
    state = next;
    _schedulePersist();
  }

  void pauseProjectWrites() {
    _projectWritesPaused = true;
    _debounce?.cancel();
    _debounce = null;
  }

  void resumeProjectWrites({bool persistCurrent = true}) {
    _projectWritesPaused = false;
    if (persistCurrent) _schedulePersist();
  }

  void _schedulePersist() {
    if (_projectWritesPaused ||
        ref.read(writer_sync.writerProjectWriteFenceProvider)) {
      return;
    }
    _debounce?.cancel();
    final snapshot = state;
    _debounce = Timer(_kDebounce, () {
      _debounce = null;
      ref
          .read(writer_sync.writerSaveSyncProvider.notifier)
          .persistWriterBindings(_serialiseBindings(snapshot));
    });
  }
}

String _serialiseBindings(Map<String, WriterSaveBinding> bindings) =>
    jsonEncode(bindings.map((k, v) => MapEntry(k, v.toJson())));

final writerSaveBindingProvider =
    NotifierProvider<WriterSaveBindingNotifier, Map<String, WriterSaveBinding>>(
      WriterSaveBindingNotifier.new,
    );

/// True when any live Writer field differs from its valid named-save baseline,
/// or from the complete selected-project default when unbound.
final writerDirtyProvider = Provider<bool>((ref) {
  final projectId = ref.watch(
    saveSystemProvider.select((s) => s.selectedProjectId),
  );
  if (projectId == null) return false;
  ref.watch(songwriterProvider);
  ref.watch(writerSaveBindingProvider);
  ref.watch(saveSystemProvider);
  return ref.read(songwriterProvider.notifier).isProjectDirty(projectId);
});
