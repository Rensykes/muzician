# Remove the Song workspace — design

Date: 2026-11-08
Status: proposed (awaiting approval)

## Intent

Song is no longer wanted. The tab has been disabled since the V2 shell, but its
feature code, persistence, save type, tests and documentation are still carried.
This change removes the Song workspace completely and deletes its stored data,
so the codebase and the app only contain the product we intend to ship.

The user accepted a fresh start, so no compatibility path is required for
existing Song projects. Writer data, saves, audio and settings must survive.

## Goals

- No Song tab, destination, placeholder, tab-index remapping or workspace
  preference.
- No Song-only models, rules, stores, UI, exports/imports or tests.
- Song saves and `song_audio/` files are removed on the next launch.
- Writer, Fretboard, Piano, Roll, Save System and Settings keep working exactly
  as they do today.
- Shared note/drum/audio content used by Writer is kept, under Writer-neutral
  names, with no Song wording left.

## Non-goals

- Redesigning Writer or changing any Writer behaviour.
- Migrating Song arrangements into Writer.
- Reworking the Save System beyond dropping Song entries.
- Rewriting archived plans, specs or agent reports under `docs/`; they are
  historical records and keep their text.

## Anti-goals

- A half-removal that leaves dead Song providers, routes, strings or save types.
- Losing Writer saves, Writer audio, settings or project folders.
- Leaving `song_project.dart` in place with Song-only classes still inside it.

## Constraints

- `lib/models/song_project.dart` is shared: Writer uses `NotePattern`,
  `NotePatternNote`, `DrumPattern`, `DrumLaneSequence`, `DrumLaneId` and
  `AudioAsset`; the piano roll and note player also use some of them.
- `SongAudioRepository`, the audio clip sink, the recorder driver and
  `downmixToMono` are used by Writer. They are Song-named but not Song-only.
- `song_audio_rules.dart` also holds `downmixToMono` and `computePeaksFromInt16`,
  which Writer audio and the repository need.
- `song_pattern_bridge_rules.dart` holds the NotePattern ↔ PianoRollState bridge
  used by the Writer melody pattern editor.
- Five files in `lib/features/song/` are Writer-facing shared UI: the drum
  machine body, drum library, drum-loop save panel, audio clip body and audio
  picker sheet. Writer's drum library, My Loops and record/import flows depend
  on them.
- The Save System persists `SongProjectSnapshot` entries and previews them in
  the save browser.
- The shell currently remaps the old persisted workspace value `song` to the
  Writer tab; removing the tab also removes the remap and the extra index.

## Approaches

### A. Tab and navigation only

Delete the disabled destination, `_UnavailableSongWorkspace`, the index remap
and the doc/AGENTS mentions. Keep every Song file, store and save type.

Trades off nothing technically, but leaves ~12k lines of unreachable code, 45
Song-named test files and a persisted save type for a product we do not want.
Rejected: it does not match "discard it".

### B. Whole feature, neutralise shared infrastructure (chosen)

Delete every Song-only file, split the shared model and audio helpers into
Writer-neutral files, drop Song saves during hydration and remove Song from
navigation, tests and live docs.

Trades off a wider diff and a mechanical rename across roughly 40 import lines,
but leaves a coherent codebase with no Song residue and no risk to Writer data.

### C. Whole feature, keep the Song-named shared files

Same as B, but keep `song_project.dart`, `song_audio_repository.dart`,
`song_audio_rules.dart` and the other Song-named files after pruning them.

Trades off a smaller diff for permanent misleading names and "song" references,
which is exactly what this change is meant to remove. Rejected.

## Design

### 1. Shell and navigation

- `contentWorkspaceNames` becomes
  `['fretboard', 'piano', 'roll', 'writer']`; the shell tabs become
  0 Fretboard, 1 Piano, 2 Roll, 3 Writer, 4 Settings.
