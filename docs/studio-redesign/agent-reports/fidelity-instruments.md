# Instrument Studio fidelity pass — 19 October 2026

Reviewed the selected `02-studio.png` concept and previous native portrait evidence. The previous instrument canvases, empty helper and vertically stacked controls pushed the native voicings below the viewport.

## Changes

- Studio instrument canvas: 222px guitar / 226px piano. Guitar uses native 28px string rows, unchanged 66px fret spacing and 36×28px hit rectangles; pointer distance guard, horizontal scrolling, capo coordinates and one-shot scroll signals remain unchanged. Compact painter geometry participates in repaint comparison.
- Studio Chord mode emphasizes selected/focused positions; Free retains the note labels. Controlled guitar and legacy hosts keep their prior geometry.
- Piano keeps native 42px white / 26px black widths and white-first/black-overlay hit testing. Studio keys are 190px/118px tall. Physical black keys stay opaque under scale filtering/focus.
- Summary uses a compact bordered row with outlined Save idea and filled Add to Writer; narrow/enlarged text reflows. Existing native eligibility, recognized/exact handoff and Free explanation are unchanged.
- Notes / Voicings / Setup are underline tabs with no separate INSPECTOR heading. Collapse remains explicit and state preserving.
- Compact root/quality selectors lead directly into the existing native voicing carousels. Diatonic suggestions and piano octave controls follow previews. Scale, Library and Instrument setup use a compact footer. Guitar tuning/capo remains visible above the board.
- Updated `docs/fretboard.md` and `docs/piano.md` to describe actual dimensions, target limitations, compact selectors and utility placement.

## Files touched in this pass

- `lib/features/instrument_shared/instrument_screen.dart`
- `lib/features/instrument_shared/chord_picker_parts.dart`
- `lib/features/fretboard/fretboard.dart`
- `lib/features/fretboard/chord_voicing_picker.dart`
- `lib/features/piano/piano_keyboard.dart`
- `lib/features/piano/piano_chord_picker.dart`
- `test/features/instrument_shared/studio_instrument_workspace_test.dart`
- `docs/fretboard.md`, `docs/piano.md`

Existing dirty changes in all files were retained. No store, music-rule, save serialization or callback contracts changed. Parent owns app header/nav/theme integration and native screenshot evidence.

## Verification

- Formatted all changed Dart files.
- Focused instrument suite: 30 passed. Covers empty and populated 390×844, 844×390, 1024×768, 760×768 and 320px/1.5× text; collapse/reopen/setup, native palette repaint and handoff contracts.
- Added assertions that populated 390×844 shows native voicing previews in its initial viewport, compact first/last string taps map correctly, scroll drags do not insert notes, and scale-filtered black keys remain opaque.
- `flutter test --no-pub test/main_startup_test.dart test/theme/studio_workspace_integration_test.dart`: 21 passed.
- `flutter analyze --no-pub`: instrument files clean; last observed repository result had a single in-progress Roll-agent braces info at `piano_roll_stack_builder.dart:238`.
- Reviewed AGENTS.md after implementation; no new persistent repository rule was needed.

## Native screenshot refinement

The parent’s `/tmp/piano-populated.png` showed the legacy-sized piano preview cards still fitting only two inversions and pushing the utility footer below navigation. Studio cards are now 102×100px, radius 6, with an 86×44 native miniature keyboard; all three fit 390px. Legacy card width stays 142px plus its existing margin. Enlarged text expands card width/height and retains horizontal scrolling. A labelled 48px octave dropdown shares the root/quality row, removing the separate octave toolbar while retaining every octave offset. The redundant voicing-count helper is omitted in Studio. Added three-card visibility, exact card geometry, octave-change and footer visibility checks using 402×722 available content (the 402×874 device after native status/navigation).

Refinement validation: 27 focused diagram/workspace/palette tests passed; `flutter analyze --no-pub` passed with no issues.
