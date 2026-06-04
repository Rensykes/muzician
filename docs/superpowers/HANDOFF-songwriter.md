# Songwriter Initiative — Session Handoff

**Last updated:** 2026-06-03
**Purpose:** Everything a fresh session needs to continue the Songwriter feature. Read this first.

---

## 1. What the Songwriter is

A new **"Writer"** tab (6th nav tab) for arranging a song as **Sections → per-section parallel Lanes → Blocks**, where each block references an existing **save** (a fretboard/piano voicing, scale, etc.) or, in the **Harmony lane**, a chord shown as a Roman numeral. v1 blocks are **silent visual guidance** (the musician plays along); playback is metronome + (future) audio lanes. Full vision + decisions: `docs/superpowers/specs/2026-06-02-songwriter-v1-design.md`.

## 2. Phase status

| Phase | What | Status |
|-------|------|--------|
| **A** | Save grid view + `SaveBrowserPanel` palette (`onPick`) | ✅ merged to `main` |
| **B1** | Foundation: model `lib/models/songwriter.dart`, rules `lib/schema/rules/songwriter_rules.dart`, store `lib/store/songwriter_store.dart`, snapshot dispatch | ✅ merged to `main` |
| **B2a** | Tab UI: header, section cards, lanes, harmony + save blocks, structure editor, save/load | ✅ merged to `main` |
| **B2a polish** | Default C major, undo-snackbar deletes, value pills, bar ruler + gridlines, drop header title, empty hint | ✅ DONE on branch **`worktree-songwriter-ux-polish`** (8 commits) — **NOT merged, awaiting review** |
| **B2b** | Playback transport + playhead + metronome, drag move/resize, tap-block→open-save, Make-Unique/Re-link | ✅ DONE on branch **`worktree-songwriter-ux-polish`** (9 commits on top of polish) — **NOT merged, awaiting review** |
| **Chord wheel** | Radial diatonic picker feeding the harmony lane | ✅ DONE on branch **`worktree-songwriter-ux-polish`** (8 commits on top of B2b) — **NOT merged, awaiting review**. Plan: `docs/superpowers/plans/2026-06-03-songwriter-chord-wheel.md` |
| **C v1 (CAGED voicings)** | Tap harmony block → CAGED voicing suggestions → 1-tap accept persists SaveEntry + bar-aligned save-lane block | ✅ DONE on branch **`worktree-songwriter-ux-polish`** (8 commits on top of chord wheel). Spec: `docs/superpowers/specs/2026-06-04-songwriter-c-voicings-design.md`. Plan: `docs/superpowers/plans/2026-06-04-songwriter-c-voicings.md`. **NOT merged, awaiting review.** |
| **C v2-a** | 3rd-above harmony — per harmony block, full chord shifted up a diatonic 3rd, on piano (`PianoSnapshot`). Adds Voicings\|Harmony tabs to the sheet. Folder: `Songwriter harmonies` (until v2-b lands and overrides) | ✅ spec + plan done. Plan: `docs/superpowers/plans/2026-06-04-songwriter-c-v2a-third-above.md` (6 tasks, TDD). Ready for execution. |
| **C v2-b** | Library-match — third `Library` tab; chord-match (`pendingChord.symbol == chordSymbol`) ∪ scale-fit (notes ⊆ key scale). **Prerequisite**: project naming + linked top-level folder (`SongwriterProjectSnapshot.name`). Retroactively changes C v1 + v2-a folder behavior — both now write into the song's folder. Search scope = song folder + descendants. | ✅ spec + plan done. Plan: `docs/superpowers/plans/2026-06-04-songwriter-c-v2b-library-match.md` (9 tasks, TDD). Assumes v2-a landed first. Ready for execution. |
| **C v3+** | Arpeggio/sequence save type, 6th-above/5th-below harmony intervals, dim/aug/7th voicings, fretboard 3rd-above variant, ranking improvements | ⬜ each needs brainstorm + spec + plan |

## 3. FIRST STEPS for the new session

1. **Merge the polish branch** (after the user confirms review):
   ```bash
   cd /Users/francescolacriola/dev/ws/muzician
   git checkout main && git merge worktree-songwriter-ux-polish
   ```
   The branch is `worktree-songwriter-ux-polish`; its worktree is at `.claude/worktrees/songwriter-ux-polish`. Verify `flutter test` (≈390 pass) + `flutter analyze` after merge.
2. **`main` is NOT pushed to `origin`** (Rensykes/muzician). Everything since `cf2ba72` is local-only. Push only if the user asks.
3. Execute **B2b** next (its plan is self-contained). Use `superpowers:subagent-driven-development` (or inline). Work in a fresh worktree branched from `main` *after* the polish merge.

## 4. Architecture map (current, post-B2a)