- Remove `songWorkspaceTabIndex` and the remap in
  `contentWorkspaceTabForPreference` / `contentWorkspacePreferenceForTab`.
  Unknown values (including a persisted `song`) fall back to Writer.
- `main.dart`: delete the Song nav destination, `_UnavailableSongWorkspace`,
  the `_screenLabelForTab` special case, the `_setTab` Song guard, and the Song
  audio provider overrides/imports. Update the initial tab and handoff targets
  from 4 → 3 and Settings from 5 → 4.
- Keep `nav_<Label>` semantics; the Song key disappears.

### 2. Shared content model

Rename `lib/models/song_project.dart` to
`lib/models/arrangement_content.dart` and keep only:
`DrumLaneId`, `NotePatternNote`, `NotePattern`, `DrumLaneSequence`,
`DrumPattern`, `AudioAsset`.

Delete `SongTrackType`, `SongPatternType`, `SongProjectConfig`, `SongTrack`,
`SongClipInstance`, `AudioClipPattern`, `SongMarker` and `SongProject`.
Update the import in every file that still needs the kept types.

### 3. Shared audio infrastructure (Writer keeps)

- `lib/store/song_audio_repository.dart` → `lib/store/audio_repository.dart`,
  class `SongAudioRepository` → `AudioRepository`. Remove the Song bundle
  method `writeImportedBundleAsset` and the `song_bundle_rules` import. The
  default subdir becomes `writer_audio` so a future no-subdir caller can never
  write into the directory this change deletes. Writer keeps using
  `songwriter_audio`, so its files are not orphaned.
- Move `SongAudioClipSink` / `NoopSongAudioClipSink` out of
  `song_playback_store.dart` into `lib/store/audio_clip_sink.dart` as
  `AudioClipSink` / `NoopAudioClipSink`.
- `lib/store/song_audio_player_sink.dart` → `lib/store/audio_player_sink.dart`
  (`AudioPlayersClipSink` keeps its name).
- `lib/store/song_audio_recorder_store.dart` → keep only the status enum,
  driver interface and provider in `lib/store/audio_recorder_core.dart`
  (`AudioRecorderStatus`, `AudioRecorderDriver`, `audioRecorderDriverProvider`).
  Delete `SongAudioRecorderNotifier` and its state.
- `lib/store/song_audio_recorder_driver_impl.dart` →
  `lib/store/audio_recorder_driver_impl.dart`.
- Move `downmixToMono` and `computePeaksFromInt16` from
  `song_audio_rules.dart` into `lib/schema/rules/audio_rules.dart`; delete the
  rest of that file.
- `lib/schema/rules/song_pattern_bridge_rules.dart` →
  `lib/schema/rules/pattern_bridge_rules.dart`, keeping both NotePattern ↔
  PianoRollState conversions. Drop the Song-only `songHighlightedNotes` and
  `songKey` parameters from `pianoRollStateFromNotePattern`.
- Update Writer imports in `songwriter_audio_sink.dart`, the stretch/slice
  controllers, recorder store, melody pattern editor, `main.dart` and the
  profile harness.

### 4. Song UI: move the Writer-facing files, delete the rest

Writer imports five files from `lib/features/song/`. They are shared UI and
must move, not disappear:

- `drum_machine_editor.dart` → `lib/features/songwriter/drum_machine_editor.dart`.
  Keep `DrumMachineEditorBody` (already provider-agnostic and embedded by
  `drum_pattern_sheet.dart`); delete the Song-only `DrumMachineEditor` wrapper
  and its `songProjectProvider` code.
- `drum_library_sheet.dart` → `lib/features/songwriter/drum_library_sheet.dart`.
- `drum_loop_save_panel.dart` → `lib/features/songwriter/drum_loop_save_panel.dart`.
  `DrumLoopSnapshot` and the `drum_loop` save type stay.
- `song_audio_clip_body.dart` → `lib/features/songwriter/songwriter_audio_clip_body.dart`
  (class `AudioClipBody` keeps its name).
