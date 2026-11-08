# Remove the Song Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the Song workspace, its persisted data, tests and documentation, while keeping Writer and every other workspace working exactly as today.

**Architecture:** Remove Song from the shell first, then from the Save System and bootstrap, then delete its UI/rules/stores. Move the five Writer-facing Song UI files into `lib/features/songwriter/` before deleting the rest. Finally rename the shared note/drum/audio types and audio infrastructure to Writer-neutral files, and split the surviving tests.

**Tech Stack:** Flutter, Dart, Riverpod, SharedPreferences, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-08-remove-song-design.md`

## Global Constraints

- Writer, Fretboard, Piano, Roll, Save System and Settings must keep working exactly as today.
- Existing Song projects and `song_audio/` files are discarded; Writer saves, Writer audio, settings and project folders must survive.
- No `SongProject`, `SongScreen`, `songProjectProvider`, `features/song/`, `songSessions` or `song_audio` reference may remain in `lib/` or `test/` except the one-time cleanup key strings in `lib/store/app_bootstrap.dart`.
- Use `dart format` on changed paths, `flutter analyze`, and the narrowest `flutter test` target before each commit.
- Follow Conventional Commits (`refactor:`, `feat:`, `docs:`, `chore:`).
- Archived plans, specs and agent reports under `docs/superpowers/` and `docs/studio-redesign/` keep their historical Song text.

## Review Focus

- A persisted Song save must be dropped, not parsed as a `FretboardSnapshot`. Tested in Task 3.
- Writer audio repository, clip sink, recorder driver, downmix and pattern bridge must survive the renames with coverage. Tested in Tasks 5 and 9.
- Hardcoded tab indices shift from six tabs to five; Writer handoff and Settings must land on the right tab. Tested in Task 2.
- Song cleanup must delete `song_audio/` and never `songwriter_audio/`. Tested in Task 4.
- Writer's drum library, My Loops and audio record/import flows depend on moved files. Tested in Task 1.

---

### Task 1: Move Writer-facing Song UI into the Writer feature

**Files:**
- Create: `lib/features/songwriter/drum_machine_editor.dart` (from `lib/features/song/drum_machine_editor.dart`)
- Create: `lib/features/songwriter/drum_library_sheet.dart`
- Create: `lib/features/songwriter/drum_loop_save_panel.dart`
- Create: `lib/features/songwriter/songwriter_audio_clip_body.dart`
- Create: `lib/features/songwriter/songwriter_audio_picker_sheet.dart`
- Modify: `lib/features/songwriter/drum_pattern_sheet.dart`, `lib/features/songwriter/songwriter_audio_clip_sheet.dart`, `lib/features/songwriter/songwriter_audio_lane_row.dart`, `lib/features/songwriter/songwriter_audio_actions.dart`, `lib/features/song/song_pattern_editor_launcher.dart`
- Test: `test/features/songwriter/drum_clear_test.dart`, `drum_fill_menu_test.dart`, `drum_audition_stop_test.dart`, `drum_library_test.dart`, `drum_loop_save_panel_test.dart`, `songwriter_audio_clip_body_test.dart`, `songwriter_audio_picker_sheet_test.dart`, `shared_editor_theme_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `DrumMachineEditorBody({required DrumPattern pattern, required int tempo, required void Function(DrumPattern updated) onChanged, int beatUnit = 4, DrumBackingDescriptor? backing, bool enableLibrary = false})` in `lib/features/songwriter/drum_machine_editor.dart`.
- Produces: `SongwriterAudioPickerSheet({required VoidCallback onRecord, required VoidCallback onImport, bool? recordSupported})`.
- Produces: `AudioClipBody({required String name, required int durationMs, required String format, required List<int> peaks, required bool isBroken})`.

- [ ] **Step 1: Move the tests and update their imports**

Use `git mv` for the eight test files above into `test/features/songwriter/`. In `shared_editor_theme_test.dart`, keep the `DrumMachineEditorBody` cases and delete the `for (final type in [SongTrackType.note, SongTrackType.drum])` block that opens Song editors. Delete `test/features/song/drum_machine_editor_test.dart` (it tests the deleted Song wrapper). Rename `song_audio_clip_body_test.dart` and `song_audio_picker_sheet_test.dart` as shown.

- [ ] **Step 2: Run the moved tests to verify they fail**

Run: `flutter test test/features/songwriter`
Expected: FAIL — the imported `features/song/...` paths and `SongAudioPickerSheet` no longer match the planned files.

