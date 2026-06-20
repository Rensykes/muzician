# Section Lyrics — Design

**Date:** 2026-06-18 (revised 2026-06-19)
**Branch:** feature/song-writer-complete
**Status:** Implemented

> **History:** An earlier revision of this spec proposed a bar-anchored *lyrics
> lane* (`SongLaneKind.lyrics`). It was built, then rejected and reverted
> (commit `090aec3`) because it duplicated the existing per-bar
> `SongBlock.lyrics`. This document now describes the shipped approach:
> per-verse **section** lyrics.

## Problem

Lyrics today live as `List<String>` on each `SongBlock` and are therefore
strictly tied to bars (a chord/silent block's `startBar`/`spanBars`). This
serves writers who want lyrics aligned under chords, but offers nothing to a
writer who just wants to write the lyrics of a section as free text.

We want a place to write the lyrics **of a section**, decoupled from bars —
and, because a section can repeat into multiple verses, lyrics **per verse**.

## Approach

Store free-text lyrics on `SongSection`, one entry per repeat instance
(verse). Render a tappable lyrics block under each section instance; tapping
opens a multi-line editor. No bar coupling at all.

Because per-verse lyrics only make sense when a section repeats, the section
**repeat control must be discoverable** — previously the repeat pill rendered
as an invisible `SizedBox` at ×1, so users could not find how to add verses.

Rejected alternative — **bar-anchored lyrics lane**: a `SongLaneKind.lyrics`
whose blocks carry text at bar positions. Built and reverted: it duplicated the
per-bar `SongBlock.lyrics` capability and added a third lyric mechanism without
serving the actual need ("lyrics of a section").

## Design

### 1. Model — `lib/models/songwriter.dart`

`SongSection` gains `final List<String> lyrics` (default `const []`), one entry
per repeat instance (verse). Added to the constructor, `copyWith`, `toJson`, and
`fromJson` (missing key → `const []`). Decoupled from `SongBlock.lyrics` (the
per-chord variant, retained).

### 2. Store — `lib/store/songwriter_store.dart`

`setSectionLyric({required String sectionId, required int verseIndex, required String? text})`:
grows the `lyrics` list to reach `verseIndex`, writes the text, then trims
trailing empties — mirroring `setBlockLyric`. Negative `verseIndex` is ignored.

### 3. UI — `lib/features/songwriter/songwriter_screen_sheet.dart`

- `_SectionLyrics` (ConsumerWidget): a full-width lyrics block rendered at the
  bottom of each `_SectionInstance` (one instance per verse). Shows
  `section.lyrics[instanceIndex]` or an "Add lyrics…" placeholder. Tap opens
  `_SectionLyricsDialog`. Keyed `sectionLyrics_<sectionId>_<instanceIndex>`.
- `_SectionLyricsDialog` (StatefulWidget): multi-line `TextField` (key
  `sectionLyricsField`), Cancel / Save (key `sectionLyricsSave`). Owns and
  disposes its `TextEditingController`. Save calls `setSectionLyric(verseIndex:
  instanceIndex)`.
- **Repeat pill** in `_SectionHeading`: now always rendered (single
  `GestureDetector`, key `repeatPill_<sectionId>`), showing `×{repeat}` — muted
  at ×1, accent (`MuzicianTheme.sky`) when >1. Tapping opens the existing
  stepper, relabeled **"Verses"**, wired to `setSectionRepeat`.

### 4. Persistence

Free via `SongSection.toJson`/`fromJson`. No save-browser changes.

## Out of scope

- Bar-level alignment of section lyrics (that is what per-bar `SongBlock.lyrics`
  is for).
- Rich text / formatting.
- Playback / timing sync.

## Testing

- **Unit (model):** `SongSection.lyrics` JSON round-trip; default empty;
  `copyWith` preserves; missing key → empty.
- **Store:** `setSectionLyric` grows/writes per verse; trims trailing empties;
  ignores negative index.
- **Widget:** repeat pill visible at ×1; section renders its verse's lyrics;
  tap → edit dialog → Save round-trip updates the store; a ×2 section exposes a
  lyrics block per verse.
- **Manual (serve-sim):** add a section, confirm the ×1 pill is visible and the
  lyrics block renders; bump to ×N and confirm one lyrics block per verse.
