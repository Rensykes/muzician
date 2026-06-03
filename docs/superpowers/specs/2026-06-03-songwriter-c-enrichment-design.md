# Songwriter — Phase C: Enrichment Design (SKETCH)

**Date:** 2026-06-03
**Status:** Direction sketch — **DO NOT plan/build cold. Run `superpowers:brainstorming` first** to resolve the open questions below, then write a spec + plan.
**Part of:** Songwriter initiative. C is the payoff of the app's mission — turning the harmony spine into arrangement help (double-tracking, harmonies, complementary sounds).

## The idea
Given a harmony block's chord + the project key, **suggest** complementary save-blocks the user can accept into save lanes:
- **Double-tracking voicings** — same chord, different fret position / octave (for a fuller stereo guitar).
- **Harmony lines** — diatonic 3rd / 6th above (the app's original purpose).
- **Complementary** scale / arpeggio highlights for soloing over the section.

Surface as "suggested blocks" the user accepts (one tap) into a save lane. Reuses `note_utils` + the existing save library.

## The blocking prerequisite
We **cannot save real arpeggios or note-sequences today** — the save types are static selections (fretboard/piano chords/scales, piano-roll sessions). v1 leaned on whole-section guide blocks because of this. C needs **a new save type** (an arpeggio / ordered note-sequence snapshot, or reuse `PianoRollSnapshot` as the sequence carrier) before suggestions are meaningful. Decide this in the brainstorm.

## Open questions (resolve in brainstorm)
1. **Arpeggio/sequence save type:** new `InstrumentSnapshot` subtype, or reuse `PianoRollSnapshot` as the sequence container? How is it authored (record via hum? draw in the roll? generate from a chord)?
2. **Suggestion surface:** inline under each harmony block? A "suggestions" panel per section? A bottom sheet on a harmony block?
3. **Suggestion engine scope:** rule-based only (intervals/voice-leading from `note_utils`), or also pull from the user's existing save library (find saves whose notes fit the chord/key)?
4. **Double-tracking** — what defines a "complementary" voicing? Different position on the neck, octave shift, drop-2, etc. Needs a voicing-generation rule.
5. **Acceptance flow:** does accepting a suggestion create a save (persisted) + a block, or just an embedded block?

## Likely file map (after brainstorm — indicative only)
| Area | File |
|------|------|
| New save type | `lib/models/save_system.dart` (or `lib/models/<arp>.dart`) + dispatch |
| Suggestion rules (pure) | `lib/schema/rules/songwriter_enrichment_rules.dart` (new) |
| Suggestion UI | `lib/features/songwriter/songwriter_suggestions.dart` (new) |
| Wiring | harmony block menu / section card |

## Dependencies / ordering
- Best done **after B2b** (playback makes the arrangement auditable) and ideally after the **chord wheel** (a clean harmony spine to hang suggestions on).
- The arpeggio save-type decision may also benefit the `Roll` tab — keep it general.

## Why this is a sketch, not a plan
The suggestion UX and the new save type are genuine design decisions with multiple valid approaches and real model impact. Planning them cold would bake in guesses. Start with brainstorming: nail the save type + one concrete suggestion (e.g. "3rd-above harmony line") end-to-end as a thin vertical slice, then expand.
