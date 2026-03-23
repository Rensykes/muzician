/// Settings Riverpod Store
library;

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fretboard.dart' show FretboardViewMode;
import '../models/piano.dart' show PianoViewMode;
import '../models/save_system.dart';

const _settingsKey = '@muzician/settings/v1';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(state.toJson()));
  }

  Future<void> setFretboardFavouriteViewMode(FretboardViewMode mode) async {
    state = state.copyWith(fretboardFavouriteViewMode: mode);
    await _persist();
  }

  Future<void> setPianoFavouriteViewMode(PianoViewMode mode) async {
    state = state.copyWith(pianoFavouriteViewMode: mode);
    await _persist();
  }

  Future<void> setSuppressOutOfKeyAlert(bool suppress) async {
    state = state.copyWith(suppressOutOfKeyAlert: suppress);
    await _persist();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
