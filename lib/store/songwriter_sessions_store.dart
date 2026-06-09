library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/songwriter.dart';

const _kSongwriterSessionsKey = '@muzician/songwriter_sessions/v1';
const _kDebounce = Duration(milliseconds: 500);

class SongwriterSessionsNotifier extends Notifier<Map<String, SongwriterProjectSnapshot>> {
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
    final raw = prefs.getString(_kSongwriterSessionsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = map.map(
          (k, v) => MapEntry(
            k,
            SongwriterProjectSnapshot.fromJson(v as Map<String, dynamic>),
          ),
        );
      } catch (_) {
        await prefs.remove(_kSongwriterSessionsKey);
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
    await prefs.remove(_kSongwriterSessionsKey);
  }

  void _schedulePersist() {
    _debounce?.cancel();
    final snapshot = state;
    _debounce = Timer(_kDebounce, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSongwriterSessionsKey,
        jsonEncode(snapshot.map((k, v) => MapEntry(k, v.toJson()))),
      );
    });
  }
}

final songwriterSessionsProvider =
    NotifierProvider<SongwriterSessionsNotifier, Map<String, SongwriterProjectSnapshot>>(
        SongwriterSessionsNotifier.new);
