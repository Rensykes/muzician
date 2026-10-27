---
name: Muzician Studio
description: A touch-first songwriting workbench with two interchangeable dark palettes.
register: product
default-theme: studio
status: implemented-refined
---

# Muzician — Studio design system

Chosen direction: Studio original, 18 October 2026. Implementation and review evidence are in [PROGRESS.md](docs/studio-redesign/PROGRESS.md); the four Studio workspaces and shared theme system are implemented. [PRODUCT.md](PRODUCT.md) governs music and persistence contracts.

Current instrument UX V2 implementation and runtime evidence: [delivery record](docs/instrument-ux-v2/PROGRESS.md).

## Scene and visual intent

A guitarist or pianist writes during rehearsal in moderate/dim light, holding an instrument and reaching for a phone or tablet. Use a graphite workbench, a large musical surface, restrained emphasis and explicit controls. Avoid a full DAW console, decorative glow, default glass effects, card-within-card layouts and gradients in text. The original Studio triptych and Roll concept are visual references in `docs/design-exploration/2026-10-16/mockups/02-studio.png` and `06-studio-piano-roll.png`. Correct diagrams come from existing renderers, never from image pixels.

## Themes and semantic roles

Both themes share layout, typography and behavior. Settings → Appearance exposes Studio and Studio Muzician; Studio is default, including old/unknown preference values. No system/light mode in this phase. Song is temporarily disabled in V2; its retained implementation remains legacy-scoped; shared components resolve the nearest inherited palette so a Song dialog is not silently restyled by a global mutable singleton.

| Role | Studio | Studio Muzician |
| --- | --- | --- |
| Canvas | #171C1B (flat) | #0A0A1E |
| Surface / navigation | #1D2421 | #0A0F1E |
| Raised inspector/dialog | #242B29 | #161B2E |
| Primary text | #F1F5F3 | #F1F5F9 |
| Secondary text | #B5C3BC | #94A3B8 |
| Muted readable label | #99ABA1 | #8B9DC3 |
| Divider / decorative border | #45534C | #465578 |
| Primary action / active nav / selected single note | #9EE7BF | #38BDF8 |
| On primary action | #14251B | #071722 |
| Normal note / secondary emphasis | #72C7AF | #4ECDC4 |
| Harmony / multi-selection | #C5CFAB | #A78BFA |
| Root note | #E5C07B | #34D399 |
| Warning / playback cursor | #F0B86E | #FB923C |
| Destructive / error | #F08B88 | #F87171 |

Studio Muzician may use the existing background stops #0A0A1E → #1A1034 → #16213E → #0F3460, but controls sit on opaque surfaces for legibility. Studio has a flat background. Disabled styling is separate from readable help text. Required text contrast ≥4.5:1, large text ≥3:1, interactive boundary/focus/selection ≥3:1. Decorative dividers need not reach 3:1; they must not be the only control boundary. Measure relevant token pairs in tests.

Musical states use labels/position/outline as well as color. Preserve piano white/black key identity and guitar strings/fret markers. Roll: normal notes use teal, active-column notes use the primary mint/sky accent, selected notes add a2px outline and multiple selection uses harmony color; active column and moving playhead remain distinct. Do not recolor musical objects with arbitrary rainbow accents.

## Runtime contract

Use an immutable context-resolved `ThemeExtension` for semantic colors, background stops and dimensions, backed by ThemeData. Keep legacy Muzician constants available for the excluded Song scope during migration. No mutable global theme variables. Painters receive the resolved immutable palette, and `shouldRepaint` includes palette changes. Root theme changes rebuild presentation without re-creating providers or using theme-based keys on workspaces. Flutter routes/sheets must use a scope-aware wrapper: Studio resolves the live app-level inherited theme source above Navigator (also above isolated editor containers), while Song uses a fixed legacy theme. Capture only the host scope kind, never a ThemeData snapshot. Shared modal surfaces resolve colors inside that live wrapper. Open/nested dialogs must update without losing input/scroll state. Song embedded Roll retains legacy layout as well as palette.

## Type, space and geometry

Use the existing platform sans family, with weight and tabular figures for numerical readouts; no remote fonts/dependency required. Titles 24–28/700, section titles 18–20/700, body/actions 14–16, labels 12–13. Use tabular figures for BPM, bar/beat and octave. Preserve user text scale; wrap/reflow instead of globally clamping it. Musical canvas labels follow the existing renderer geometry, with readable minimums and a documented accessibility limitation where appropriate.

