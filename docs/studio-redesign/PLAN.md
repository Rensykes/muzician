# Studio implementation plan

Revision 2 — 18 October 2026. Status: **APPROVED** — independent fresh-context review, revision 2 (`reviews/plan-r2.md`). User confirmed two selectable themes and scope of four workspaces plus shared panels/Settings. Implementation must not start until a fresh-context reviewer explicitly approves this plan. Subsequent changes to scope/contracts require another review; routine implementation choices do not.

## 1. Objective and deliverables

Implement the selected Studio interface, not just a palette swap, for Fretboard, Piano, Piano Roll and Writer. Studio original graphite/mint is default; Studio Muzician changes palette with the same layout. Settings stores device-local selection. Song remains accessible with its existing layout/palette and semantics. Root PRODUCT.md and DESIGN.md specify target direction; ledger records actual shipped phase.

Deliver branch `codex/studio-redesign`, functional code, focused regression coverage, updated feature docs/README, compact and wide screenshots, analyzer and relevant test evidence. No deployment, PR or destructive resets requested. Existing user iOS changes must remain byte-for-byte intact.

Reference images are visual hierarchy guidance, not specifications of music or behavior. Known artifacts (incorrect guitar positions, misplaced Add to Writer in Writer, fake Timing/Sound, inconsistent grid durations) must not be reproduced.

## 2. Current architecture and risks

- `main.dart` owns app, IndexedStack, navigation, private Fretboard/Piano/Settings screen composition. Preserve hydration, project-key sync, linked-native-edit callbacks and tab state.
- `MuzicianTheme` is static, used in 64 feature/shared UI files plus painters and main. Merely changing MaterialApp ThemeData will leave hardcoded palettes. Some descendants create local `Theme(data: MuzicianTheme.dark())`; all in-scope overrides must be removed or inherit the selected extension.
- `InstrumentScreen` currently has canvas/detection/dock; voicing/scale/settings are sheets. Studio needs an actual inline inspector, bounded correctly on small/short screens, without mounting duplicate provider-driven editors invisibly.
- Roll embeds into Song/Writer with capability flags. It has raw-pointer gesture math and synchronized scroll controllers that must be preserved.
- Writer screen sheet is large (~4k lines), contains nontrivial placement/library/audio operations. Limit changes to composition/presentation and token injection; keep state/rules/canonical-save flows intact.
- Root Navigator dialogs can lose local host scope if built with the wrong context. Studio sheets/routes must resolve the LIVE app theme rather than freeze caller ThemeData; legacy Song remains explicitly fixed through embedded editors/dialogs. See concrete route contract below.
- Settings persistence is JSON under `@muzician/settings/v1`. Add optional field, no migration reset. Theme selection must not reset other settings or be saved in project snapshots.

## 3. Architecture decisions and stable interface

### Theme

Add `AppThemeVariant { studio, studioMuzician }` in a small model file. `AppSettings.themeVariant` defaults to studio; absent/unknown JSON value -> studio. `SettingsNotifier.setThemeVariant` performs copyWith + persistence. Runtime flow:

`Settings action → settingsProvider.themeVariant → Consumer app ThemeData → inherited StudioPalette → widgets and painters`.

Create immutable `StudioPalette extends ThemeExtension<StudioPalette>` in `lib/theme/studio_theme.dart`. Public API locked before feature dispatch:

- `StudioPalette.of(BuildContext)` returns the current extension, fallback `legacy` when absent (existing tests/host Song stay safe).
- Static immutable `studio`, `studioMuzician`, `legacy` palettes.
- Fields use existing familiar names for migration: scaffoldBg, surface, dialogBg, textPrimary, textSecondary, textMuted, textDim, sky, teal, violet, purple, emerald, orange, red, glassBg, glassBorder, gradientColors, onAccent; `isStudio` indicates layout opt-in if needed, not a business feature flag.
- `StudioTheme.data(AppThemeVariant)` returns ThemeData + extension + readable component defaults.
- `StudioTheme.legacyData()` wraps legacy Muzician ThemeData with explicit legacy extension.
- No static mutable selected palette. No theme-keyed recreation of provider scopes or screens. Palette passed to painter constructors; repaint comparator includes palette changes.

