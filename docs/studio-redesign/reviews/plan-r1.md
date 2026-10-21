# Studio plan review — revision 1

Date: 18 October 2026

Verdict: **CHANGES REQUIRED**

Independent review of PLAN.md revision 1, PRODUCT.md, DESIGN.md, PROGRESS.md and the actual application integration points. No implementation changes made. The overall design is feasible and the proposed preservation of provider identity, save semantics, gesture math and painter repaint dependencies is sound. Two architecture/ownership gaps need resolution before dispatch.

## Blocking findings

### R1.1 — Assign shared Writer/Settings surfaces outside the current ownership map

PLAN.md lines 48–54 assigns P4 only `lib/features/songwriter/*`, P1a only theme/main/shared UI, and no owner to `lib/features/song/*` or `lib/features/save_system/*`. These paths contain requested surfaces, not only excluded Song UI:

- `lib/features/songwriter/drum_pattern_sheet.dart:14` imports `DrumMachineEditorBody` from `lib/features/song/drum_machine_editor.dart`. That body and its fill controls use static Muzician colors; it also imports `drum_library_sheet.dart` and `drum_loop_save_panel.dart`. Its current 32px step cells are below the new Studio controls contract.
- `lib/features/songwriter/songwriter_audio_actions.dart:35` mounts `SongAudioPickerSheet` from `lib/features/song/song_audio_picker_sheet.dart`; Writer audio rows and the clip sheet use `AudioClipBody` from `lib/features/song/song_audio_clip_body.dart`. These also contain static presentation colors.
- Settings mounts `DataRecoveryPanel` at `lib/main.dart:1038`, implemented with static glass/colors under `lib/features/save_system/data_recovery_panel.dart`.
- `lib/features/song/song_pattern_editor_launcher.dart:21` and `:29` push fullscreen note/drum editor routes through the root Navigator. Wrapping `SongScreen` in a Theme alone does not carry that local Theme into those route builders. A boundary edit is necessary and permitted by the plan, but has no assigned owner.

**Required revision:** Add an explicit, bounded allowlist and single owner for these shared presentation files and the Song route boundary, with phase ordering. Include the drum library/save dependencies in the inventory. Specify context-based palette/layout behavior so these components adopt Studio in Writer while retaining the legacy appearance when used by Song. Do not move files or refactor music logic merely for ownership. Assign matching tests, including Writer drum/audio/library and Settings recovery presentation plus Song note/drum fullscreen route scope. Finish the relevant shared contract before parallel feature agents consume it, or explicitly transfer ownership at a defined gate.

**Approval check:** Every listed in-scope surface and route boundary has an owner and a verification target; “Song excluded” cannot cause shared Writer editors to be skipped or Song-specific layouts to be silently redesigned.

### R1.2 — Separate live Studio route inheritance from fixed legacy Song scope

PLAN.md lines 20 and 40 require shared routes/dialogs to capture the caller's ThemeData. PRODUCT/DESIGN and P1/P5 simultaneously require a theme change to update an already-open panel while preserving its state. Unconditional ThemeData capture does not satisfy that contract.

The installed Flutter implementation documents that `InheritedTheme.capture`/`captureAll` freezes captured themes (`packages/flutter/lib/src/widgets/inherited_theme.dart:60` onwards). `showDialog` and `showModalBottomSheet` already capture themes between the caller and Navigator. A newly added `Theme(data: Theme.of(caller), ...)` or `captureAll` around every Studio route would pin its launch-time palette. Conversely, `MaterialPageRoute` from the local Song subtree currently escapes into the global root theme. The isolated `ProviderContainer` in Writer/Song melody editors also means a generic theme Consumer inside an embedded editor must not accidentally read a fresh default Settings provider.

**Required revision:** State the concrete route contract before P1a starts. For example: Studio routes inherit the live root theme without copying a selected ThemeData snapshot, while Song fullscreen routes get an explicit constant legacy wrapper; any necessary nested captured scopes must rebuild from the live app preference above isolated editor provider containers. An equivalent scope-aware implementation is fine. Enumerate the helper/direct-route call sites that need adaptation and establish ownership under R1.1. Avoid a blanket capture recommendation.

**Required regression evidence:** Open a Studio sheet/dialog containing local input or scroll state, switch the app preference through the root container, and assert new resolved colors with the same route and local state. Repeat with a nested modal and a Writer melody route using its isolated container. Open Song note/drum fullscreen routes and a nested modal and verify they remain legacy after switching the global preference. Keep the existing notes/playback/history assertions; closing and reopening a modal does not prove this requirement.

**Approval check:** The plan describes how both live updates and fixed legacy scope work, rather than delegating contradictory requirements to individual agents.

## Nonblocking suggestions

- Clarify whether the shared Roll editor inside Song retains its current layout as well as its palette. The target says Song keeps its existing layout, while P3 currently applies a structural Roll redesign to all hosts. Prefer explicit legacy layout selection if the exclusion includes the editor; otherwise document the narrow shared-editor exception consistently. Preserve all existing capability flags either way.
- Link concrete test groups in each phase report. Useful existing regressions include `test/features/instrument_shared/instrument_screen_layout_test.dart` (actual compact gestures, scroll and 1.6× text), `linked_instrument_edit_target_test.dart`, `writer_handoff_test.dart`, `test/features/song/song_note_pattern_editor_test.dart`, and Writer drum audition/library tests. Update assertions about replaced dock widgets while preserving the interaction guarantees.
- Record the baseline analyzer result before implementation. It was still absent from the ledger inspected for this review; the plan already requires it.

## Verified strengths

- `AppSettings` is separate from instrument/project snapshots, and the optional-field approach fits the existing JSON/copyWith/SettingsNotifier code without a migration reset.
- The app uses a stable IndexedStack and provider scope, so a Consumer-based root ThemeData update can preserve workspace state without rebuilding provider containers.
- The plan correctly preserves the native-edit callbacks held in main.dart, canonical Writer Save behavior, project key confirmation and exact-Harmony spelling boundaries.
- Roll's existing capability flags and isolated host containers are explicitly recognized. Palette arguments and repaint checks cover the real CustomPainter implementation model.
- Compact/wide/short viewport, persistence, save/handoff, contrast and state-preservation gates are substantive. The document does not promise new music features from concept-image artifacts.

No tests were executed for this document-only review. Source and SDK inspection established the findings above. Revise the plan, then submit the updated plan for a new explicit approval verdict before implementation.