- `song_audio_picker_sheet.dart` → `lib/features/songwriter/songwriter_audio_picker_sheet.dart`,
  class renamed `SongwriterAudioPickerSheet`, dropping the Song-shaped
  `trackId`/`startTick` parameters Writer always passes as `''`/`0`.

Update `drum_pattern_sheet.dart`, `songwriter_audio_clip_sheet.dart`,
`songwriter_audio_lane_row.dart` and `songwriter_audio_actions.dart` to the new
paths.

Then delete the remaining 13 Song feature files:
`song_arranger_timeline.dart`, `song_audio_actions.dart`,
`song_audio_recorder_sheet.dart`, `song_clip_action_bar.dart`,
`song_coach_steps.dart`, `song_export_actions.dart`, `song_feature.dart`,
`song_import_picker_sheet.dart`, `song_note_pattern_editor.dart`,
`song_pattern_editor_launcher.dart`, `song_save_panel.dart`, `song_screen.dart`
and `song_track_header.dart`.

Other Song-only code to delete:

- `lib/models/song_playback.dart`.
- Rules: `song_bundle_rules.dart`, `song_from_writer_rules.dart`,
  `song_import_rules.dart`, `song_playback_rules.dart`, `song_render_rules.dart`,
  `song_rules.dart`, `song_split_rules.dart`, `song_audio_export_rules.dart`.
- Stores: `song_bundle_import.dart`, `song_playback_store.dart`,
  `song_project_store.dart`, `song_sessions_store.dart`.
- Save System: `SongProjectSnapshot` in `lib/models/save_system.dart`; the Song
  branch in `lib/ui/save_previews/save_preview_thumbnail.dart`
  (`_SongMiniPainter`); the Song summary, icon and `instrumentFilter == 'song'`
  branch in `lib/ui/save_browser_panel.dart`; the Song config-sync branch in
  `lib/store/save_system_store.dart`; the Song branch in
  `lib/store/project_config_sync.dart`.
- Bootstrap: Song session hydration, validation cases, storage-key checks and
  the `Song drafts` recovery label in `lib/store/app_bootstrap.dart` and
  `lib/store/persisted_data_recovery_store.dart`.
- Profile harness: Song view mode, `_ProfileSongProjectNotifier`,
  `_withControlledSongAudioClip`, `songFromSongwriter`/`song_playback_rules`
  usage, Song provider overrides and `buildSongPlaybackProfileManifest` in
  `lib/profile_writer_playback.dart`.

### 5. Persisted data cleanup (fresh start accepted)

On hydration, once:

- Remove `@muzician/song_sessions/v1` and `@muzician/song_session/v1`.
- Drop save entries whose serialised snapshot has `type: 'song'` or
  `instrument: 'song'` while deserialising the Save System, so the old type is
  never parsed into a `FretboardSnapshot`. Writer links and non-Song saves are
  preserved; folders are kept even if a Song save was their only child.
- Delete the legacy `song_audio/` directory; keep `songwriter_audio/`.
- A persisted `lastContentWorkspace: 'song'` resolves to Writer through the
  existing unknown-value fallback.

### 6. Tests

Move and split tests for code that survives; delete the rest.

- Move to `test/store/`: `song_audio_repository_test.dart` →
  `audio_repository_test.dart`, `song_audio_repository_subdir_test.dart` →
  `audio_repository_subdir_test.dart`, `song_audio_repository_stretch_test.dart`
  → `audio_repository_stretch_test.dart`, `song_audio_player_sink_profile_test.dart`
  → `audio_player_sink_profile_test.dart`.
- Move `test/schema/rules/song_pattern_bridge_rules_test.dart` →
  `pattern_bridge_rules_test.dart` and drop the Song-only bridge parameters.
- Split `test/schema/rules/song_audio_rules_test.dart`: keep the
  `downmixToMono` / `computePeaksFromInt16` groups in a new
  `audio_rules_test.dart`; delete the Song tick/measure cases.
