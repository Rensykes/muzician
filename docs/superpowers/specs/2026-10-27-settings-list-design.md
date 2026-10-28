# Settings List Redesign

## Intent
Replace the Settings screen's stack of cards with a compact, coherent grouped list, so recovery is visually integrated and does not look like an oversized exception.

## Goals and constraints
- Preserve every setting, interaction, persistent value, and Data Recovery backup action.
- Use Studio semantic palette colors, compact spacing, section labels, and dividers instead of standalone cards.
- Keep controls readable, accessible, and scrollable on iPhone; long backup entries remain expandable.
- Do not change settings behavior or recovery data handling.

## Approaches
- **Selected: grouped sections with dividers.** Matches the existing Studio preference for unframed controls and is compact without hiding settings.
- Retain cards and shrink Data Recovery: smallest visual diff, but does not fulfill moving away from the card design.
- Collapse settings into an accordion: reduces initial height but adds interaction and hides important controls.

## Implementation calls
Redesign the full Settings screen in place, keeping current section order and preserving the recovery panel's semantics/actions. Update the Settings feature guide/README overview if needed. Verify with focused widget coverage, Flutter analysis/tests, and iPhone installation if a connected, trusted, provisioned device is available.
