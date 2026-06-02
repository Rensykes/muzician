# Songwriter — Spec 1: Save Grid View (Subproject A)

**Date:** 2026-06-02
**Status:** Design approved, ready for implementation plan
**Part of:** Songwriter initiative (A → B → C). This is **A**, the smallest, standalone piece. It ships a grid display for the existing save browser **and** becomes the block-picker palette that Spec 2 (Songwriter v1) consumes.

---

## 1. Problem

Today saves live only in `SaveBrowserPanel` (`lib/ui/save_browser_panel.dart`): a nested-folder **list**, opened per-instrument (each instrument panel passes an `instrumentFilter`). A list row is slow to scan. Users want to glance at a folder and see *what each save is* — a chord, a scale, a voicing — without reading names one by one.

Saves are not all chords. An `InstrumentSnapshot` may be a fretboard/piano chord, a scale, an arpeggio-ish highlight set, a piano-roll session, or a song project. The card must identify each at a glance using data we already derive.

## 2. Scope

**In scope (v1):**
- A **list ⇄ grid** display-mode toggle inside `SaveBrowserPanel`.
- A **grid card** for saves and for folders.
- Preference persistence of the chosen mode.
- A **palette mode** for the same panel: instead of loading a save, it returns the picked save to a caller (used by Spec 2).

**Out of scope (deferred):**
- A standalone cross-instrument "Library" screen (revisited during B/C).
- **Mini instrument thumbnails** on cards (tiny rendered fretboard/keyboard/roll). v1 uses icon + derived label only.
- Any change to how saves are created, loaded, or stored.

## 3. Decisions

| ID | Decision |
|----|----------|
| A-1 | Grid is a **display-mode toggle inside `SaveBrowserPanel`**, not a new screen. Every instrument save panel inherits it for free. |
| A-2 | The grid panel doubles as the **block palette** for Songwriter (Spec 2) via an optional pick callback. |
| A-3 | Card face = **type icon + derived label + name + timestamp**. No new painters. |
| A-4 | Toggle state persists in `AppSettings`. |

## 4. Card Face

Resolution order for the card's primary label (reuse existing derivation, no new music logic):

1. `snapshot.pendingChord` present → chord symbol (e.g. `Cmaj7`).
2. else `snapshot.pendingScale` present → scale label (e.g. `A Dorian`).
3. else `snapshot.selectedNotes` non-empty → note chips (existing chip widget).
4. else → literal `"Highlight"` (a save with selection but no derivable chord/scale).

Card also shows:
- **Type icon** — fretboard / piano / piano_roll / song / songwriter (maps `snapshot.instrument`).
- **Save name** (`SaveEntry.name`).
- **Timestamp** (existing formatting).

**Folder cards** render in the same grid, sorted above save cards, using a folder icon + name + child count. Tapping a folder navigates into it (same as the list). Breadcrumb navigation is unchanged.

## 5. Interactions (parity with list mode)

- **Tap save card** → same action the list row performs (load in normal mode; pick in palette mode — see §7).
- **Long-press save card** → same context menu as the list row (rename, delete, move, etc.).
- **Tap folder card** → navigate into folder.
- All create/rename/delete/move flows are reused unchanged.

## 6. Toggle & Persistence

- A mode toggle (list/grid icon button) lives in the `SaveBrowserPanel` header.
- Selected mode is stored in `AppSettings` as a new field `saveBrowserGrid: bool` (default `false` → list), persisted through the existing `settingsProvider` / `SharedPreferences` path. Add the field to `AppSettings.toJson`/`fromJson` with a safe default so older stored settings load unchanged.

## 7. Palette Mode (consumed by Spec 2)

`SaveBrowserPanel` gains an optional pick affordance so Songwriter can reuse it as the block source:

- New optional prop, e.g. `onPick: void Function(SaveEntry)?`.
- When `onPick != null`, the panel is in **palette mode**: tapping a card invokes `onPick` and dismisses, instead of running the normal load action. Folder navigation still works.
- `instrumentFilter` is already supported and is set by the caller (e.g. `'fretboard'` for a guitar lane) so the palette only shows compatible saves.
- Normal mode (`onPick == null`) is unchanged.

This keeps one browser implementation for both "manage my saves" and "pick a block."

## 8. Files Touched

| File | Change |
|------|--------|
| `lib/ui/save_browser_panel.dart` | Add mode toggle, grid layout, grid card widget, optional `onPick` palette mode. |
| `lib/models/save_system.dart` | Add `AppSettings.saveBrowserGrid` field + JSON. |
| `lib/store/settings_store.dart` | Setter for the new preference. |
| `test/...` | Card label-resolution test; settings serialization test; palette-mode callback test. |

No changes to instrument save panels are required — they inherit the toggle. They may later pass `onPick`, but that wiring belongs to Spec 2.

## 9. Success Criteria

- Toggle switches list ⇄ grid in any instrument save panel; choice survives app restart.
- Each save type renders an identifying card via the §4 resolution order, including the "Highlight" fallback.
- Folder cards navigate; breadcrumbs intact.
- Palette mode returns the picked `SaveEntry` to a caller and dismisses, without mutating save state.
- `flutter analyze` clean; new tests pass; verified on one compact and one wide viewport.

## 10. Risks / Notes

- **Grid density on compact phones** — verify card min-width keeps labels legible; fall back to 2 columns on narrow widths via `LayoutBuilder`.
- **`selectedNotes` may be large** — cap note-chip count on the card (e.g. first N + "…").
- Deferring thumbnails is deliberate: real per-instrument thumbnail painters are a separate effort and not needed to identify a save.
