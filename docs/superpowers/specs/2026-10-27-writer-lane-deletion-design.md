# Writer lane deletion

## Intent and scope

Make Drums, Sample, Guitar Strum, and Melody lanes removable from Writer without removing their section or reusable saved ideas. Lyrics remain unchanged, as does existing Harmony deletion and its safeguards.

## Approaches

- **Selected: a delete control on each lane**, consistent with the existing Harmony lane control. It is direct and discoverable, at the cost of an additional control in each lane header.
- **Section Mixer action:** avoids adding controls to lane headers but makes the action less direct and less consistent with Harmony.

## Behavior and constraints

- Show an accessible, labeled delete control on each of the four lane types. Confirm deletion, describing that the lane and its section content will be removed while reusable saved ideas remain.
- Cancel makes no changes. Confirm removes the lane and its placements from the section in one undoable Writer action, including across section repeats. Other lanes and section lyrics remain unchanged.
- Preserve reusable saved ideas and audio needed by retained saves or undo history; do not delete shared source material. Existing Harmony behavior and anchored-lane safeguards remain unchanged.
- Continue using the existing Writer state and persistence mechanisms; avoid unrelated changes. Keep controls usable in compact and wide layouts.

## Verification

Add focused coverage for all four lane types, confirmation and cancellation, removal of only the selected lane, undo, and preservation of reusable content. Verify compact and wide layouts, run the relevant tests and analyzer, and update the Writer feature documentation and README as required.
