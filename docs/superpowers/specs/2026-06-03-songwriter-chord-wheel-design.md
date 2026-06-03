# Songwriter — Chord Wheel Design

**Date:** 2026-06-03
**Status:** Design draft — **needs a `writing-plans` pass** to become an implementation plan.
**Part of:** Songwriter initiative. A faster, key-aware way to add **harmony-lane** chords, matching the reference UI (radial diatonic picker). Slots after B2b (or in parallel — it touches only the harmony entry path).

## Why
Today harmony chords are added via `harmony_chord_sheet.dart` (12 root chips → quality chip = two taps + a modal). For laying a progression quickly, a **diatonic chord wheel** of the project key is faster and teaches function (I–IV–V, ii–vi–iii, vii°). This is the screenshot the user referenced.

## What it is
A radial picker showing the **7 diatonic triads of the project key**, arranged by function:
- Majors I / IV / V (tonic group) prominent,
- minors vi / ii / iii,
- diminished vii°,
- (v1) non-diatonic positions dimmed / disabled; borrowed + secondary dominants are a later pass.

Tapping a wedge creates a harmony `SongBlock` for that chord (root + quality + notes + Roman numeral) at the next free bar — same output as `makeHarmonyBlock`, so the data model is unchanged.

## Decisions (defaults; confirm in the plan pass)
| ID | Decision |
|----|----------|
| CW-1 | The wheel is the **primary** harmony-add UI; keep the root+quality sheet as an "Other chord" fallback (for borrowed/altered chords). |
| CW-2 | v1 shows **diatonic triads only** of `config.keyRoot`/`keyScaleName`. If no key is set, fall back to the root+quality sheet (or prompt to set a key). |
| CW-3 | Render with a **`CustomPainter`** wheel + gesture hit-testing by angle/radius (authentic look). Each wedge labeled with the chord symbol + Roman numeral. |
| CW-4 | Output via existing `makeHarmonyBlock` + `romanNumeralFor`; no model/store change. Placement = next free bar (reuse `_nextFreeBar` from `songwriter_lane_row.dart`), default span 2 bars. |
| CW-5 | Quality per degree from the scale: major → I, IV, V; minor → ii, iii, vi; dim → vii° (for `major`). Derive generically from scale degrees so it works for `minor` too. |

## Diatonic derivation (rule, mostly exists)
For key root pc `k` and scale intervals `S = scaleIntervals[scaleName]` (`note_utils.dart`):
- degree `d` (0..6) → root pc = `(k + S[d]) % 12`.
- triad quality = stack scale thirds: pcs `S[d]`, `S[(d+2)%7]`, `S[(d+4)%7]` (mod-octave) → classify intervals into `'' | 'm' | 'dim' | 'aug'`.
- chord notes via `getChordNotes(rootName, quality)`; numeral via `romanNumeralFor`.
Add a helper `diatonicTriads(keyRootPc, scaleName) -> List<{rootPc, quality, symbol, romanNumeral, notes}>` in `songwriter_rules.dart` (pure, unit-testable — do this as the first plan task).

## File map (proposed)
| File | Responsibility |
|------|----------------|
| `lib/schema/rules/songwriter_rules.dart` | add `diatonicTriads(...)` (pure) |
| `lib/features/songwriter/chord_wheel.dart` (new) | `ChordWheel` widget — `CustomPainter` + hit-testing; `onPick(SongBlock)` |
| `lib/features/songwriter/harmony_chord_sheet.dart` | host the wheel; keep root+quality grid as "Other" tab/expander |
| `lib/features/songwriter/songwriter_lane_row.dart` | unchanged entry point (already opens the harmony sheet) |

## Tests
- `diatonicTriads` in C major → `[I C, ii Dm, iii Em, IV F, V G, vi Am, vii° Bdim]` (rule test).
- Wheel widget: tapping the I wedge returns a `SongBlock` with `romanNumeral == 'I'` and `chordNotes` containing C/E/G (widget test with a deterministic hit coordinate, or expose an internal `wedgeAt(angle)` for unit testing).

## Out of scope (later)
Borrowed chords, secondary dominants, 7th/extended qualities on the wheel, modulation, drag-from-wheel-to-a-bar.

## Open question for the plan pass
- Hit-testing precision on a painted wheel is fiddly to widget-test. Recommend exposing a pure `chordWheelHitTest(Offset local, Size, key) -> int? degree` so the geometry is unit-tested and the widget just renders + forwards taps.
