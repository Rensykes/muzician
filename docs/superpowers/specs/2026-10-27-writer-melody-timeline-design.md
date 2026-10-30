# Writer Melody Timeline Design

## Intent and scope

Replace the Melody lane's current bar-cell presentation with a purpose-built, wrapped block timeline inside Writer. Make melody placements easy to recognize, resize and reuse, and allow each lane to choose its playback sound. Keep the existing Studio visual language, Writer workflows and musical data; this is not a separate DAW or a redesign of other lanes.

## Approaches considered

1. Extend the current bar-cell lane with resize handles, repeat actions and sound selection. This reuses more presentation code and is lower risk, but retains the current lane structure.
2. **Chosen: a new Melody timeline editor within Writer**, retaining existing project models and rules where appropriate. It provides a clearer block-focused interaction at the cost of a larger UI and compatibility effort. It wraps bars into rows, rather than using a horizontally scrolling timeline.

## Timeline and placement

- Render bar-aligned, visually continuous melody blocks spanning their placed bars. A block crossing a row boundary appears as clearly related continuation segments; its resize handle is on the final segment. Keep bar numbers, empty-bar creation, readable names, existing playback-position feedback and Writer's compact, theme-aware styling. The approved mockup is illustrative rather than pixel-perfect.
- Tap a block to edit its melody. Provide accessible block actions including Adjust placement, Repeat / reuse, Make Unique, existing performance editing, renaming and any other applicable existing actions. Preserve lane deletion and existing flows for creating or selecting patterns, including the melody performance editor.
- Drag the right-edge handle to resize in whole bars. Support mouse and touch, including across wrapped rows. Keep the left edge fixed, enforce at least one bar, and stop before the next block or at the section boundary; never move or overwrite another block. Show the current valid extent during the gesture and commit as one undoable edit; cancel leaves placement unchanged. Adjust placement remains an explicit, accessible alternative using the same rules.
- The timeline uses Writer's existing bar numbering and adaptive row geometry, with per-row bar labels or an equivalent clear indication; do not redesign the shared section ruler. Keep controls usable with scaled text, compact and wide screens, and both Studio themes. Continue to provide non-gesture alternatives and meaningful semantics for blocks, actions and resize values.
- Automatically repeated lane occurrences are visibly distinguishable from authored placements and count as occupied when choosing a destination or resizing. Validate against both authored blocks and expanded repeats, and prevent an edit that would overlap or silently displace an existing automatic occurrence because the lane's repeat period changed. Explain when this prevents an edit; users can adjust the lane repeat first. The placement dialog may still move the start as well as change length, subject to these same safeguards.

## Reuse and musical behavior

- Repeat / reuse asks the user to choose an empty starting bar and creates a fresh placement linked to the same pattern and canonical Save as the original melody. It starts with the original placement's length, shortened only as needed to fit the free contiguous bars before the next block or section end. Cancel or an invalid destination makes no changes. Existing Use existing pattern remains available across lanes and sections. Broken references remain visible; disable actions that cannot safely resolve their content.
- Edits to a shared melody affect all linked occurrences. Make Unique creates an independent melody for that occurrence using the existing save-system and performance-mapping semantics. Resizing a placement does not resize or change the shared melody or any other placement.
- Keep current playback semantics: a melody loops from the block's left edge if its placement is longer than the pattern and clips notes at the block or section edge when shorter. Existing pattern lengths, moves, lane and section repeats, playback, save recovery and undo/redo must remain intact.

## Per-lane sound

- Add a Melody lane Sound control with Piano, Clean guitar and Distorted guitar. The selected sound is project-persisted per lane, independent of the melody's Piano/Fretboard performance target and saved physical positions. The same melody can therefore sound different in different lanes. Changing this choice must not modify the global Fretboard/Harmony guitar-tone preference or another lane.
- Existing projects may have different pattern performance targets within one lane. To avoid changing their sound, an unset legacy lane retains today's per-pattern piano/guitar selection and current shared guitar-tone behavior until the user explicitly picks a sound; present that state clearly. Newly created lanes use Piano as the explicit default.
- Route live Writer playback using the lane's explicit choice, including simultaneous lanes with different guitar tones, while preserving note duration, mix, timing and clipping. Distinguish tones in event grouping and pass them through to the sound sink rather than using the global setting. Preserve existing behavior in other lanes. Sound changes take effect on the next transport start, consistent with current event flattening. Persist sound through project and named-version save/load, duplication and undo/redo. Existing melody performance editing is unchanged.

## Constraints, non-goals and verification

- Do not change Guitar Strum, Harmony, Drums or audio lane interaction or their sound preferences. Do not add automation, sub-bar resizing, independent copied content by default, or unrelated timeline capabilities.
- Retain old project/save compatibility, canonical Save System linkage and recovery, history grouping, persistence coordination, section repeats and project-switch behavior. Handle missing pattern/save references without losing placements.
- Test wrapped and single-row resizing, limits, adjacent blocks, cancellation, destination placement, linked edits and Make Unique; test compact/wide and scaled-text layouts, accessibility actions, both themes and actual populated runtime screenshots. Test lane-sound serialization and legacy fallback, playback routing including concurrent tones, undo/redo and save/load. Run the repository's required formatting, analysis and focused tests.

## Builder decisions

The implementer may choose the gesture geometry, repeat destination picker and exact visual affordances, provided they satisfy the behavior and constraints above. Preserve existing Writer patterns and shared components where appropriate without forcing a shared redesign onto other lanes.
