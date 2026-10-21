# Writer visual fidelity refinement

19 October 2026. Scope: Writer-specific header, section sheet, tests, and guides.
All pre-existing redesign changes retained. No models, stores, theory rules,
shared theme/shell/transport files, or native project files changed here.

## Layout shipped

- Editable project context and draft status first; Writer title, Save version,
  Undo/Redo, and version-browser icons together; inline key/BPM/play/metronome
  below. Help and overflow remain reachable. History and version icons have
  tooltips. Controls retain at least 44-pixel targets and wrap with scaled text.
- Section name, bars, repeat, Mixer, and Section actions share a compact row.
  Remove section moved to Section actions and uses the same history Undo path.
- Harmony keeps four-bar rows. Filled cells start at 64px, empty slots at 44px;
  distinct Save names and lyrics add 14px/16px respectively before text scaling.
  Empty slots show +. Chord, exact-label, Save, native edit, and advanced action
  flows remain unchanged.
- Strum title and labelled Source selector share one row at standard phone
  width. Unassigned remains visible and silent; source eligibility and occupied
  target filtering are unchanged.
- Studio strum placements use neutral strips with mint (or theme-primary)
  ordered down/up previews. At sufficient width, name, preview, and linked Save
  action share a 44px strip; narrow single-bar tiles retain stacked content.
  Continuation rows and all eight-bar placement semantics remain intact.
- Section lyric entry retains a 44px minimum target.

## Verification

- Read root AGENTS.md, PRODUCT.md, DESIGN.md, renderer/accessibility specialist
  guidance, existing Writer callers/tests, Studio concept 02, prior native phone
  and iPad captures, and parent native evidence-v2/02 capture.
- Focused Writer suite: 49 tests PASS covering Studio density at 390×844 and
  1024×768 with simulated 44px top/80px bottom insets, 320px at 1.5 text scale,
  844×390 landscape, both palettes/live theme retention, key confirmation,
  Harmony exact/source behavior, occupancy filtering, patterns, lyrics/history,
  open sheets, and isolated melody editor retention.
- Additional tightened density checks PASS 2: Source stays in the title row,
  all 8 Harmony cells plus source and lyric entry fit the initial viewport;
  Remove section is recovered with header Undo; one-bar narrow strum placements
  render without overflow.
- `dart format` changed Dart paths; `flutter analyze --no-pub`: no issues.
- `git diff --check` scoped to owned files: clean.
- Parent owns final native phone/tablet screenshots, README, and root design
  ledger reconciliation. The evidence-v2/02 intermediate native capture already
  shows the compact section/cards; neutral strum refinement followed its review.

Guides updated: docs/songwriter.md and docs/song_writer_guide.md. AGENTS.md was
reviewed; this layout refinement introduces no persistent architecture rules.

## Final disclosure refinement

Reviewed populated native `evidence-v2/09-writer-studio-portrait.png` against the
Studio02 reference. Bars and Repeat were visually passive; Studio now presents
both actual editors as outlined controls with a 1px border, 6px radius, trailing
chevron, and at least 44px height. Mixer shows its text label at widths of 700px
or more and retains an icon plus tooltip on compact screens. No new controls
or editing behavior were introduced. The compact row wraps at larger text sizes.

Writer Studio tests cover compact/wide density, the 320px/1.5 scaled layout,
disclosure touch targets and chevrons, opening both existing stepper editors,
and responsive Mixer labelling. Parent retains final native capture and guide
reconciliation for this final small refinement.

## Mixed Harmony row alignment

Final review identified a mixed row where the 44px empty slots were vertically
centred beside a 64px filled cell. Studio Harmony rows now take the tallest
cell's scaled content height and stretch every cell to that height. Fully empty
rows remain 44px; lyrics and distinct Save names still determine additional
content height. Legacy row geometry is unchanged. A focused mixed-row regression
checks both top/bottom alignment and the compact all-empty following row.

Reviewed `evidence-v2/16-writer-ipad-final.png` to confirm the reported uneven
row. Final Writer Studio suite: 14 tests PASS. `flutter analyze --no-pub`: no
issues. Scoped diff whitespace check: clean. Parent owns the post-fix runtime
capture of this bounded alignment change.
