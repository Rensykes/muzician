/// Settings Riverpod Store
library;

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Future<void> setSuppressOutOfKeyAlert(bool suppress) async {
    state = state.copyWith(suppressOutOfKeyAlert: suppress);
    await _persist();
  }

  Future<void> setNoteVolume(double volume) async {
    state = state.copyWith(noteVolume: volume.clamp(0.0, 1.0));
    await _persist();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
