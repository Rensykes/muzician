/// Settings Riverpod Store
library;

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/harmony_lane_instrument.dart';
import '../models/save_system.dart';
import '../schema/rules/mono_pitch_rules.dart';

const settingsStorageKey = '@muzician/settings/v1';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(settingsStorageKey);
      if (raw != null) {
        try {
          state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {
          state = const AppSettings();
        }
      }
    } catch (_) {
      state = const AppSettings();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(settingsStorageKey, jsonEncode(state.toJson()));
  }

  Future<void> setSuppressOutOfKeyAlert(bool suppress) async {
    state = state.copyWith(suppressOutOfKeyAlert: suppress);
    await _persist();
  }

  Future<void> setNoteVolume(double volume) async {
    state = state.copyWith(noteVolume: volume.clamp(0.0, 1.0));
    await _persist();
  }

  Future<void> setShowNoteLabels(bool show) async {
    state = state.copyWith(showNoteLabels: show);
    await _persist();
  }

  Future<void> setHumSensitivity(HumSensitivity sensitivity) async {
    state = state.copyWith(humSensitivity: sensitivity);
    await _persist();
  }

  Future<void> setMetronomeEnabled(bool enabled) async {
    state = state.copyWith(metronomeEnabled: enabled);
    await _persist();
  }

  Future<void> setSaveBrowserGrid(bool grid) async {
    state = state.copyWith(saveBrowserGrid: grid);
    await _persist();
  }

  Future<void> setRecordMonitorBacking(bool on) async {
    state = state.copyWith(recordMonitorBacking: on);
    await _persist();
  }

  Future<void> setRecordMonitorMetronome(bool on) async {
    state = state.copyWith(recordMonitorMetronome: on);
    await _persist();
  }

  Future<void> setRecordCountIn(bool on) async {
    state = state.copyWith(recordCountIn: on);
    await _persist();
  }

  Future<void> setLastContentWorkspace(String? workspace) async {
    state = state.copyWith(lastContentWorkspace: () => workspace);
    await _persist();
  }

  Future<void> setDefaultNewProjectHarmonyInstrument(
    HarmonyLaneInstrument instrument,
  ) async {
    state = state.copyWith(
      defaultNewProjectHarmonyInstrument: () => instrument,
    );
    await _persist();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
