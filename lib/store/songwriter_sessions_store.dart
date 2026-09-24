library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/songwriter.dart';
import 'persisted_data_recovery_store.dart';

const songwriterSessionsStorageKey = '@muzician/songwriter_sessions/v1';
const _kDebounce = Duration(milliseconds: 500);

class SongwriterSessionsNotifier
    extends Notifier<Map<String, SongwriterProjectSnapshot>> {
  Timer? _debounce;
  bool _hydrated = false;

  @override
  Map<String, SongwriterProjectSnapshot> build() {
    ref.onDispose(() => _debounce?.cancel());
    return const {};
  }

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(songwriterSessionsStorageKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = map.map(
          (k, v) => MapEntry(
            k,
            SongwriterProjectSnapshot.fromJson(v as Map<String, dynamic>),
          ),
        );
        state = parsed;
      } catch (_) {
        throw MalformedPersistedPayload(
          storageKey: songwriterSessionsStorageKey,
          raw: raw,
        );
      }
    }
    _hydrated = true;
  }

  SongwriterProjectSnapshot? get(String projectId) => state[projectId];

  void put(String projectId, SongwriterProjectSnapshot project) {
    state = {...state, projectId: project};
    _schedulePersist();
  }

  void remove(String projectId) {
    final next = {...state}..remove(projectId);
    state = next;
    _schedulePersist();
  }

  Future<void> clearAll() async {
    _debounce?.cancel();
    state = const {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(songwriterSessionsStorageKey);
  }

  /// Cancels any pending debounced write and persists the current state now.
  /// Use at app-lifecycle flush points (e.g. before backgrounding) and in tests
  /// that need a deterministic round-trip without waiting out the debounce.
  Future<void> flush() async {
    _debounce?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      songwriterSessionsStorageKey,
      jsonEncode(state.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  void _schedulePersist() {
    _debounce?.cancel();
    final snapshot = state;
    _debounce = Timer(_kDebounce, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        songwriterSessionsStorageKey,
        jsonEncode(snapshot.map((k, v) => MapEntry(k, v.toJson()))),
      );
    });
  }
}

final songwriterSessionsProvider =
    NotifierProvider<
      SongwriterSessionsNotifier,
      Map<String, SongwriterProjectSnapshot>
    >(SongwriterSessionsNotifier.new);
