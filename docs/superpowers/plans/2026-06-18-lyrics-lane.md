# Section Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: IMPLEMENTED** (branch feature/song-writer-complete, commits `fc742a9`, `8a16695`, `72bdb0f`). This plan documents the shipped work. An earlier version of this plan built a bar-anchored *lyrics lane*; that was reverted (commit `090aec3`) — see the spec's History note.

**Goal:** Give each song section free-text lyrics, one per verse (repeat instance), decoupled from bars, with a discoverable verse-count control.

**Architecture:** `SongSection.lyrics: List<String>` indexed by repeat instance. A `_SectionLyrics` block renders per `_SectionInstance`; a `_SectionLyricsDialog` edits it. The section repeat pill is made always-visible and relabeled "Verses".

**Tech Stack:** Dart / Flutter, Riverpod (`songwriterProvider`), `package:flutter_test`, SharedPreferences mock for store tests.

**Spec:** `docs/superpowers/specs/2026-06-18-lyrics-lane-design.md`

---

## File Structure

- `lib/models/songwriter.dart` — `SongSection.lyrics` field + JSON.
- `lib/store/songwriter_store.dart` — `setSectionLyric`.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — `_SectionLyrics`, `_SectionLyricsDialog`, always-visible repeat pill.
- Tests:
  - `test/models/songwriter_section_lyrics_test.dart`
  - `test/store/songwriter_section_lyric_ops_test.dart`
  - `test/features/songwriter/songwriter_section_lyrics_test.dart`

---

## Task 1: Model — `SongSection.lyrics`

**Files:**
- Modify: `lib/models/songwriter.dart` (`SongSection`)
- Test: `test/models/songwriter_section_lyrics_test.dart`

- [x] **Step 1: Failing test** — round-trip a section with `lyrics: ['verse one', 'verse two']`; assert default empty + `copyWith` preserves; missing JSON key → empty.
- [x] **Step 2: Run** — FAIL (`lyrics` getter undefined).
- [x] **Step 3: Implement** — add `final List<String> lyrics` (default `const []`) to the field list, constructor (`this.lyrics = const []`), `copyWith` (`List<String>? lyrics` → `lyrics ?? this.lyrics`), `toJson` (`'lyrics': lyrics`), and `fromJson` (`(json['lyrics'] as List?)?.map((e) => e as String).toList() ?? const []`).
- [x] **Step 4: Run** — PASS.
- [x] **Step 5: Commit** — `feat(songwriter): add per-verse lyrics field to SongSection`.

## Task 2: Store — `setSectionLyric`

**Files:**
- Modify: `lib/store/songwriter_store.dart` (after `setSectionRepeat`)
- Test: `test/store/songwriter_section_lyric_ops_test.dart`

- [x] **Step 1: Failing test** — write verse 1 first → `['', 'second verse']`; then verse 0 → `['first verse', 'second verse']`; clearing last verse trims to `['a']`; negative index ignored.
- [x] **Step 2: Run** — FAIL (`setSectionLyric` undefined).
- [x] **Step 3: Implement:**

```dart
  void setSectionLyric({
    required String sectionId,
    required int verseIndex,
    required String? text,
  }) {
    if (verseIndex < 0) return;
    _replaceSection(sectionId, (s) {
      final list = [...s.lyrics];
      while (list.length <= verseIndex) {
        list.add('');
      }
      list[verseIndex] = text ?? '';
      while (list.isNotEmpty && list.last.isEmpty) {
        list.removeLast();
      }
      return s.copyWith(lyrics: list);
    });
  }
```

- [x] **Step 4: Run** — PASS.
- [x] **Step 5: Commit** — `feat(songwriter): add setSectionLyric store op`.

## Task 3: UI — section lyrics block + visible repeat pill

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
  - `_SectionInstance.build` children: append `_SectionLyrics` after the drum-lane loop.
  - `_SectionHeading` repeat pill: collapse the `if (repeat>1) … else …` into one always-visible pill (key `repeatPill_<sectionId>`), `×{repeat}` muted at 1 / `MuzicianTheme.sky` when >1, stepper title "Verses".
  - New `_SectionLyrics` (ConsumerWidget) + `_SectionLyricsDialog` (StatefulWidget owning/disposing its controller).
- Test: `test/features/songwriter/songwriter_section_lyrics_test.dart`

- [x] **Step 1: Failing widget tests** — (a) `repeatPill_<id>` visible + `×1` shown at repeat 1; (b) section renders its verse-0 lyrics text; (c) tap `sectionLyrics_<id>_0` → enter `sectionLyricsField` → tap `sectionLyricsSave` → store lyrics == `['new lyrics']`; (d) a `setSectionRepeat(id, 2)` section exposes `sectionLyrics_<id>_0` and `sectionLyrics_<id>_1`.
- [x] **Step 2: Run** — repeat-pill test passes; 3 lyrics tests FAIL.
- [x] **Step 3: Implement** — `_SectionLyrics` keyed `sectionLyrics_<sectionId>_<instanceIndex>` shows `section.lyrics[instanceIndex]` or "Add lyrics…", tap → `_SectionLyricsDialog`; dialog `TextField` key `sectionLyricsField`, Save key `sectionLyricsSave` → `setSectionLyric(verseIndex: instanceIndex)`; always-visible repeat pill with "Verses" stepper.
- [x] **Step 4: Run** — PASS (4/4). `dart format` + `dart analyze` clean; full suite green.
- [x] **Step 5: Commit** — `feat(songwriter): per-verse section lyrics + always-visible repeat pill`.

## Task 4: Manual verification (serve-sim)

- [x] Add a section → confirm the `×1` repeat pill is visible (muted) and the "Add lyrics…" block renders under the grid, decoupled from bars.
- [x] Tap the pill → "Verses" stepper → bump to 2 → confirm "— 1 of 2 —" and "— 2 of 2 —", each with its own lyrics block.

---

## Final verification

- [x] `flutter test` — 602 tests pass.
- [x] `dart analyze` — no issues.
- [x] All commits pushed.
