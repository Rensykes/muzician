# Melody Block Piano-Roll Preview

## Intent

Make Writer Melody blocks recognizable at a glance by displaying miniature horizontal piano-roll notes inside them, inspired by FL Studio pattern clips. The preview is visual only; Piano Roll remains the editor.

## Chosen approach

Draw notes directly in each block rather than making a widget for every note. The latter would support individual note interaction but adds unnecessary complexity for a non-interactive preview.

## Behavior

- Show relative pitch vertically and note start and length horizontally, with consistent pitch scaling across all segments of a pattern.
- Reflect the melody's actual repeated and clipped placement, including wrapped rows and automatic lane repetitions. Pattern loops restart at the occurrence's beginning; notes clip at pattern, placement and section boundaries.
- Refresh all linked placements when shared melody notes change; Make Unique retains independent content. Empty patterns and missing/incompatible references remain clearly identifiable and never fabricate notes.
- Preserve Writer styling, both Studio themes, readable names, resize handles, block taps, actions, accessibility, and compact and wide layouts. Preview drawing must not intercept gestures.
- Do not modify playback, musical data, persistence, or unrelated lane types.

## Verification

Test note geometry, looping, clipping, wrapped continuity, automatic repeat offsets, shared edit refresh, empty/missing patterns, theme changes and existing interaction behavior. Verify populated runtime appearance at compact and wide sizes; distinguish runtime screenshots from widget tests.