Spacing scale: 4, 8, 12, 16, 24, 32. Compact outer inset 16; wide 24. Radius: controls 6–8, panels 10, modal 16. Borders 1px; modest shadow only for transient overlays. Interactive controls ≥44×44 logical pixels (48 where practical). Canvas key cells and note handles retain existing instrument geometry and gestures; do not claim all musical hit regions meet 44px. Provide visible selection/edit alternatives and do not shrink them further.

## Shared workspace structure

Project context comes first in a quiet 44px row with a plain project-name disclosure, followed by the full title; full workspace title does not compete with the project name and three icons. Long project names can ellipsize with full semantic label/tooltip. Keep six labelled navigation destinations, with Song visibly disabled and an accessible “Temporarily unavailable” explanation. Use an adaptive rail only when it improves space, otherwise keep the existing bottom layout with safe-area handling. Preserve Song code and saved data.

For Fretboard/Piano, compact portrait pins the playable canvas above a bounded inspector. Tabs and Scale/Library remain outside the inspector content scroll; each panel keeps its own scroll position. Wide and short landscape use a side inspector, keeping native musical geometry useful. Adapt auxiliary content to available height and scaled text instead of allowing inspector scrolling to displace the instrument. Respect keyboard viewInsets, safe areas and nested scroll constraints. Very short portrait layouts use the compact single-row header and scroll audition, selection and the bounded inspector below the pinned full canvas. Never crop strings or keys to fit controls; retain 44px control targets.

Shared controls: project/title header, opaque workspace panel, labelled primary/secondary action, inspector tabs, section heading and theme-aware modal helper. Create only components actually reused. Modal sheets scroll, have a named title and close action, preserve context and can be dismissed without applying unrelated changes. Do not present a decorative handle as a promise of multiple drag detents unless implemented.

## Fretboard and Piano

Order: project/title → compact labeled Input/View menus → playable canvas → single selection disclosure → inspector. Input (Free/Chord) and View (Full/Solo) use neutral controls with 44px minimum touch targets and explanatory menu choices. Selection opens one live-theme action sheet for exact notes, Save idea and Add to Writer; do not repeat summaries or actions in inspector tabs. The disclosure remains available with the inspector collapsed. Default inspector Voicings; tabs Notes / Voicings / Setup. Allow collapse and reopen without clearing selection or recreating panels. Notes contains full detection; Voicings provides From notes / By chord search with native diagrams in a horizontal carousel; Setup exposes native controls. Distinguish captured search criteria from the applied selection with an Applied label/check. Applying a result must not change criteria, result order or carousel offset. Manual note edits refresh the note query; Use current notes is the explicit refresh action. Root/quality controls must remain readable in a narrow inspector and reflow where needed. Scale and library remain explicitly reachable without duplicate state or dead controls.

Full labels every playable note; Solo labels only exact selected positions,
independent of Chord/Free. Keep piano keys and guitar strings visible in both
views. The Fretboard canvas extends through fret 24 with horizontal scrolling.

Save idea opens the existing save flow; Add to Writer preserves recognized versus Exact selection and linked-save behavior. Keep explanations for disabled guitar Free handoff. Show tuning/capo as readable controls and preserve capo positioning, one-note-per-string eligibility and scroll guards. Piano preserves actual MIDI keys, black-key overlays, range, octave/inversions and audition. No new global transport for Fretboard/Piano merely because it appeared in the image.

Fretboard has one compact audition row below its canvas: a Sound menu for Clean
or Distorted electric guitar and labelled Strum controls for down/up strokes.
Keep these 44px actions available when the inspector is collapsed. Empty or
ambiguous selections disable strumming and explain how to select one position
per string; audition never changes the selection.

Automatic **From notes** suggestions in Fretboard and Piano respect the active
scale as well as the captured notes. Changing or clearing the scale updates
results without changing the query or instrument selection. An incompatible
query shows the existing no-results state; do not silently relax either filter.
Explicit **By chord** browsing retains its key-conflict confirmation.

## Piano Roll

Grid remains central, with an unframed transport above and a compact tool row. Keep Draw, Select, Split, Paint and Delete accessible; active tool has a visible label. Expose snap in the borderless tool row; the transport's pitch-range readout shifts octaves by vertical drag, resets on long-press, and offers the same actions on tap. Retain Quick, rewind, selection clear/delete, column detection, scale, Save/Load, Import and Hum Recorder. Name recording 'Hum recorder' or explain it visibly. No velocity lane, automation or Add to Writer invented by the mockup.

