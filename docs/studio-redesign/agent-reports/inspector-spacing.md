# Inspector spacing correction — 21 October 2026

The supplied populated Fretboard screenshots showed centered Notes content in a fixed 420px viewport and compounded Setup spacing. Studio now places detection directly below its tab and lets the content determine its height. The compact page owns vertical scrolling; the existing bounded wide inspector rail owns it on larger windows. Horizontal note/chord/scale rows retain their own scrolling. Legacy detection keeps its prior standalone viewport behavior through the default `embedded: false` setting.

Setup starts with useful configuration. Studio spacing between related groups is 8px, duplicate external Capo/Range headings are removed, tuning's extra bottom padding is removed and its category/list gap is 4px. Tuning presets align with their parent and use the Studio rectangular control shape. Clear all selections is a quiet red text action at the bottom, with a minimum 44px target and the same clearing callbacks. Both palettes share the correction. No music calculations, provider state, gesture/painter logic, Song behavior or iOS project files were changed.

## Changed files

- `lib/features/instrument_shared/instrument_screen.dart`: remove the Studio-only 420px Notes wrapper and opt into embedded detection.
- `lib/features/instrument_shared/shared_detection_panel.dart`: embedded content sizing, top-aligned switcher, inherited vertical scrolling; standalone behavior remains default.
- `lib/main.dart`: compact Fretboard/Piano Setup group spacing and bottom text clear action.
- `lib/features/fretboard/tuning_selector.dart`: Studio spacing, inset and control corners.
- `lib/features/fretboard/capo_control.dart`: remove redundant Studio vertical padding.
- `test/features/instrument_shared/studio_instrument_workspace_test.dart`: actual heading position (12–32px below Notes), no nested vertical viewport, exact 8px trailing result padding across populated compact/wide/landscape and 320px text1.5.
- `test/features/instrument_shared/studio_instrument_app_test.dart`: actual Setup ordering, 44px clear control, single native labels, close mode label/control spacing and clearing behavior at 320px text1.5, 390px and 1024px, including live palette switching with retained selection.
- `docs/fretboard.md`, `docs/piano.md`: revised Setup order, content sizing and scroll ownership.

## Verification

- Changed Dart paths formatted.
- `flutter test --no-pub test/features/instrument_shared/studio_instrument_workspace_test.dart test/features/instrument_shared/studio_instrument_app_test.dart`: 30 passed.
- `flutter analyze`: no issues found (4.5 seconds).
- Additional actual-app rerun after adding live-palette assertions: 7 passed.
- Parent owns native populated screenshot comparison against the supplied references and compact/wide runtime review. Tests establish geometry and reachability, not visual fidelity.
- Root AGENTS reviewed after implementation: no persistent architecture or verification rule changed, so no guidance edit needed. Parent owns root product/design/README/ledger reconciliation.

The working tree already contained a broad Studio implementation. All edits above were applied to that existing state without resets or unrelated cleanup.
