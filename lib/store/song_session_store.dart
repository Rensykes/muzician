/// Auto-saves the active [SongProject] to SharedPreferences so the workspace
/// survives an app restart.  This is a *single, temporary* slot — distinct
/// from the named save browser — and is overwritten when the user creates a
/// new project via the Song header's "New" button.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_project.dart';
import '../schema/rules/song_rules.dart' as song_rules;
import 'song_project_store.dart';

const _kSongSessionKey = '@muzician/song_session/v1';
const _kSongSessionDebounce = Duration(milliseconds: 500);

class SongSessionPersistence {
  SongSessionPersistence(this.ref);

  final Ref ref;

  Timer? _debounce;
  ProviderSubscription<SongProject>? _subscription;
  bool _hydrating = false;
  bool _attached = false;

  /// Restores the previously persisted session (if any), then begins
  /// listening for changes.  Idempotent — safe to call once on app start.
  Future<void> hydrate() async {
    if (_attached) return;
    _hydrating = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSongSessionKey);
      if (raw != null) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final project = SongProject.fromJson(json);
          await ref.read(songProjectProvider.notifier).loadProject(project);
        } catch (_) {
          // Corrupt blob — drop it so the next save replaces it cleanly.
          await prefs.remove(_kSongSessionKey);
        }
      }
    } finally {
      _hydrating = false;
    }
    _attachListener();
  }

  void _attachListener() {
    _attached = true;
    _subscription = ref.listen<SongProject>(songProjectProvider, (_, next) {
      _schedulePersist(next);
    });
  }

  void _schedulePersist(SongProject project) {
    if (_hydrating) return;
    _debounce?.cancel();
    _debounce = Timer(_kSongSessionDebounce, () => _persist(project));
  }

  Future<void> _persist(SongProject project) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSongSessionKey, jsonEncode(project.toJson()));
  }

  /// Wipes the persisted session and resets the in-memory project to the
  /// default empty workspace.  Used by the Song "New" button after the user
  /// confirms the overwrite.
  Future<void> clearAndReset() async {
    _debounce?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSongSessionKey);
    _hydrating = true;
    try {
      await ref
          .read(songProjectProvider.notifier)
          .loadProject(song_rules.getDefaultSongProject());
    } finally {
      _hydrating = false;
    }
  }

  void dispose() {
    _subscription?.close();
    _subscription = null;
    _debounce?.cancel();
    _debounce = null;
  }
}

final songSessionProvider = Provider<SongSessionPersistence>((ref) {
  final session = SongSessionPersistence(ref);
  ref.onDispose(session.dispose);
  return session;
});