Inspector: Stack Builder / Selection. Reuse the builder and detection logic. On wide screens the inspector sits beside the grid; on compact screens it has bounded/scrollable expansion so the grid keeps useful height. Embedded instances respect showScale/showSavePanels/showBackground and inherit host behavior.

## Writer

Header separates project/title, named version action and overflow. Transport retains project key confirmation, tempo/play/metronome; Undo/Redo remain available. Use 'Save version' and 'Writer versions' for named Writer snapshots while retaining Section blocks. State labels distinguish auto-persisted draft from named-version changes.

Writer uses unframed transport and metadata disclosures, compact section spacing,
and divider-separated Mixer rows instead of nested bordered cards. Fretboard
Harmony has an inline Sound disclosure for the shared Clean/Distorted preference.
Retain visible musical cell boundaries and 44px control targets.

Section: name, bars, repeats and Mixer; Harmony lane source label, four-cell rows with chord/degree/lyrics and Save identity; other lane types retain editors. Expose frequent chord actions contextually while keeping every existing advanced menu action. No Add to Writer inside Writer. Keep exact labels literal and theory absent when unknown.

Melody uses numbered, four-bar wrapped timeline rows with related continuation
segments, a final-edge resize handle and visible edit and block actions. Keep an
accessible **Adjust placement** alternative, clear automatic-repeat markers and
conflict feedback. Repeat / reuse selects a free start and preserves shared
pattern and Save linkage; Make Unique detaches the selected placement. The lane
header exposes its own Sound: Piano by default for new lanes, with Clean guitar
and Distorted guitar choices; unset legacy lanes show Pattern sounds. Explicit
lane sound is independent of the pattern's instrument mapping and the shared
Harmony guitar preference. Preserve these controls and the wrapped layout in
both themes and at compact and wide sizes.

Wide layout: avoid a single half-width section with an empty column. Use full-width bounded section content or a real contextual inspector; do not invent an inspector with fake actions. Pattern editor groups steps using the canonical project beat grid (four per quarter beat, two per eighth beat), with 44px steps and wrapping within a labelled beat when needed. Groups never cross a bar boundary; existing timing rules remain authoritative. Guitar Strum source stays explicit, Unassigned remains visible and silent. Audio/melody/drum/lyrics must stay reachable even when not illustrated in the concept.

## Visual fidelity revision — 19 October 2026

The initial implementation passed functional review but did not match the chosen composition. Studio uses rectangular 6–8px controls, mint filled primary actions, outlined secondary actions, and underlined inspector tabs without a redundant INSPECTOR banner. Avoid pill-shaped defaults and oversized empty-state copy. In phone portrait, target 200–230px instrument canvases and a compact horizontal detection/action row so the first native voicing previews appear above navigation. Writer combines section metadata in one row where possible and uses compact chord cells (about 64px populated, 44px empty), exposing more lanes without scrolling. Preserve scaled-text reflow and essential 44px toolbar touch targets. Music cell geometry can adapt to density while maintaining existing hit-testing and scroll guards; provide larger landscape/editor views and native picker alternatives.

Compare real populated screenshots with the references before declaring completion; passing layout tests alone does not establish fidelity.

The final visual pass also uses readable bar/beat ruler labels, a contextual column strip when height allows, and a bounded wide Roll builder. New notes added outside a grid gesture are revealed vertically. Writer Bars/Repeat are plain disclosures; Mixer has a label on wide layouts. Native evidence and before/after comparison are in `docs/studio-redesign/comparison.html`.

## Verification and preservation

Instrument inspectors size to their active content and align results at the top. The phone workspace or wide inspector rail owns vertical scrolling; embedded Notes must not reserve a fixed-height viewport. Setup uses one horizontal inset and removes additive native-widget spacing and repeated headings. Configuration comes first, with a subdued 44px Clear all selections action last. Verify populated Notes and Setup as well as Voicings; a single default-tab capture is insufficient.

Test 390×844 portrait and 844×390 landscape plus 1024×768 wide where applicable; 320px width and text scale 1.5 for headers/forms. Verify no overflow/unbounded viewport, controls reachable with scroll, theme changes reflected inside open dialogs and painters, settings restored on restart and no changes to notes/history/project when switching. Use screenshots of real populated data to compare hierarchy to Studio. Preserve all existing music/key/Save safeguards. Update feature guides and README after each implemented phase; do not label planned controls as shipped.
