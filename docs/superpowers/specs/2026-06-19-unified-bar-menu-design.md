# Unified Bar Menu + Per-Verse Bar Lyrics — Design

**Date:** 2026-06-19
**Branch:** feature/song-writer-complete
**Status:** Approved (brainstorming)

## Problem

Two issues with the Writer bar grid (`songwriter_screen_sheet.dart`):

1. **Tap is destructive for saves.** Tapping a chord bar opens the harmony
   sheet (fine), but tapping a save (its badge on a chord, or a standalone save
   cell) deletes it instantly (`_onTapSave`). Interaction is inconsistent and
   surprising — a tap should never destroy.

2. **Per-verse bar lyrics are hidden.** Each repeat instance already renders its
   own bar row and `_editBlock` writes `verseIndex: instanceIndex`, so per-verse
   editing technically works. But the lyric text is never shown on the bars and
   editing is buried behind the harmony sheet, so it feels like a single
   "first verse only" slot.

## Goals

- **One entrypoint per bar.** Tapping any bar opens a single, consistent action
  menu. Tap is never destructive. This also prepares a single place for the
  upcoming "force a fretboard/piano save on chord/voicing selection" flow.
- **Long-press = delete** (quick shortcut, with undo) on occupied bars.
- **Per-verse bar lyrics** that are visible per verse row and editable directly.

## Design

### 1. Unified bar action sheet

New `showBarActionSheet(...)` built on the existing `showWidgetSheet` helper
(same pattern as save/load and library sheets). Opened from a bar cell's `onTap`.
Contents depend on cell state:

- **Chord bar** (block with a chord):
  - **Change chord** → existing chord editor (`_editBlock` chord path /
    `showHarmonyChordSheet`).
  - **Voicings & library** → existing `showHarmonyBlockSheet` (voicings,
    third-above, library matches). This is where the future forced-save flow
    will attach.
  - **Lyrics — Verse N** → per-verse lyric dialog (see §3).
  - **Remove chord** → `_removeBlock` (+ undo).
  - If a save badge shares the bar: **Remove save** item too.
- **Silent / lyric-only block:** Lyrics — Verse N · Remove.
- **Standalone save cell:** **Open / replace** (→ library picker) · **Remove
  save**.
- **Empty bar:** **Add chord** (→ chord sheet) · **Add from library**.

Tap is never destructive: every removal is an explicit menu item.

### 2. Save tap is non-destructive

`_onTapSave` no longer removes the save. Instead it opens the save section of
the action sheet (standalone) or the chord sheet with a "Remove save" item
(badge). Long-press on a save cell triggers delete (+ undo), matching chord
bars.

### 3. Per-verse bar lyrics

- **Editing:** the "Lyrics — Verse N" action opens a focused multi-line lyric
  dialog (a reused `_VerseLyricDialog`, controller disposed) that reads
  `block.lyrics[instanceIndex]` and writes via
  `setBlockLyric(verseIndex: instanceIndex)`. `N = instanceIndex + 1`. No model
  change — `SongBlock.lyrics` and `setBlockLyric` already support per-verse.
- **Visibility:** each bar cell renders its verse's lyric
  (`block.lyrics[instanceIndex]`, empty → nothing or a faint affordance) as a
  small text line within the cell. Because each verse renders its own
  `_BarRow(instanceIndex: i)`, verse 1's row shows verse 1's words and verse 2's
  row shows verse 2's.

### 4. Coexistence with section lyrics

Section lyrics (free per-verse text under the section, shipped previously) and
bar lyrics (words aligned under a specific chord, per verse) both remain. They
serve different jobs and do not interact. No change to section lyrics.

### 5. Interaction summary

| Cell | Tap | Long-press |
|---|---|---|
| Chord bar | Action sheet (change / voicings / lyrics / remove) | Remove chord (+undo) |
| Silent block | Action sheet (lyrics / remove) | Remove (+undo) |
| Standalone save | Action sheet (open-replace / remove) | Remove save (+undo) |
| Empty bar | Add sheet (chord / library) | — |

## Out of scope

- The forced fretboard/piano save on chord/voicing selection (future; this
  design only ensures a single entrypoint exists).
- Playback / timing.
- Rich-text lyrics.

## Testing

- **Widget:**
  - Tapping a chord bar opens the action sheet and does **not** remove the
    block.
  - Tapping a save (badge and standalone) opens a menu and does **not** remove
    it.
  - Long-pressing an occupied bar removes it (block count drops; undo restores).
  - The "Lyrics — Verse N" action writes the lyric at `verseIndex =
    instanceIndex` (verse 2 row → index 1).
  - A bar with `lyrics: ['v1', 'v2']` in a ×2 section shows `v1` in instance 0's
    row and `v2` in instance 1's row.
- **Manual (serve-sim):** tap chord → menu (nothing deleted); tap save → menu;
  long-press → delete; set ×2, add a chord, give verses different lyrics, see
  each verse row show its own words.