`MuzicianApp` watches the preference. Song subtree receives explicit legacy Theme. Root nav/Settings follow chosen Studio palette. Shared widgets resolve nearest palette; shared dialogs use the live/fixed route contract below. A Song route using Roll with showBackground=false must retain both legacy layout and palette and preserve flags. Do not change Song's business code; a minimal wrapper/import boundary to preserve scope is allowed and tested.

### Route and embedded editor contract (R1.2)

Introduce a small app-level `StudioThemeSource` inherited value ABOVE MaterialApp/Navigator, rebuilt by the root settings Consumer. It exposes only the selected presentation variant, independent of nested ProviderContainers. It must not create a second mutable source of truth: settingsProvider remains canonical. `StudioRouteTheme` reads this inherited source in build for Studio, or uses fixed `legacyData()` when its launch-time **scope kind** is legacy. Capture the boolean scope kind, never the selected ThemeData or palette snapshot. This widget is placed INSIDE Flutter's captured theme wrappers, so it overrides a stale captured Theme with the live root variant. Its child keeps the same identity/key, retaining text controllers, scroll and local state. In tests without a root source, fallback to the nearest palette safely.

Route helpers expose a reusable builder wrapper/factory to bind caller scope kind. For `showWidgetSheet`, `showPickerSheet`, shared dialogs and information panels, wrap their builder content in `StudioRouteTheme`; any explicit surface color must be resolved inside that live wrapper, not frozen in the call arguments. Use transparent modal route background plus a live opaque content surface where needed. Material route scaffolds resolve Theme locally. Existing direct `showDialog`/`showModalBottomSheet` in owned feature files must adopt the same builder wrapper if they introduce captured local Theme/color values. Do not add a Consumer reading settings inside isolated editor containers.

Call-site ownership: P1a owns `_mockup_shell.dart`, `ui/core/*`, `ui/project_picker_sheet.dart`/other existing project helpers, main navigation and new route/source primitives. P1c owns Song's `song_pattern_editor_launcher.dart` fullscreen routes: wrap explicitly fixed legacy, including note/drum editors and nested modal children. P2 owns instrument dialog direct sites. P3 owns Roll direct sites. P4 owns Writer direct routes (structure, melody pattern, melody performance) and dialogs. The Writer melody route obtains live theme from `StudioThemeSource` above Navigator; its existing isolated ProviderContainer is created once and continues to own only editor data. Roll and shared editors consume Theme, not the isolated settings provider for palette.

Song nested shared controls get legacy palette and legacy layout; Studio layout branches in Roll/drum shared UI use the inherited palette scope. Root navigation follows the selected Studio palette even on Song; Song's own page and pushed editors remain unchanged. This is a temporary explicit boundary, not a third user theme.

Required tests before P1 gate: (a) root-container preference change while a shared Studio sheet with text input and scroll is OPEN changes its resolved palette and retains local state/route; (b) repeat for nested modal; (c) Song fullscreen note/drum route and nested modal remain legacy. P4 adds Writer isolated melody route version of (a), asserting same isolated container/edited notes. P3 verifies legacy Roll layout and capability flags in Song. Closing/reopening is not sufficient evidence.

### Ownership and sequencing

Only one agent owns a file at a time. Agents must not commit or reformat other owners' files. Parent integrates, updates ledger and runs cross-feature checks. When a task needs an out-of-scope file, message parent and wait for transfer. Shared files are completed before feature parallelism. Stable contracts are communicated in each dispatch.