- [ ] **Step 3: Move the five source files**

`git mv` each file to its new path. Move `drum_machine_editor.dart` whole for now, including the Song-only `DrumMachineEditor` wrapper; Task 7 deletes the wrapper after the Song UI is gone. Update its relative imports: `../../models/song_project.dart` and `../../store/song_project_store.dart` stay for now (renamed/deleted in Tasks 8–9); `drum_library_sheet.dart` and `drum_loop_save_panel.dart` remain sibling imports.

In the moved `song_audio_picker_sheet.dart`, rename the class to `SongwriterAudioPickerSheet` and remove the `trackId` and `startTick` fields/constructor parameters.

Update the four Writer call sites plus `song_pattern_editor_launcher.dart` to the new paths. In `songwriter_audio_actions.dart`, call `SongwriterAudioPickerSheet(onRecord: ..., onImport: ...)` without `trackId`/`startTick`.

- [ ] **Step 4: Run the moved tests to verify they pass**

Run: `flutter test test/features/songwriter`
Expected: PASS.

- [ ] **Step 5: Format and analyze**

Run: `dart format lib/features/songwriter test/features/songwriter && flutter analyze`
Expected: no new errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter lib/features/song test/features/songwriter test/features/song
git commit -m "refactor: move Writer-facing Song UI into the Writer feature"
```

---

### Task 2: Remove the Song tab from the shell

**Files:**
- Modify: `lib/store/app_bootstrap.dart`, `lib/main.dart`
- Test: `test/main_startup_test.dart`, `test/store/app_bootstrap_startup_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `contentWorkspaceNames == ['fretboard', 'piano', 'roll', 'writer']`.
- Produces: `contentWorkspaceTabForPreference(null) == 3`, `contentWorkspaceTabForPreference('unknown') == 3`, `contentWorkspacePreferenceForTab(3) == 'writer'`, `contentWorkspacePreferenceForTab(4) == null`.

- [ ] **Step 1: Write the failing shell tests**

In `test/main_startup_test.dart`:
- Change the restore cases to `('fretboard', 0)`, `('piano', 1)`, `('roll', 2)`, `('writer', 3)`, `('song', 3)` (the old Song preference falls back to Writer).
- Change the invalid-preference expectation from 4 to 3.
- Change the Settings expectation from 5 to 4.
- Delete the test `Song is disabled and tapping it leaves the workspace unchanged`, and remove the `SongScreen` / `song_project_store.dart` imports it used.
- Add: `expect(find.byKey(const ValueKey('nav_Song')), findsNothing);` after startup on both viewports.

In `test/store/app_bootstrap_startup_test.dart`, replace the `content workspace preference mapping` test expectations with the four names and index 3 for Writer; `contentWorkspacePreferenceForTab(4)` is null.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/main_startup_test.dart test/store/app_bootstrap_startup_test.dart`
Expected: FAIL on the new indices and the missing `nav_Song` assertion.

- [ ] **Step 3: Implement the shell change**

In `lib/store/app_bootstrap.dart`:
```dart
const contentWorkspaceNames = <String>['fretboard', 'piano', 'roll', 'writer'];

int contentWorkspaceTabForPreference(String? workspace) {
  final index = contentWorkspaceNames.indexOf(workspace ?? 'writer');
  return index < 0 ? 3 : index;
}

String? contentWorkspacePreferenceForTab(int tabIndex) =>
    tabIndex >= 0 && tabIndex < contentWorkspaceNames.length
    ? contentWorkspaceNames[tabIndex]
    : null;
```
Delete `songWorkspaceTabIndex`.

In `lib/main.dart`:
- Remove the `Song` `AppNavDestination`, `_UnavailableSongWorkspace`, the `_setTab` Song guard and the `_screenLabelForTab` Song special case.
- Set `_tabIndex = 3`, Writer `_setTab(3)`, Settings `_setTab(4)`, and the Fretboard/Piano handoff callbacks to `_setTab(3)`.
- Remove the `songAudioClipSinkProvider` override and its `song_playback_store.dart` import; keep the recorder driver/status imports for now.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/main_startup_test.dart test/store/app_bootstrap_startup_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/app_bootstrap.dart lib/main.dart test/main_startup_test.dart test/store/app_bootstrap_startup_test.dart
git commit -m "refactor: remove the Song tab from the shell"
```

---

### Task 3: Remove Song from the Save System