- Split `test/models/song_project_test.dart`: keep `NotePatternNote`,
  `DrumPattern`, `AudioAsset` coverage in `arrangement_content_test.dart`;
  delete `SongProject` and `AudioClipPattern` coverage.
- Move the Writer-facing UI tests to `test/features/songwriter/`:
  `drum_machine_editor_test`, `drum_library_test`, `drum_loop_save_panel_test`,
  `drum_clear_test`, `drum_fill_menu_test`, `drum_audition_stop_test`,
  `song_audio_clip_body_test`, `song_audio_picker_sheet_test`, and the drum
  cases of `shared_editor_theme_test`.
- Delete the remaining Song workspace feature/rule/store tests and the Song
  sections of `test/profile_writer_playback_fixture_test.dart`.
- Keep the Writer model tests named after the musical `SongBlock` / `SongSection`
  / `SongLane` domain: `test/models/song_block_*`, `test/models/song_section_test`
  and the Writer rule tests. "Song" there is composition language, not the
  removed workspace.
- Update `test/schema/rules/songwriter_resolve_test.dart` (it builds a
  `SongProject`), `test/main_startup_test.dart` (no Song destination or screen),
  `test/store/app_bootstrap_startup_test.dart` (new tab count, no Song remap),
  `test/store/project_config_sync_test.dart` (no Song sync),
  `test/store/save_system_store_test.dart` (no Song snapshot),
  `test/store/save_system_store_migration_test.dart` and
  `test/features/save_system/recovery_export_test.dart` (legacy song keys are
  cleaned rather than recovered).
- Add a focused Save System test that a persisted Song save is dropped while a
  Writer save survives.

### 7. Documentation and agent guidance

- `README.md`: remove the Song row, update the feature overview and project
  structure list.
- Delete `docs/song_workspace.md`.
- Rename `docs/song_writer_guide.md` → `docs/writer_guide.md`, remove the Song
  transport/timeline/clip/marker/bridge sections, and update the Writer-only
  parts and links.
- `docs/songwriter.md`: remove the "Song is temporarily unavailable" and Song
  destination wording; link the Writer guide.
- `docs/save_system.md`: remove `SongProjectSnapshot`, the Song save panel row
  and the `song_audio/` wipe wording.
- `docs/piano_roll.md`: remove the "Legacy Song host" and "Standalone Roll vs.
  Song Note Editor" sections and the Song-hosted legacy-layout wording.
- `lib/ui/core/app_info_panel.dart`: remove the user-visible "Song-embedded
  Roll" entry.
- `AGENTS.md`: remove Song from the history, legacy-scope and unavailable-tab
  rules; keep Writer guidance.
- Review `PRODUCT.md` and `DESIGN.md`; change them only if they make a
  Song-specific commitment.

## Verification

1. `flutter analyze` clean.
2. `flutter test` green, including the new Song-save-drop regression test.
3. `grep -rn "SongProject\|SongScreen\|songProjectProvider\|songSessions\|song_audio\|features/song" lib test` returns only intentional Writer-neutral names and the one-time cleanup key strings.
4. Launch on a compact and a wide viewport: tabs read Fretboard, Piano, Roll,
   Writer, Settings; Writer handoff from Fretboard/Piano lands on Writer;
   Settings opens at the last tab; no Song entry anywhere.
5. Seed a persisted Song save and `song_audio/` file, relaunch, confirm they are
   gone and Writer saves/audio remain.
6. `dart format` on changed paths.

## Risks

- The Save System filter runs before snapshot parsing; a missed path could
  misparse an old Song save as Fretboard. The regression test covers it.
- Removing the extra tab index shifts hardcoded indices; `flutter test` plus the
  handoff check covers it.
- Writer audio must keep pointing at `songwriter_audio`; the cleanup only
  removes `song_audio`.
- Historical docs keep Song links; that is intentional and limited to archived
  material.