| Concern | File |
|---------|------|
| Model (immutable, copyWith/toJson/fromJson) | `lib/models/songwriter.dart` — `SongwriterConfig`, `SongSection`, `SongLane`, `SongBlock`, `SongLaneKind`, `SongwriterProjectSnapshot` |
| Snapshot dispatch | `lib/models/save_system.dart` `InstrumentSnapshot.fromJson` (branch `type=='songwriter'`). NOTE: `InstrumentSnapshot` is now `abstract` (was `sealed`) to allow the cross-file subtype. |
| Pure rules | `lib/schema/rules/songwriter_rules.dart` — `romanNumeralFor`, `blocksOverlap`, `makeSection/Lane/SaveBlock/HarmonyBlock`, `flattenedBarCount`, `laneNaturalLength`, `tileLaneBlocks` |
| Store (Riverpod `songwriterProvider`) | `lib/store/songwriter_store.dart` — CRUD, inserters (undo), `setBlockPlacement`, `makeBlockUnique`, `setKey/setTempo`, `newProject`, `loadProject`, `hydrate`, debounced session autosave `@muzician/songwriter_session/v1`, default **C major** |
| UI feature folder | `lib/features/songwriter/` — `songwriter_screen.dart`, `songwriter_header.dart`, `songwriter_section_card.dart`, `songwriter_lane_row.dart`, `songwriter_block_tile.dart`, `harmony_chord_sheet.dart`, `songwriter_structure_editor.dart`, `songwriter_save_panel.dart`, `songwriter_grid.dart` (BarRuler/BarGridPainter), `songwriter_undo.dart`, `songwriter_feature.dart` |
| Nav | `lib/main.dart` `_AppShellState.build` — `IndexedStack` index 4 = `SongwriterScreen()`, `_NavTab` "Writer" (`Icons.lyrics`); `initState` hydrates `songwriterProvider` |

## 5. Key reuse points for B2b

- **Transport template:** `lib/store/piano_roll_playback_store.dart` (`PianoRollPlaybackNotifier.startPlayback`, tick loop ~L122-157). B2b builds a NEW `SongwriterPlaybackNotifier` (the song transport `SongPlaybackNotifier` is bound to `songProjectProvider`, not reusable).
- **Metronome:** `NotePlayer.instance.playClick(accent: bool)` (`lib/utils/note_player.dart` ~L38). Wrap in an injectable sink provider like `pianoRollMetronomeSinkProvider` (`piano_roll_playback_store.dart:39`).
- **Tick maths:** ticksPerQuarter = 4; `beatTicks = beatUnit == 8 ? 2 : 4`; `measureTicks = beatTicks * beatsPerBar`; tick duration = `piano_roll_rules.durationForTickDelta(1, tempo)`.
- **Flatten:** `flattenedBarCount(sections)` (total bars after section repeats). For the playhead, map a global bar back to (section, localBar) by walking sections × repeat.
- **Isolated editor pattern (tap-into-save):** `lib/features/song/song_note_pattern_editor.dart` (`_isolatedContainer = ProviderContainer(...)`, `UncontrolledProviderScope`). For read-only save preview, see `lib/ui/save_previews/save_preview_thumbnail.dart` (`_painterFor`).
- **`settingsProvider.metronomeEnabled`** gates the click (`lib/store/settings_store.dart`).

## 6. Conventions (follow these)

- **TDD per task:** write failing test → run (fail) → minimal impl → run (pass) → commit. One concern per commit.
- **Widget-test gotchas:** the songwriter store debounces persistence 500 ms — after a mutation in a widget test, `await tester.pump(const Duration(milliseconds: 600))` to drain the Timer or the test fails with "A Timer is still pending". SnackBar actions need `pumpAndSettle` (slide-in) before tapping.
- **Commits:** Conventional Commits; end body with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Verify:** `dart format <changed>`, `flutter analyze` (must be clean), narrowest `flutter test`, plus a full sweep before finishing. Visual changes → serve-sim on the iPhone 17 Pro simulator (`xcrun simctl io booted screenshot`, `npx serve-sim tap <x> <y>` normalized 0..1).
- **Models:** `copyWith(...)` can't null a field via `??`; use an explicit `clearX` flag (see `SongSection.copyWith(clearLabel:)`).
- **Don't auto-merge to `main`** when the user says they'll review — land on a branch.
- The repo runs CAVEMAN response mode + superpowers skills; brainstorm before greenfield creative work, writing-plans before coding.

## 7. Open product decisions (surface to user before building where noted)

- **B2b tap-into-save scope:** v1 default = a **read-only preview sheet** of the referenced save (cheap, via the preview painter). Full embedded editor is heavier — confirm with user (noted in the B2b plan).
- **C (enrichment)** needs a brainstorm (chord-wheel-first entry? arpeggio save type shape? suggestion UX). Do not plan it cold.