**Files:**
- Modify: `lib/models/save_system.dart`, `lib/store/save_system_store.dart`, `lib/schema/rules/save_system_rules.dart`, `lib/ui/save_browser_panel.dart`, `lib/ui/save_previews/save_preview_thumbnail.dart`, `lib/store/project_config_sync.dart`
- Test: `test/schema/rules/save_system_rules_test.dart` (create), `test/store/save_system_store_test.dart`, `test/store/project_config_sync_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `deserialiseState(String raw)` drops any save whose snapshot JSON has `type == 'song'` or `instrument == 'song'` before `SaveEntry.fromJson`.

- [ ] **Step 1: Write the failing save-filter test**

Create `test/schema/rules/save_system_rules_test.dart`:
```dart
test('deserialiseState drops persisted Song saves', () {
  final raw = jsonEncode({
    'folders': [],
    'saves': [
      {
        'id': 'song-1',
        'name': 'Old Song',
        'folderId': 'f',
        'snapshot': {'type': 'song', 'instrument': 'song', 'project': {}},
        'createdAt': 0,
        'updatedAt': 0,
        'order': 0,
      },
      {
        'id': 'keep-1',
        'name': 'Keep',
        'folderId': 'f',
        'snapshot': {
          'type': 'fretboard',
          'instrument': 'fretboard',
          'tuning': 'standard',
          'numFrets': 12,
          'capo': 0,
          'selectedCells': [],
          'selectedNotes': [],
          'viewMode': 'exact',
        },
        'createdAt': 0,
        'updatedAt': 0,
        'order': 1,
      },
    ],
  });
  final parsed = deserialiseState(raw);
  expect(parsed, isNotNull);
  expect(parsed!.saves.map((save) => save.id), ['keep-1']);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/schema/rules/save_system_rules_test.dart`
Expected: FAIL — the Song save is either parsed or causes a fallback.

- [ ] **Step 3: Implement the filter and remove the Song snapshot**

In `lib/schema/rules/save_system_rules.dart`, before mapping saves:
```dart
bool isRemovedSongSave(Map<String, dynamic> save) {
  final snapshot = save['snapshot'];
  if (snapshot is! Map) return false;
  return snapshot['type'] == 'song' || snapshot['instrument'] == 'song';
}
```
Filter the raw list with `where((save) => !isRemovedSongSave(save as Map<String, dynamic>))`.

In `lib/models/save_system.dart`, delete `SongProjectSnapshot` and the `type == 'song' || instrument == 'song'` branch in `InstrumentSnapshot.fromJson`. Keep the `song_project.dart` import only if `DrumLoopSnapshot` still needs `DrumPattern`; otherwise remove it.

In `lib/store/save_system_store.dart`, delete the `if (snap is SongProjectSnapshot)` branch in `_snapshotWithProjectConfig` and the now-unused import.

In `lib/ui/save_browser_panel.dart`, delete `_buildSongSummary`, the `SongProjectSnapshot` branch, the `'song'` icon case and the `instrumentFilter == 'song'` branch.

In `lib/ui/save_previews/save_preview_thumbnail.dart`, delete `_SongMiniPainter`, its dispatch branch and the `song_project.dart` import.

In `lib/store/project_config_sync.dart`, delete the `// Song` block in both `_applyProjectConfig` and `_clearProjectKeyContext`, and the `song_project_store.dart` import.

- [ ] **Step 4: Update the affected tests**

Delete both Song groups in `test/store/save_system_store_test.dart` (`InstrumentSnapshot.fromJson dispatches to SongProjectSnapshot` and `SongProjectSnapshot serialization`) and the `song_project.dart` import. In `test/store/project_config_sync_test.dart` and `test/store/project_config_sync_key_context_test.dart`, remove the `songProjectProvider` reads/writes, the `song_project_store.dart` / `song_rules.dart` imports, and assert Writer state only.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/schema/rules/save_system_rules_test.dart test/store/save_system_store_test.dart test/store/project_config_sync_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/save_system.dart lib/store/save_system_store.dart lib/schema/rules/save_system_rules.dart lib/ui/save_browser_panel.dart lib/ui/save_previews/save_preview_thumbnail.dart lib/store/project_config_sync.dart test/schema/rules/save_system_rules_test.dart test/store/save_system_store_test.dart test/store/project_config_sync_test.dart
git commit -m "refactor: remove Song saves from the Save System"
```

---

### Task 4: Remove Song bootstrap hydration and wipe persisted Song data

**Files:**
- Modify: `lib/store/app_bootstrap.dart`, `lib/store/persisted_data_recovery_store.dart`, `lib/store/save_system_store.dart`
- Test: `test/store/app_bootstrap_startup_test.dart`, `test/store/save_system_store_migration_test.dart`, `test/features/save_system/recovery_export_test.dart`

**Interfaces:**
- Consumes: `deserialiseState` filtering from Task 3.
- Produces: on `hydrateStores`, the keys `@muzician/song_sessions/v1` and `@muzician/song_session/v1` are removed before validation; `song_audio/` is deleted; `songwriter_audio/` and Writer keys remain.

- [ ] **Step 1: Write the failing cleanup test**

In `test/store/app_bootstrap_startup_test.dart`, add:
```dart
test('Song storage is discarded and Writer storage survives', () async {
  SharedPreferences.setMockInitialValues({
    '@muzician/song_sessions/v1': '{"song":{}}',
    '@muzician/song_session/v1': '{"config":{}}',
    songwriterSessionsStorageKey: '{"writer":{}}',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await hydrateStores(container.read);
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.containsKey('@muzician/song_sessions/v1'), isFalse);
  expect(prefs.containsKey('@muzician/song_session/v1'), isFalse);
  expect(prefs.containsKey(songwriterSessionsStorageKey), isTrue);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/store/app_bootstrap_startup_test.dart`
Expected: FAIL — Song keys remain.

- [ ] **Step 3: Implement the cleanup**

In `lib/store/app_bootstrap.dart`:
- Add `const _removedSongStorageKeys = ['@muzician/song_sessions/v1', '@muzician/song_session/v1'];`.
- After `prefs` is available and before the Writer journal replay/validation, loop and `await prefs.remove(key)` for each.
- Remove `songSessionsStorageKey` from `currentKeys`, remove the Song `hydrate()` call, and delete the Song cases from `_validateStoredPayload`.
- Remove the `song_sessions_store.dart` and `song_project.dart` imports.

In `lib/store/persisted_data_recovery_store.dart`, remove the `'@muzician/song_sessions/v1' => 'Song drafts'` label.

In `lib/store/save_system_store.dart`, add `_wipeRemovedSongAudioDir()` (same body as `_wipeAudioDir` but only the `song_audio` directory) and call it at the start of `hydrate()` inside `try/catch`.

- [ ] **Step 4: Update the affected tests**

In `test/store/app_bootstrap_startup_test.dart`:
- Remove Song keys from the malformed-data maps and expected recovery sets, and remove the `songSessionsStorageKey`, `song_rules.dart` and `getDefaultSongProject` imports.
- In the legacy migration test, drop the `getDefaultSongProject()` payload and assert the Song key is gone after hydrate.

In `test/features/save_system/recovery_export_test.dart`, change the `sourceKey` strings from `@muzician/song_sessions/v1` to `@muzician/writer_sessions/v1` and update the filename expectation to `_muzician_writer_sessions_v1`.

`test/store/save_system_store_migration_test.dart` keeps `@muzician/song_session/v1` in its legacy wipe list; leave it as-is.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/store/app_bootstrap_startup_test.dart test/store/save_system_store_migration_test.dart test/features/save_system/recovery_export_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/store/app_bootstrap.dart lib/store/persisted_data_recovery_store.dart lib/store/save_system_store.dart test/store/app_bootstrap_startup_test.dart test/features/save_system/recovery_export_test.dart
git commit -m "refactor: discard persisted Song data during hydration"
```

---

### Task 5: Extract the shared audio clip sink

**Files:**
- Create: `lib/store/audio_clip_sink.dart`
- Modify: `lib/store/song_playback_store.dart`, `lib/store/songwriter_audio_sink.dart`, `lib/store/song_audio_player_sink.dart`
- Test: `test/store/songwriter_audio_store_test.dart`, `test/store/song_audio_player_sink_profile_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `abstract class AudioClipSink` with `Future<void> prepare(Iterable<AudioAsset> assets)`, `startClip({required AudioAsset asset, required int offsetMs, double volume = 1.0, double balance = 0.0, bool loop = false})`, `stopClip({required AudioAsset asset})`, `stopAll()`.
- Produces: `const NoopAudioClipSink()`.

- [ ] **Step 1: Move the sink interface**

Create `lib/store/audio_clip_sink.dart` with the `AudioClipSink` and `NoopAudioClipSink` classes copied from `song_playback_store.dart`, renamed from `SongAudioClipSink` / `NoopSongAudioClipSink`. Delete those classes from `song_playback_store.dart`.

Update `songwriter_audio_sink.dart` and `song_audio_player_sink.dart` to import `audio_clip_sink.dart` and use `AudioClipSink` / `NoopAudioClipSink`. Remove the now-unused `song_playback_store.dart` import from `songwriter_audio_sink.dart`.

- [ ] **Step 2: Update the sink test**

In `test/store/song_audio_player_sink_profile_test.dart`, update any `SongAudioClipSink` type reference to `AudioClipSink`. The Song bundle tests stay until Task 7, because `song_export_actions.dart` still imports the bundle code.

- [ ] **Step 3: Run the Writer audio tests**

Run: `flutter test test/store/songwriter_audio_store_test.dart test/store/song_audio_player_sink_profile_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/store/audio_clip_sink.dart lib/store/song_playback_store.dart lib/store/songwriter_audio_sink.dart lib/store/song_audio_player_sink.dart test/store/song_audio_player_sink_profile_test.dart
git commit -m "refactor: extract the shared audio clip sink from Song"
```

---

### Task 6: Remove Song from the profile harness

**Files:**
- Modify: `lib/profile_writer_playback.dart`
- Test: `test/profile_writer_playback_fixture_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: the harness keeps `ProfileViewMode.writer`, `fretboard`, `piano`; `buildWriterPlaybackProfileProviderOverrides` takes only the Writer `repository`.

- [ ] **Step 1: Delete the Song harness**

In `lib/profile_writer_playback.dart`:
- Remove `ProfileViewMode.song` and the `'song'` mapping.
- Remove `_ProfileSongProjectNotifier`, `_withControlledSongAudioClip`, `buildSongPlaybackProfileManifest`, the `SongScreen` branch and every Song import.
- Change `buildWriterPlaybackProfileProviderOverrides({required SongAudioRepository repository, required SongAudioRepository songRepository, ...})` to accept only `repository`, and remove the `songProjectProvider` / `songAudioRepositoryProvider` / `songAudioClipSinkProvider` overrides.

In `test/profile_writer_playback_fixture_test.dart`, delete the Song comparator and recorded-clip Song tests, the `songRepository` arguments, and the `ProfileViewMode.song` expectations. Keep the Writer fixture tests.

- [ ] **Step 2: Run the harness tests**

Run: `flutter test test/profile_writer_playback_fixture_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/profile_writer_playback.dart test/profile_writer_playback_fixture_test.dart
git commit -m "refactor: remove Song from the Writer playback harness"
```

---

### Task 7: Delete the remaining Song UI and bundle path

**Files:**
- Delete: `lib/features/song/` remaining files: `song_arranger_timeline.dart`, `song_audio_actions.dart`, `song_audio_recorder_sheet.dart`, `song_clip_action_bar.dart`, `song_coach_steps.dart`, `song_export_actions.dart`, `song_feature.dart`, `song_import_picker_sheet.dart`, `song_note_pattern_editor.dart`, `song_pattern_editor_launcher.dart`, `song_save_panel.dart`, `song_screen.dart`, `song_track_header.dart`
- Delete: `lib/store/song_bundle_import.dart`, `lib/schema/rules/song_bundle_rules.dart`
- Modify: `lib/store/song_audio_repository.dart`
- Test: delete `test/features/song/` remaining files, `test/store/song_bundle_import_test.dart`, `test/schema/rules/song_bundle_rules_test.dart`

**Interfaces:**
- Consumes: Task 1 moved the Writer-facing files; Task 6 removed the harness import.
- Produces: no `lib/features/song/` directory and no Song bundle code.
- Produces: `SongAudioRepository` without `writeImportedBundleAsset`.

- [ ] **Step 1: Delete the Song UI, bundle path and their tests**

Delete the 13 source files, the bundle store/rule files, and every remaining `test/features/song/*.dart` plus the two bundle tests. At this point `lib/features/song/` should contain only the five files moved out in Task 1, so delete the empty directory.

In `lib/features/songwriter/drum_machine_editor.dart`, delete the Song-only `DrumMachineEditor` wrapper, its `_MetaRow`, and the `song_project_store.dart` import. Keep `DrumMachineEditorBody`, the `song_project.dart` import for `DrumPattern` / `DrumLaneId`, and the private widgets the body uses.

In `lib/store/song_audio_repository.dart`, delete `writeImportedBundleAsset`, the `song_bundle_rules` import and the `songBundleMaxAudioEntryBytes` reference. Keep `writeRecording`, `importExternalFile`, `delete`, `reconcileOrphans`, `readInt16Samples`, `readAssetBytes`, `writeStretched` and `extractInt16Samples`.

- [ ] **Step 2: Verify nothing imports the deleted files**

Run: `grep -rn "features/song/\|song_bundle" lib test`
Expected: no matches.

- [ ] **Step 3: Analyze and run the Writer tests**

Run: `flutter analyze && flutter test test/features/songwriter test/store/songwriter_audio_store_test.dart`
Expected: no errors; Writer tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A lib/features/song lib/store/song_bundle_import.dart lib/schema/rules/song_bundle_rules.dart lib/store/song_audio_repository.dart test
git commit -m "refactor: delete the Song workspace UI and bundle path"
```

---

### Task 8: Delete Song-only rules, stores and models

**Files:**
- Delete: `lib/models/song_playback.dart`
- Delete rules: `lib/schema/rules/song_audio_export_rules.dart`, `song_from_writer_rules.dart`, `song_import_rules.dart`, `song_playback_rules.dart`, `song_render_rules.dart`, `song_rules.dart`, `song_split_rules.dart`
- Delete stores: `lib/store/song_playback_store.dart`, `song_project_store.dart`, `song_sessions_store.dart`
- Test: delete the matching `test/schema/rules/song_*`, `test/store/song_*` and `test/models/song_project_test.dart`

**Interfaces:**
- Consumes: Task 5 removed the clip sink and bundle path; Task 6 removed the harness.
- Produces: no Song-only rule/store/model files.

- [ ] **Step 1: Delete the files**

Delete the rules and stores listed above. Delete `test/schema/rules/song_audio_export_rules_test.dart`, `song_from_writer_rules_test.dart`, `song_import_rules_test.dart`, `song_playback_rules_test.dart`, `song_render_rules_test.dart`, `song_rules_test.dart`, `song_split_rules_test.dart`, `test/store/song_audio_recorder_store_test.dart`, `song_playback_store_test.dart`, `song_project_history_test.dart`, `song_project_store_cold_start_test.dart`, `song_project_store_session_swap_test.dart`, `song_project_store_test.dart`, `song_sessions_store_test.dart`. Keep `test/models/song_project_test.dart` for the Task 9 split.

Before deleting `song_rules.dart`, prune `lib/schema/rules/song_audio_rules.dart` to only `downmixToMono` and `computePeaksFromInt16`: delete `audioClipLengthTicks`, `audioTickToMs`, `requiredMeasuresForEndTick`, `schedulableAudioClips` and the `song_rules` import. The file is renamed in Task 9.

- [ ] **Step 2: Update the two mixed tests**

In `test/schema/rules/songwriter_resolve_test.dart`, delete the final `songFromSongwriter` block and the `song_from_writer_rules.dart` / `song_project.dart` imports. In `test/profile_writer_playback_fixture_test.dart`, remove any remaining `SongPatternType` / `SongProject` imports.

- [ ] **Step 3: Analyze and run the remaining tests**

Run: `flutter analyze && flutter test test/schema/rules/songwriter_resolve_test.dart test/store/songwriter_audio_store_test.dart`
Expected: no errors; tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A lib test
git commit -m "refactor: delete Song-only rules, stores and models"
```

---

### Task 9: Neutralise the shared model and audio names

**Files:**
- Rename: `lib/models/song_project.dart` → `lib/models/arrangement_content.dart`
- Rename: `lib/store/song_audio_repository.dart` → `lib/store/audio_repository.dart`
- Rename: `lib/store/song_audio_player_sink.dart` → `lib/store/audio_player_sink.dart`
- Rename: `lib/store/song_audio_recorder_store.dart` → `lib/store/audio_recorder_core.dart`
- Rename: `lib/store/song_audio_recorder_driver_impl.dart` → `lib/store/audio_recorder_driver_impl.dart`
- Rename: `lib/schema/rules/song_audio_rules.dart` → `lib/schema/rules/audio_rules.dart`
- Rename: `lib/schema/rules/song_pattern_bridge_rules.dart` → `lib/schema/rules/pattern_bridge_rules.dart`
- Test: rename/split as described below

**Interfaces:**
- Consumes: nothing.
- Produces: `arrangement_content.dart` keeps `DrumLaneId`, `NotePatternNote`, `NotePattern`, `DrumLaneSequence`, `DrumPattern`, `AudioAsset`.
- Produces: `AudioRepository` (class) and `songwriterAudioRepositoryProvider`.
- Produces: `AudioRecorderStatus`, `AudioRecorderDriver`, `audioRecorderDriverProvider`.
- Produces: `downmixToMono(Int16List samples, int channels)` and `computePeaksFromInt16(Int16List samples, {int targetBins = 400})`.
- Produces: `pianoRollStateFromNotePattern(NotePattern pattern, {required int tempo, required TimeSignature timeSignature})` and `notePatternFromPianoRollState(...)` unchanged except the dropped Song parameters.

- [ ] **Step 1: Prune and rename the content model**

In `lib/models/song_project.dart`, delete `SongTrackType`, `SongPatternType`, `SongProjectConfig`, `SongTrack`, `SongClipInstance`, `AudioClipPattern`, `SongMarker` and `SongProject`. Rename the file to `lib/models/arrangement_content.dart` with `git mv`. Update every import of `models/song_project.dart` to `models/arrangement_content.dart` across `lib/` and `test/`.

- [ ] **Step 2: Rename the audio infrastructure**

Use `git mv` for each file above and rename the symbols:
- `SongAudioRepository` → `AudioRepository`; keep `ReconcileResult`; delete `songAudioRepositoryProvider`; keep `songwriterAudioRepositoryProvider` and set the default subdir to `'writer_audio'`.
- `SongAudioClipSink` / `NoopSongAudioClipSink` are already `AudioClipSink` / `NoopAudioClipSink` from Task 5.
- `SongAudioRecorderStatus` → `AudioRecorderStatus`; `SongAudioRecorderDriver` → `AudioRecorderDriver`; `songAudioRecorderDriverProvider` → `audioRecorderDriverProvider`; delete `SongAudioRecorderNotifier` and `SongAudioRecorderState`.
- `RecordPackageDriver` keeps its name.
- `song_audio_rules.dart` was already pruned to `downmixToMono` and `computePeaksFromInt16` in Task 8; just rename it to `audio_rules.dart`.
- Keep both bridge functions in `pattern_bridge_rules.dart`; remove the `songHighlightedNotes` and `songKey` parameters and the Song wording from the doc comments.

Update every import and call site, including `lib/main.dart`, `lib/store/songwriter_audio_sink.dart`, `songwriter_audio_recorder_store.dart`, `songwriter_stretch_controller.dart`, `songwriter_slice_controller.dart`, `lib/features/songwriter/songwriter_melody_pattern_editor.dart`, `lib/models/save_system.dart`, `lib/models/songwriter.dart`, `lib/utils/note_player.dart`, `lib/utils/playback_voice_spec.dart`, `lib/schema/rules/piano_roll_playback_rules.dart`, `lib/schema/rules/drum_presets.dart`, `lib/schema/rules/songwriter_*.dart` and `lib/store/drum_pattern_playback_store.dart`.

- [ ] **Step 3: Move and split the surviving tests**

- `git mv test/store/song_audio_repository_test.dart test/store/audio_repository_test.dart` and update the class name.
- `git mv test/store/song_audio_repository_subdir_test.dart test/store/audio_repository_subdir_test.dart`; assert `writer_audio` vs `songwriter_audio` separation.
- `git mv test/store/song_audio_repository_stretch_test.dart test/store/audio_repository_stretch_test.dart`.
- `git mv test/store/song_audio_player_sink_profile_test.dart test/store/audio_player_sink_profile_test.dart`.
- `git mv test/schema/rules/song_pattern_bridge_rules_test.dart test/schema/rules/pattern_bridge_rules_test.dart`; remove the Song parameters.
- Split `test/schema/rules/song_audio_rules_test.dart`: keep only the `downmixToMono` and `computePeaksFromInt16` groups in `test/schema/rules/audio_rules_test.dart`.
- Split `test/models/song_project_test.dart`: keep `NotePatternNote`, `DrumPattern` and `AudioAsset` coverage in `test/models/arrangement_content_test.dart`.

- [ ] **Step 4: Run the moved tests**

Run: `flutter test test/store/audio_repository_test.dart test/store/audio_repository_subdir_test.dart test/store/audio_repository_stretch_test.dart test/store/audio_player_sink_profile_test.dart test/schema/rules/pattern_bridge_rules_test.dart test/schema/rules/audio_rules_test.dart test/models/arrangement_content_test.dart`
Expected: PASS.

- [ ] **Step 5: Grep for leftovers**

Run: `grep -rn "SongProject\|SongScreen\|songProjectProvider\|songSessions\|song_audio\|features/song\|song_audio_rules\|song_pattern_bridge" lib test`
Expected: only the two cleanup key strings in `lib/store/app_bootstrap.dart` and the `song_audio` directory literal in the cleanup helper.

- [ ] **Step 6: Format, analyze and run the full suite**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: analyzer clean; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A lib test
git commit -m "refactor: rename shared Song infrastructure to Writer-neutral files"
```

---

### Task 10: Update documentation and agent guidance

**Files:**
- Modify: `README.md`, `AGENTS.md`, `docs/songwriter.md`, `docs/save_system.md`, `docs/piano_roll.md`, `lib/ui/core/app_info_panel.dart`
- Rename: `docs/song_writer_guide.md` → `docs/writer_guide.md`
- Delete: `docs/song_workspace.md`

**Interfaces:**
- Consumes: the shipped code from Tasks 1–9.
- Produces: live docs that contain no Song workspace.

- [ ] **Step 1: Update the guides**

- `README.md`: remove the Song feature row; update the project-structure list; point Writer at `docs/songwriter.md` and `docs/writer_guide.md`.
- `git mv docs/song_writer_guide.md docs/writer_guide.md`; delete the Song transport, timeline, clip, marker and bridge sections; retitle to "Writer — Feature Guide"; keep Writer playback, portrait/landscape and interactive-guide content.
- `docs/songwriter.md`: remove the "Song is temporarily unavailable" and Song destination wording; link the Writer guide; update the drum-editor path to `lib/features/songwriter/drum_machine_editor.dart`.
- `docs/save_system.md`: remove the `SongProjectSnapshot` section, the `SongSavePanel` row and the `song_audio/` wipe wording; rename `SongAudioRepository` to `AudioRepository` and update the drum-loop panel path to `lib/features/songwriter/`.
- `docs/piano_roll.md`: remove "Legacy Song host" and "Standalone Roll vs. Song Note Editor"; remove Song-hosted legacy-layout wording.
- `lib/ui/core/app_info_panel.dart`: remove the "Song-embedded Roll" entry.
- `AGENTS.md`: remove Song from the history cap, legacy-scope and unavailable-tab rules; keep Writer guidance and add that Song is removed.

- [ ] **Step 2: Review product docs**

Check `PRODUCT.md` and `DESIGN.md` for a Song-specific commitment. Change them only if one exists; otherwise leave them.

- [ ] **Step 3: Verify no live Song link remains**

Run: `grep -rn "song_workspace.md\|song_writer_guide.md\|Song-embedded Roll\|Temporarily unavailable" README.md AGENTS.md docs/songwriter.md docs/save_system.md docs/piano_roll.md docs/writer_guide.md lib/ui/core/app_info_panel.dart`
Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md docs lib/ui/core/app_info_panel.dart
git commit -m "docs: remove the Song workspace from live documentation"
```

---

### Task 11: Final verification

**Files:**
- No code changes expected.

- [ ] **Step 1: Run the full suite and analyzer**

Run: `dart format lib test && flutter analyze && flutter test`
Expected: clean analyzer, all tests pass.

- [ ] **Step 2: Grep for Song residue**

Run: `grep -rn "SongProject\|SongScreen\|songProjectProvider\|songSessions\|song_audio\|features/song\|SongSavePanel\|SongAudioPickerSheet" lib test`
Expected: only the one-time cleanup key strings and the `song_audio` directory literal in `lib/store/app_bootstrap.dart` / `lib/store/save_system_store.dart`.

- [ ] **Step 3: Verify the shell on two viewports**

Run the app on a compact viewport (393×844) and a wide viewport (1180×820). Confirm:
- The tabs read Fretboard, Piano, Roll, Writer, Settings.
- The Fretboard/Piano "Add to Writer" handoff lands on Writer.
- Settings opens from the last tab and returns to the previous workspace.
- No Song entry appears in navigation or the info panel.

- [ ] **Step 4: Verify data cleanup**

Seed a persisted `@muzician/song_sessions/v1` key, a v3 save with a `type: 'song'` entry, and a `song_audio/` file; relaunch. Confirm the Song key, Song save and `song_audio/` are gone, while Writer saves, `songwriter_audio/` and settings remain.

- [ ] **Step 5: Report**

Summarize the verification output, the compact/wide result and the data-cleanup result. Do not claim completion without the command output.
