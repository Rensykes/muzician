import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/song_rules.dart'
    show getDefaultSongProject;
import 'package:muzician/schema/rules/save_system_rules.dart';
import 'package:muzician/store/app_bootstrap.dart';
import 'package:muzician/store/persisted_data_recovery_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/song_sessions_store.dart';
import 'package:muzician/store/songwriter_sessions_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup restore: a saved Writer draft survives the hydrate sequence',
    () async {
      // ── Phase A: a prior run that selected a project and added a section. ──
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c0 = ProviderContainer();
      await c0.read(saveSystemProvider.notifier).hydrate();
      await c0.read(songwriterSessionsProvider.notifier).hydrate();
      final pid = c0
          .read(saveSystemProvider.notifier)
          .createProject('Vorrei', const ProjectConfig())!;
      c0.read(saveSystemProvider.notifier).selectProject(pid);
      c0
          .read(songwriterProvider.notifier)
          .addSection(label: 'V', lengthBars: 4);
      // Flush the debounced session write deterministically — no real delay. The
      // save-system write is immediate (un-debounced) and its microtasks are
      // queued before flush's, so its blob is on disk once flush resolves.
      await c0.read(songwriterSessionsProvider.notifier).flush();
      final prefs = await SharedPreferences.getInstance();
      final saveBlob = prefs.getString('@muzician/save-system/v3')!;
      final sessBlob = prefs.getString('@muzician/songwriter_sessions/v1')!;
      c0.dispose();

      // ── Phase B: relaunch — the writer provider is alive (IndexedStack builds
      // it eagerly) BEFORE the stores hydrate, exactly as in the app shell. ──
      SharedPreferences.setMockInitialValues(<String, Object>{
        '@muzician/save-system/v3': saveBlob,
        '@muzician/songwriter_sessions/v1': sessBlob,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      // Registers the project-selection listener before any hydrate runs.
      c.read(songwriterProvider);

      await hydrateStores(c.read);

      expect(c.read(saveSystemProvider).selectedProjectId, pid);
      expect(c.read(songwriterProvider).sections, isNotEmpty);
    },
  );

  test('content workspace preference mapping defaults to Writer', () {
    expect(contentWorkspaceTabForPreference(null), 4);
    expect(contentWorkspaceTabForPreference('unknown'), 4);
    expect(contentWorkspaceNames, [
      'fretboard',
      'piano',
      'roll',
      'song',
      'writer',
    ]);
    for (var tab = 0; tab < contentWorkspaceNames.length; tab++) {
      final workspace = contentWorkspaceNames[tab];
      expect(contentWorkspaceTabForPreference(workspace), tab);
      expect(contentWorkspacePreferenceForTab(tab), workspace);
    }
    expect(contentWorkspacePreferenceForTab(5), isNull);
  });

  test('content workspace selection persists through app settings', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .setLastContentWorkspace('song');

    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.fromJson(
      (jsonDecode(prefs.getString('@muzician/settings/v1')!) as Map)
          .cast<String, dynamic>(),
    );
    expect(settings.lastContentWorkspace, 'song');
  });

  test(
    'settings read failure uses defaults and startup still hydrates',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        '@muzician/settings/v1': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await hydrateStores(container.read);

      expect(container.read(settingsProvider), const AppSettings());
      expect(container.read(saveSystemProvider).selectedProjectId, isNotNull);
    },
  );

  test(
    'malformed Song, Writer, and save data is preserved until fresh start',
    () async {
      const malformed = <String, String>{
        songSessionsStorageKey: '{ "song": [broken] }',
        songwriterSessionsStorageKey: '{ "writer": [broken] }',
        '@muzician/save-system/v3': '{ "folders": [broken] }',
        writerSaveBindingsStorageKey: '{ "writer": { "activeSaveId": 3 } }',
      };
      SharedPreferences.setMockInitialValues(malformed);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final prefs = await SharedPreferences.getInstance();

      StartupRecoveryRequired? recovery;
      try {
        await hydrateStores(container.read);
        fail('Malformed persisted data should block startup hydration.');
      } on StartupRecoveryRequired catch (error) {
        recovery = error;
      }

      expect(recovery, isNotNull);
      expect({
        for (final payload in recovery.payloads) payload.storageKey,
      }, malformed.keys.toSet());
      for (final entry in malformed.entries) {
        expect(prefs.getString(entry.key), entry.value);
      }
      // Preflight stops before the save-system default can overwrite bad data.
      expect(
        prefs.getString('@muzician/save-system/v3'),
        malformed['@muzician/save-system/v3'],
      );

      await container
          .read(dataRecoveryProvider.notifier)
          .preserveAndClear(recovery.payloads);
      final preserved = container.read(dataRecoveryProvider);
      expect(
        preserved.map((backup) => backup.raw).toSet(),
        malformed.values.toSet(),
      );
      for (final entry in malformed.entries) {
        expect(prefs.containsKey(entry.key), isFalse);
      }

      // Only the explicit fresh-start action clears source keys; normal
      // hydration can now initialize a new workspace while backups remain.
      await hydrateStores(container.read);
      final projectId = container
          .read(saveSystemProvider.notifier)
          .createProject('Active project', const ProjectConfig())!;
      container.read(saveSystemProvider.notifier).selectProject(projectId);

      final selectedBackup = preserved.first;
      await container
          .read(dataRecoveryProvider.notifier)
          .deleteBackup(selectedBackup.storageKey);
      expect(container.read(saveSystemProvider).selectedProjectId, projectId);
      expect(prefs.getString(preserved[1].storageKey), preserved[1].raw);
      expect(
        container
            .read(dataRecoveryProvider)
            .any((backup) => backup.storageKey == selectedBackup.storageKey),
        isFalse,
      );
    },
  );

  test(
    'malformed legacy payloads are preserved before the migration wipe',
    () async {
      const malformed = <String, String>{
        '@muzician/save-system/v2': '{ "folders": [broken] }',
        '@muzician/save_system': '{ "saves": [broken] }',
        '@muzician/song_session/v1': '{ "tracks": [broken] }',
        '@muzician/songwriter_session/v1': '{ "sections": [broken] }',
      };
      SharedPreferences.setMockInitialValues(malformed);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final prefs = await SharedPreferences.getInstance();

      StartupRecoveryRequired? recovery;
      try {
        await hydrateStores(container.read);
        fail('Malformed legacy data should block the migration wipe.');
      } on StartupRecoveryRequired catch (error) {
        recovery = error;
      }

      expect(recovery, isNotNull);
      expect({
        for (final payload in recovery.payloads) payload.storageKey,
      }, malformed.keys.toSet());
      for (final entry in malformed.entries) {
        expect(prefs.getString(entry.key), entry.value);
      }
      expect(prefs.containsKey('@muzician/save-system/v3'), isFalse);
    },
  );

  test(
    'valid legacy data follows the existing migration wipe policy',
    () async {
      final song = getDefaultSongProject();
      const writer = SongwriterProjectSnapshot(
        config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      );
      final legacy = <String, String>{
        '@muzician/save-system/v2': jsonEncode({'folders': [], 'saves': []}),
        '@muzician/save_system': jsonEncode({'folders': [], 'saves': []}),
        '@muzician/song_session/v1': jsonEncode(song.toJson()),
        '@muzician/songwriter_session/v1': jsonEncode(writer.toJson()),
      };
      SharedPreferences.setMockInitialValues(legacy);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await hydrateStores(container.read);

      final prefs = await SharedPreferences.getInstance();
      for (final key in legacy.keys) {
        expect(
          prefs.containsKey(key),
          isFalse,
          reason: '$key is migrated by wipe',
        );
      }
      expect(prefs.getString(saveSystemStorageKey), isNotNull);
    },
  );
}
