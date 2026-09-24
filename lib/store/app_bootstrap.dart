library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_project.dart';
import '../models/songwriter.dart';
import '../schema/rules/save_system_rules.dart';
import 'persisted_data_recovery_store.dart';
import 'save_system_store.dart';
import 'settings_store.dart';
import 'song_sessions_store.dart';
import 'songwriter_sessions_store.dart';
import 'writer_save_binding_store.dart';

/// A reader compatible with both [WidgetRef.read] and [ProviderContainer.read],
/// so the bootstrap can run from the app shell and from tests.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

const contentWorkspaceNames = <String>[
  'fretboard',
  'piano',
  'roll',
  'song',
  'writer',
];

int contentWorkspaceTabForPreference(String? workspace) {
  final index = contentWorkspaceNames.indexOf(workspace ?? 'writer');
  return index < 0 ? 4 : index;
}

String? contentWorkspacePreferenceForTab(int tabIndex) =>
    tabIndex >= 0 && tabIndex < contentWorkspaceNames.length
    ? contentWorkspaceNames[tabIndex]
    : null;

/// Hydrates the persisted stores and restores the active project selection.
///
/// Order matters. The per-project session stores and the writer save bindings
/// are hydrated BEFORE [saveSystemProvider]. Hydrating the save system restores
/// `selectedProjectId`, which fires the project-selection listeners that load
/// each feature's session for that project — and those listeners read the
/// session maps. Hydrating the save system last left the listeners reading
/// empty maps, so a project opened with a blank session instead of its draft.
Future<void> hydrateStores(ProviderReader read) async {
  await read(settingsProvider.notifier).hydrate();

  late final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (error) {
    throw StartupStorageFailure('Could not read saved workspaces.', error);
  }

  final malformed = <MalformedPersistedPayload>[];
  final currentKeys = [
    songSessionsStorageKey,
    songwriterSessionsStorageKey,
    writerSaveBindingsStorageKey,
    saveSystemStorageKey,
  ];
  final rawByKey = <String, String>{};
  for (final key in currentKeys) {
    final String? raw;
    try {
      raw = prefs.getString(key);
    } catch (error) {
      throw StartupStorageFailure('Could not read saved data.', error);
    }
    if (raw == null) continue;
    rawByKey[key] = raw;
    try {
      _validateStoredPayload(key, raw);
    } catch (_) {
      malformed.add(MalformedPersistedPayload(storageKey: key, raw: raw));
    }
  }

  // SaveSystemNotifier.hydrate removes every legacy key when no valid v3
  // payload exists. Inspect those source schemas before that migration path
  // can delete a malformed value. A valid v3 payload skips the legacy wipe.
  final currentSaveSystem = rawByKey[saveSystemStorageKey];
  final shouldWipeLegacy =
      currentSaveSystem == null || deserialiseState(currentSaveSystem) == null;
  if (shouldWipeLegacy) {
    for (final key in [...legacySaveSystemStorageKeys, ...legacySessionKeys]) {
      final String? raw;
      try {
        raw = prefs.getString(key);
      } catch (error) {
        throw StartupStorageFailure('Could not read saved data.', error);
      }
      if (raw == null) continue;
      try {
        _validateStoredPayload(key, raw);
      } catch (_) {
        malformed.add(MalformedPersistedPayload(storageKey: key, raw: raw));
      }
    }
  }
  if (malformed.isNotEmpty) throw StartupRecoveryRequired(malformed);

  await read(songSessionsProvider.notifier).hydrate();
  await read(songwriterSessionsProvider.notifier).hydrate();
  await read(writerSaveBindingProvider.notifier).hydrate();
  // Last: selecting the restored project fires session listeners that need the
  // maps above already populated.
  await read(saveSystemProvider.notifier).hydrate();

  final notifier = read(saveSystemProvider.notifier);
  final selected = read(saveSystemProvider).selectedProjectId;
  // First launch (or selection cleared): default to Dump so the user can create
  // saves freely on Fretboard / Piano / Roll without a forced project modal.
  // Song / Songwriter still prompt when entered because Dump is not a project.
  notifier.selectProject(selected ?? notifier.ensureDumpFolder());
}

void _validateStoredPayload(String key, String raw) {
  if (key == saveSystemStorageKey) {
    if (deserialiseState(raw) == null) throw const FormatException();
    return;
  }

  final decoded = jsonDecode(raw);
  final values = decoded as Map<String, dynamic>;
  switch (key) {
    case songSessionsStorageKey:
      for (final value in values.values) {
        SongProject.fromJson(value as Map<String, dynamic>);
      }
      return;
    case '@muzician/song_session/v1':
      SongProject.fromJson(values);
      return;
    case songwriterSessionsStorageKey:
      for (final value in values.values) {
        SongwriterProjectSnapshot.fromJson(value as Map<String, dynamic>);
      }
      return;
    case '@muzician/songwriter_session/v1':
      SongwriterProjectSnapshot.fromJson(values);
      return;
    case writerSaveBindingsStorageKey:
      for (final value in values.values) {
        final binding = value as Map<String, dynamic>;
        binding['activeSaveId'] as String?;
        binding['alwaysOverwrite'] as bool?;
      }
      return;
    case '@muzician/save-system/v2':
    case '@muzician/save_system':
      if (values['folders'] is! List || values['saves'] is! List) {
        throw const FormatException('Invalid legacy save-system payload.');
      }
      deserialiseState(raw) ??
          (throw const FormatException('Invalid legacy save-system payload.'));
      return;
  }
}