| Phase/task | Model/effort | Exclusive ownership |
| --- | --- | --- |
| P1a palette + shared primitives + app root/nav/Settings UI | gpt-6.1-sol, high | lib/theme/*; lib/main.dart; lib/features/_mockup_shell.dart; lib/ui/*; lib/ui/core/*; theme/shared UI tests |
| P1b preference model/store + persistence tests | gpt-6-luna, xhigh | new lib/models/app_theme_variant.dart; AppSettings portion of lib/models/save_system.dart; lib/store/settings_store.dart; test/models/app_settings_test.dart; test/store/settings_store_test.dart |
| P1c shared cross-feature surfaces/boundaries | gpt-6.1-sol, high (P1a agent serially, or separate agent after API exists) | explicit shared Song allowlist below; DataRecoveryPanel; corresponding tests |
| P2 instrument workspaces | gpt-6.1-sol, high | lib/features/instrument_shared/*; lib/features/fretboard/*; lib/features/piano/*; main.dart instrument composition only AFTER P1a transfers file; corresponding feature tests; docs/fretboard.md, docs/piano.md |
| P3 Piano Roll | gpt-6.1-sol, high | lib/features/piano_roll/*; matching feature tests; docs/piano_roll.md |
| P4 Writer | gpt-6.1-sol, high | lib/features/songwriter/*; corresponding feature tests; docs/songwriter.md, relevant Writer sections docs/song_writer_guide.md |
| P5 documentation/token audit | gpt-6-luna, xhigh | README.md; docs/studio-redesign/coverage.md; read-only residual-color inventory; docs/save_system.md presentation/settings sections if needed |
| P5 integration/verification | parent + review subagent | only explicit integration fixes; ledger/evidence; final AGENTS review |

P1c bounded allowlist (presentation only, no Song business redesign):
- `lib/features/song/drum_machine_editor.dart`, `drum_library_sheet.dart`, `drum_loop_save_panel.dart`: theme inherited from host; Studio beat grouping/44px targets only in Studio scope, preserve Song legacy layout.
- `lib/features/song/song_audio_picker_sheet.dart`, `song_audio_clip_body.dart`: palette-aware shared Writer audio UI/painter, keep playback/import behavior.
- `lib/features/song/song_pattern_editor_launcher.dart`: fixed legacy fullscreen note/drum route boundary only.
- `lib/features/save_system/data_recovery_panel.dart`: Settings presentation; never modify backup actions/data semantics.
- If these import further shared presentation dependencies, enumerate them in phase report and get parent ownership assignment before edit. No wholesale `features/song/*` migration.
- Tests: existing Song note pattern editor, Writer drum library/backing audition and audio picker/clip tests plus palette-scoping test using these shared bodies; Settings recovery widget test. P1c finishes before P4 consumes the shared surfaces.

P1a and P1b may run together after interface agreement; P1a consumes enum/model after P1b writes it. P1c runs after P1a route/palette API stabilizes and before P1 completion. P2/P3/P4 may run together only after P1 passes and main.dart is transferred; max three active implementation agents. P5 Luna documentation can run when a slot frees and phase reports exist.

## 4. Detailed phases and acceptance gates

### P0 — specification and baseline

1. Preserve original iOS hashes and branch/base in PROGRESS.md (done).
2. Write PRODUCT/DESIGN/PLAN; record explicit user answers (done).
3. Baseline `flutter analyze --no-pub`; record pre-existing failures separately.
4. Fresh reviewer `fork_turns=none`, no prior conversation. Provide repository path and request only; reviewer reads files and critiques scope/architecture/tests/ownership. Write `reviews/plan-rN.md` with APPROVED or CHANGES REQUIRED and blockers. Parent addresses findings in plan/spec; repeat until approved, retaining verdict history.

### P1 — foundation and persistent theme

1. Implement preference/backward-compatible parse/copyWith/toJson and provider setter. No snapshot version changes.
2. Implement palettes/ThemeData and contrast tests for text and primary controls in both palettes. Legacy palette exists solely for excluded scope/fallback.
3. Wire app theme, navigation and Settings Appearance selector with descriptive labels; immediate switch, persisted reload. Keep existing Settings options/recovery controls.
4. Migrate shared shell, project chip/picker, save browser, transport and dialogs in `lib/ui` to inherited palette. Remove decorative glass defaults for Studio while preserving legacy behavior.
5. Full workspace title independent of project context in shared header where reusable. Keep 44px named actions. No premature instrument layout change before P2.
6. Song boundary: local legacy theme; modal routes captured correctly. Root navigation may follow Studio even while Song content remains legacy (documented temporary boundary).
7. Tests: old/unknown/new settings decode, round trip, copyWith preservation; set/persist/rehydrate; theme switching with existing provider state and open sheet; shared modal caller scope; legacy Song/embedded editor palette; representative token contrast; Settings header at narrow/text-scale.
8. Run analyze and focused P1 tests. Gate: palette API stable, no unresolved cross-scope route issue, hashes intact.

### P2 — Fretboard/Piano Studio layouts

1. Replace InstrumentScreen composition with project/title row, instrument-specific controls, native playable canvas, compact detection/actions, inline inspector (Notes/Voicings/Setup) and explicit Scale/library access. Default Voicings; allow collapse. Wide uses content + inspector, compact/short uses scrollable layout without shrinking canvas below current usable sizes.
2. Pass existing picker/setup widgets or builders from private main compositions; don't duplicate logic/provider state. Move project chip to context row rather than extracting it by fragile type/position inspection. Keep linked edit target callbacks and SavePanel construction intact.
3. Add visible Save idea action using current save flow; Add to Writer reuses complete current recognized/exact flow. Notes tab retains compatible scales/focus and Clear. Scale key confirmation remains unchanged.
4. Fretboard: Free/Chord, tuning and capo readable; fix CAPO wrap and touch targets. Preserve painter/scroll threshold/capo math. Piano: range and octave/inversions remain available; no glissando or new playback transport.
5. Recolor native canvas, diagrams, controls and all instrument-specific sheets via resolved palette; inspector settings inherit selected theme. Native geometric colors may stay distinct where musical identity requires it.
6. Tests: existing bindings and handoff suites; new compact/wide populated/empty/long-name layout; inspector switching/collapse; disabled Free explanation; exact handoff remains; theme switch selected notes unchanged; piano/fretboard repaint tokens. Fix only regressions caused by changes; record pre-existing limitations.
7. Update feature guides, reconciling known obsolete default/range/renderer/mode claims. Gate: UI is structurally Studio, not just recolored legacy; no lost actions or clipped canvas.

### P3 — Piano Roll Studio

1. Remove hardcoded local theme override; inherited palette for standalone/embedded modes and painters.
2. Recompose project/title, transport and visible tools with dominant grid. Retain raw Listener/pinch/scroll/resize math untouched apart from palette arguments.
3. Add bounded inspector Stack Builder/Selection/Tools; preserve all five tools, Quick, detection, column selection, clear/delete, range and snap. Make existing snap/range reachable on mobile. Keep rewind and capability flags.
4. Utility actions Scale/Hum recorder/Save/Import with real callbacks. No velocity, automation, extra recording type or Writer transfer. Translate labels only if necessary and update tests/docs consistently.
5. Palette injection includes note normal/selected/multi/active-column/playhead distinctions and shouldRepaint. Selection/time state survives theme switch.
6. Tests: grid gestures and existing screen/builder/hum tests; 390×844/844×390/1024×768 with expanded inspector; mobile snap/range, all tool entries, embedded flags/theme. Gate: no grid squeezed to unusable/negative height, no unbounded nested scroll.

### P4 — Writer Studio

1. Theme migration for header, sheet, sections, blocks, wheel, mixer, save dialogs and audio/melody/drum/strum editors. Preserve non-presentational logic and journal/history semantics.
2. Project/title + Save version + overflow; compact transport; named snapshots labelled Writer versions while Section blocks stays. Draft wording explains named-version delta without claiming unsaved loss.
3. Reduce excessive spacing, structure Harmony cells and lane/source headers with readable chord/degree/lyrics. Keep four-cell grid and context menus; expose selected block's common actions without removing advanced actions. Contextual editor may reuse existing sheets if inline duplication would risk semantics; document concrete choice.
4. Wide single section uses available width sensibly (full-width bounded sheet or real inspector). Multi-section layout remains understandable, with ruler navigation/autoscroll maintained.
5. Strum editor: 16th steps grouped by beat, 44px targets, horizontal/vertical scroll for long patterns, no arbitrary7+7+2 wrap. Keep source eligibility/exclusivity and Unassigned silence; down/up/off cycle unchanged.
6. Preserve all lane types/editors, repeats/per-verse lyrics, save all-uses/standalone, undo/new protection, exact labels and confirmation dialogs. No fake Add to Writer command.
7. Tests: header/version menus, key confirmation, block action reachability, lane/mixer/strum layout, empty/populated/narrow/wide, exact/source exclusivity, relevant existing Writer feature suites and store regressions. Gate: canonical music state unchanged by theme/layout; all editors usable.

### P5 — integration and closure

1. Inventory residual `MuzicianTheme` and hardcoded colors across in-scope files. Classify retained values (legacy Song, physical canvas geometry/colors, intentional status) vs missed migration. Do not mechanically rewrite unrelated Song files.
2. README feature overview/settings/theme/renderer corrections; all feature docs describe shipped behavior. PRODUCT/DESIGN status updated to match implementation. Review AGENTS: add short persistent palette/painter/Song boundary rule only if architecture now warrants it.
3. Run format on changed Dart only, full `flutter analyze --no-pub`, focused tests per phase; once integrated run full `flutter test --no-pub` if feasible (suite is large). If failure, diagnose; do not repeat passing suites without new changes.
4. Build/run iOS simulator with explicit Xcode path. Inspect all four populated screens plus Settings in Studio and switch to Studio Muzician. Capture at least portrait and wide/landscape; open representative picker, save and mixer/strum/Stack Builder. Do not reset existing user's project; use a separate test project if needed, preserving its saves.
5. Verify theme persists after restart; switching doesn't change current project/notes/history and open dialogs use correct colors. Smoke-test excluded Song and a Song modal/embedded Roll; no redesign required.
6. Final independent accessibility/code review against actual diff and spec; fix concrete regressions, record known pre-existing limitations (e.g. canvas semantics). No blanket WCAG claim.
7. Ledger checklist includes commands/results, screenshot paths, agent ownership, unresolved findings and exact next action. Completion only with all requested phases implemented and verified; if usage interrupted, leave honest in-progress state.

## 5. Required verification matrix

| Scenario | Compact | Wide/short | Both themes | Evidence |
| --- | --- | --- | --- | --- |
| Fretboard Free/Chord, voicing, tuning/capo, detection/handoff | yes | yes | yes | widget + simulator |
| Piano exact MIDI, inversion/range, save/handoff | yes | yes | yes | widget + simulator |
| Roll grid/tools/inspector, selection vs column, embedded flags | yes | yes | yes | regression/widget + simulator |
| Writer populated/empty, section/block, mixer/strum, version | yes | yes | yes | feature tests + simulator |
| Settings theme persistence and legacy decode | yes | narrow1.5x | yes | unit/provider/widget |
| Long project/custom exact name; keyboard/insets | yes | yes | representative | widget |
| Song legacy boundary and modal/embedded Roll | smoke | smoke | switch from either | widget/smoke |

## 6. Resume protocol

Each agent reads AGENTS.md, PRODUCT.md, DESIGN.md, PLAN.md, PROGRESS.md and its domain file first. Before editing, read callers. Append a report under `docs/studio-redesign/agent-reports/` with files touched, tests/commands/results, remaining risks and next action. Parent alone edits central ledger to avoid conflicts. Do not rely on chat history for a handoff. Persist reports even when tests are blocked. Preserve unrelated edits and never reset worktrees or user projects. Model assignments are user-authorized: Sol 6.1 for complex cross-widget work; Luna xhigh for bounded model/persistence/docs work.

## Revision history

- R1 independent reviewer: CHANGES REQUIRED; report `reviews/plan-r1.md`.
- R2: adds explicit P1c allowlist/ownership and dependent verification; replaces ThemeData capture with app-root inherited theme source + scope-aware live route wrapper; fixes Song embedded Roll layout to legacy; adds open/nested/isolated editor state-preservation tests. Baseline analyzer PASS is in PROGRESS.md.

- R2 independent reviewer: APPROVED, `reviews/plan-r2.md`; implementation authorized under stated gates. Corrected nonblocking project_picker_sheet filename.

- Implementation R1/R2 review: strum beat-group sizing clarified to canonical `ticksPerBeat`, rather than assuming four ticks in every meter. Four remains correct for quarter-note beats; eighth-note beats use two. This preserves existing music rules and prevents groups crossing measure boundaries. Final independent review APPROVED in `reviews/implementation-r2.md`.
