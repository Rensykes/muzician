# Studio redesign coverage and residual color audit

Audit date: 19 October 2026. This records source-level coverage for Fretboard,
Piano, Piano Roll, Writer, shared UI, and the app shell after the parent-led
native review.

## Theme and source inventory

The bounded source search used:

```sh
rg -n "MuzicianTheme" lib/features/fretboard lib/features/piano lib/features/piano_roll lib/features/songwriter lib/features/instrument_shared lib/ui lib/main.dart
rg -n "Color\\(0x|Colors\\.(white|black|red|green|blue|orange|purple|pink|grey|gray|amber|teal|cyan)" lib/features/fretboard lib/features/piano lib/features/piano_roll lib/features/songwriter lib/features/instrument_shared lib/ui lib/main.dart
```

It found eight `MuzicianTheme` references, all in
`lib/features/instrument_shared/instrument_screen.dart`. They belong to the
explicit non-Studio branch: legacy empty-state styles and the previous Scale /
Chord dock and background. The Studio branch returns the new inline inspector.
No `MuzicianTheme` reference remains in migrated feature UI, shared `lib/ui`,
or `main.dart`.

The initial concrete-color search found 132 literal references across these 26 files (before the two parent corrections below):

- Instrument canvases and diagrams: `lib/features/fretboard/chord_diagram.dart`,
  `lib/features/fretboard/fretboard.dart`,
  `lib/features/fretboard/tuning_selector.dart`,
  `lib/features/piano/piano_chord_diagram.dart`,
  `lib/features/piano/piano_chord_picker.dart`,
  `lib/features/piano/piano_keyboard.dart`, and
  `lib/features/piano/piano_range_selector.dart`.
- Instrument pickers and handoff surfaces: `lib/features/instrument_shared/chord_picker_parts.dart`,
  `lib/features/instrument_shared/shared_scale_picker.dart`, and
  `lib/features/instrument_shared/writer_handoff.dart`.
- Roll canvas and panels: `lib/features/piano_roll/piano_roll_grid.dart`,
  `lib/features/piano_roll/piano_roll_save_stack_loader.dart`,
  `lib/features/piano_roll/piano_roll_screen_v2.dart`, and
  `lib/features/piano_roll/piano_roll_stack_builder.dart`.
- Writer: `lib/features/songwriter/chord_wheel.dart` and
  `lib/features/songwriter/songwriter_undo.dart`.
- App shell and shared UI: `lib/main.dart`, `lib/ui/core/app_info_panel.dart`,
  `lib/ui/core/coach_overlay.dart`, `lib/ui/core/muzician_dialog.dart`,
  `lib/ui/project_config_sheet.dart`, `lib/ui/project_picker_sheet.dart`,
  `lib/ui/save_browser_panel.dart`,
  `lib/ui/save_previews/save_preview_thumbnail.dart`,
  `lib/ui/save_tree_browser.dart`, and `lib/ui/transport_strip.dart`.

Most remaining concrete colors fall into these intentional groups:

- Physical instrument identity: piano white and black key faces and labels;
  Fretboard material presets, strings, fret wires, nut, and inlay markers; and
  the same white/black key distinction in voicing diagrams and Save thumbnails.
- Explicit legacy styling: white/gray fills in `isStudio` fallback expressions
  preserve the excluded Song surface or unthemed compatibility hosts. The Roll
  grid also uses neutral row and grid-line washes, while selected notes, active
  columns, and playback use palette roles.
- Decorative or data-graphic neutrals: low-alpha borders, row washes, handles,
  scrims, shadows, thumbnail waveforms, and fret/string lines in app chrome,
  dialogs, Save browsers, transport, and help panels. These do not define text
  color or the sole state indicator.
- Writer chord-wheel gray is in the legacy palette branch; black wheel strokes
  and undo shadows are decorative.

The parent resolved the two flagged semantic sites: the unchecked out-of-key
setting checkbox now uses `textMuted` for its boundary, and controlled Fretboard
position labels use `onAccent` in Studio (the legacy ink is retained only in the
legacy branch). No additional semantic palette omission was identified.

This search classifies literal values; it does not measure all rendered
contrast or interaction boundaries. No blanket WCAG or touch-target claim is
made. Fretboard and Piano retain native note/key hit geometry, and Piano Roll
retains dense grid cells and small pitch labels. Named controls and the new
inspector/action layouts were exercised by feature tests, but the musical
surface itself is not uniformly 44px.

## Current verification evidence and limits

- The parent reports **1,389 Flutter tests passing** before these documentation
  and Help-copy edits. This documentation phase did not add or run tests.
- Device-targeted iOS build and launch passed; native compact/wide screenshots inspected and independent implementation R2 approved. Generic multiarchitecture simulator build has a documented Flutter toolchain limitation; see VERIFICATION.md.
- Parent integration coverage reports the app root at 320×844 with 1.5× text,
  390×844, 844×390, and 1024×768 in both themes, with project, notes, and Writer
  history preserved across switching.
- The excluded Song screen has a known 33px overflow at 320px width with 1.5×
  text when opened. This was treated as outside the Studio redesign scope;
  normal-size Song smoke coverage remains part of the native review.
- Writer strum grouping was corrected to the canonical beat grid and measure boundaries. Independent R2 review approved the fix; 24 targeted tests passed, including multi-bar 3/8 and compact layouts. Existing denominator-2/16 timing rules were preserved.

## Documentation alignment

`README.md` now names both device-local appearances, the Studio instrument
inspectors and Idea library, all five Roll tools and Quick/Hum actions, and
Writer versions with its separately auto-persisted draft. `docs/save_system.md`
records `themeVariant`, its Studio default and legacy Song boundary, plus the
distinction between a named Writer version and its active draft. The shared
Help panel now names the Notes / Voicings / Setup inspector, Idea library and
Save idea actions, Roll’s five tools, Quick, and the Hum Recorder without
describing it as audio-track or MIDI-file recording. Writer-specific Help uses
the existing Writer coach tour; its on-screen labels and Draft tooltip already
name **Save version**, **Writer versions**, **Draft**, and **Draft changed**.

Final parent verification: analyzer clean; 68 focused theme/UI/startup/painter tests pass after final Help and token changes. See VERIFICATION.md for final native evidence.
