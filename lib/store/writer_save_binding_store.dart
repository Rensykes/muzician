library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/save_system.dart';
import 'save_system_store.dart';
import 'songwriter_store.dart';

const _kWriterBindingsKey = '@muzician/writer_save_bindings/v1';
const _kDebounce = Duration(milliseconds: 500);

/// Per-project link between the live Writer project and a named [SaveEntry].
class WriterSaveBinding {
  final String? activeSaveId;
  final bool alwaysOverwrite;
  const WriterSaveBinding({this.activeSaveId, this.alwaysOverwrite = false});

  WriterSaveBinding copyWith({String? activeSaveId, bool? alwaysOverwrite}) =>
      WriterSaveBinding(
        activeSaveId: activeSaveId ?? this.activeSaveId,
        alwaysOverwrite: alwaysOverwrite ?? this.alwaysOverwrite,
      );

  Map<String, dynamic> toJson() => {
        'activeSaveId': activeSaveId,
        'alwaysOverwrite': alwaysOverwrite,
      };

  factory WriterSaveBinding.fromJson(Map<String, dynamic> json) =>
      WriterSaveBinding(
        activeSaveId: json['activeSaveId'] as String?,
        alwaysOverwrite: json['alwaysOverwrite'] as bool? ?? false,
      );
}

class WriterSaveBindingNotifier
    extends Notifier<Map<String, WriterSaveBinding>> {
  Timer? _debounce;
  bool _hydrated = false;

  @override
  Map<String, WriterSaveBinding> build() {
    ref.onDispose(() => _debounce?.cancel());
    return const {};
  }

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWriterBindingsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = map.map(
          (k, v) => MapEntry(
            k,
            WriterSaveBinding.fromJson(v as Map<String, dynamic>),
          ),
        );
      } catch (_) {
        await prefs.remove(_kWriterBindingsKey);
      }
    }
    _hydrated = true;
  }

  /// Binds [projectId] to [saveId] and RESETS alwaysOverwrite. Called on load
  /// and on save (new or save-as-new).
  void bind(String projectId, String saveId) {
    state = {...state, projectId: WriterSaveBinding(activeSaveId: saveId)};
    _schedulePersist();
  }

  void setAlwaysOverwrite(String projectId, bool value) {
    final cur = state[projectId] ?? const WriterSaveBinding();
    state = {...state, projectId: cur.copyWith(alwaysOverwrite: value)};
    _schedulePersist();
  }

  void clear(String projectId) {
    final next = {...state}..remove(projectId);
    state = next;
    _schedulePersist();
  }

  void _schedulePersist() {
    _debounce?.cancel();
    final snapshot = state;
    _debounce = Timer(_kDebounce, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kWriterBindingsKey,
        jsonEncode(snapshot.map((k, v) => MapEntry(k, v.toJson()))),
      );
    });
  }
}

final writerSaveBindingProvider =
    NotifierProvider<WriterSaveBindingNotifier, Map<String, WriterSaveBinding>>(
        WriterSaveBindingNotifier.new);

/// True when the live Writer project differs from the named save it is bound
/// to. When unbound (or the bound save is missing), dirty when it has content.
final writerDirtyProvider = Provider<bool>((ref) {
  final projectId =
      ref.watch(saveSystemProvider.select((s) => s.selectedProjectId));
  if (projectId == null) return false;
  final project = ref.watch(songwriterProvider);
  final binding = ref.watch(writerSaveBindingProvider)[projectId];
  final saves = ref.watch(saveSystemProvider.select((s) => s.saves));
  final id = binding?.activeSaveId;
  SaveEntry? entry;
  if (id != null) {
    for (final s in saves) {
      if (s.id == id) {
        entry = s;
        break;
      }
    }
  }
  if (entry == null) {
    return project.sections.isNotEmpty || project.drumPatterns.isNotEmpty;
  }
  return jsonEncode(project.toJson()) != jsonEncode(entry.snapshot.toJson());
});
