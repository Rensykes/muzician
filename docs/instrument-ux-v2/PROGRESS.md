# Instrument UX V2 delivery record

## Active-scale chord suggestions — 22 October 2026

Fretboard and Piano now filter automatic **From notes** suggestions by every
chord tone in the active scale. A configured project key takes precedence over
the instrument's local scale. With no active scale, the full catalogue remains
available. Changing or clearing the scale refreshes cached results while keeping
the captured query and native selection. A captured note outside the scale
returns no suggestions; explicit **By chord** choices keep their existing
key-conflict confirmation.

Validation:

- All 15 shared voicing-rule tests and 7 shared voicing-widget tests pass.
- Coverage includes major/pentatonic scales, both instruments' generated pitches,
  local/project scale changes and clearing, project precedence, query/selection
  retention, in-key application and explicit out-of-key By chord confirmation.
- Widget checks cover compact 390×800 and wide 1024×768 viewports.
- `flutter analyze --no-pub`: no issues. All four changed Dart files are formatted;
  `git diff --check` passes.
- The updated native debug build launched on iPhone 18 Pro and iPad Pro 11-inch
  (M5), iOS 27. On iPhone, C + E in C major starts with C, Am and Cmaj7;
  applying C preserves the query and succeeds without an out-of-key dialog.
  [Populated phone evidence](evidence/scale-filter-fretboard-phone.png).
- Tablet input through the simulator helper was unresponsive; the wide behavior
  is covered by the widget tests and a populated Flutter-rendered
  [wide Piano capture](evidence/scale-filter-piano-wide.png).
  Temporary simulator helpers were stopped.
  Xcode's automatic project/scheme rewrites were restored; no signing changes.

## Compact actions refinement — 22 October 2026

This refinement supersedes the earlier stacked selection-summary layout below.
Fretboard and Piano now have a single 44px selection row outside inspector tabs.
It shows the detected chord and note count (or just the count for an exact
selection); **Actions** opens note details, Save idea and Add to Writer in one
live-theme sheet. Free-mode eligibility explanations appear there. Switching
Notes / Voicings / Setup or collapsing the inspector does not move the action
entry. A stable widget identity preserves sheet actions across rotation.

Free/Chord and Exact/Solo are compact menus with current values, accessible
Input/View labels, selected checks and explanatory choices. Setup starts with
instrument settings. Menus wrap at enlarged text sizes. Very short portrait
layouts use the compact header and tighter inspector margins. The chord diagram
uses equal 12px horizontal gutters and accounts for selected/unselected border
insets; upper-fret labels remain in the left gutter.

Validation for this refinement:

- `flutter analyze --no-pub`: no issues.
- 113 tests passed across `test/features/instrument_shared`,
  `test/features/fretboard/chord_diagram_test.dart`, and
  `test/theme/studio_workspace_integration_test.dart`.
- Coverage includes the actual app at 320×568 with 1.5× text, menu wrapping at
  320px with 2× text, rotation with an open sheet, theme and panel retention,
  Free/Chord eligibility, and raster centering at frets 1 and 12.
- Native debug builds launched on iPhone 18 Pro and iPad Pro 11-inch (M5), iOS 27.
  Populated screenshots were compared with the user's density/alignment examples.
  Save idea from the iPad selection sheet correctly opened the existing library.
- Generic simulator build hit an Xcode architecture check; device-targeted
  `flutter run --no-pub --no-resident` succeeded on both simulators. Flutter
  emitted a non-blocking native-assets SdkRoot diagnostic after build success.
- No signing/deployment changes: automatic Xcode rewrites were restored.
  Full repository tests and Android/web release builds were not run.

| Refined view | Evidence |
| --- | --- |
| Compact Fretboard with C + E | [Selection row](evidence/compact-actions-phone-populated.png) |
| Centered chord diagrams, inspector scrolled | [Diagrams](evidence/compact-actions-phone-diagrams.png) |
| Dedicated exact-selection actions | [Action sheet](evidence/compact-actions-phone-actions.png) |
| Setup without repeated summary/mode bars | [Setup](evidence/compact-actions-phone-setup.png) |
| Wide Piano with C major | [iPad](evidence/compact-actions-ipad-populated.png) |

PRODUCT, DESIGN, README and both instrument guides were reconciled. AGENTS now
records the single selection disclosure and compact accessible mode controls.


## Implemented behavior

The [implementation plan](PLAN.md) replaces whole-page instrument scrolling
with a fixed playable surface and a bounded inspector. Compact portrait keeps
it below the instrument; wide and short landscape put it alongside. Inspector
tabs, collapse, theme changes and layout changes preserve mounted state.

Voicings remain horizontal. **From notes** requires every captured pitch class,
with extra chord tones allowed within the active scale, when set. Manual edits
update the query; applying a result
preserves it, result order and horizontal position. **Use current notes** refreshes
it explicitly. **By chord** has independent root/quality selectors and enumerates
available generated realizations for current instrument settings.

Song is visibly disabled with an accessible explanation. Normal navigation does
not mount it; a saved Song destination restores to Writer. Its implementation,
arrangements and serializers remain intact.

## Verification — 22 October 2026

- `flutter analyze --no-pub`: no issues.
- Final formatting check: 18 changed Dart files, zero formatting changes;
  `git diff --check` clean.
- Focused regression suite after the final summary refinement: **148 tests passed**.
- The suite covers rules, both instruments' search/application, deferred provider
  notifications, horizontal offset, theme/panel state, fixed canvases at compact,
  wide and short landscape sizes, scaled text, spelling, piano preview painting,
  Song navigation and startup preference fallback.
- Native iPhone 18 Pro and iPad Pro 11-inch (M5), iOS 27 simulator screenshots
  were inspected with populated selections. The iPhone was rebuilt from the
  current source on 22 October; the iPad evidence was captured on 21 October.
- Landscape inspector scrolling reveals the horizontal cards while the piano
  remains at the same position. Rotation also retains the inspector offset.
- Initial landscape gesture captures were duplicates because the raw input used
  logical instead of physical landscape coordinates; they were replaced after
  observing a real scroll. This was a verification-tool issue, not an app fix.
- Visual review found an overly narrow Exact selection summary beside its
  actions on compact screens; the final refinement stacks actions when the
  title cannot fit beside them.

Commands for the focused suite:

```sh
flutter test --no-pub \
  test/features/instrument_shared \
  test/features/instrument_spelling_test.dart \
  test/features/piano/piano_chord_diagram_test.dart \
  test/schema/rules/instrument_voicing_search_rules_test.dart \
  test/store/app_bootstrap_startup_test.dart \
  test/main_startup_test.dart \
  test/theme/studio_workspace_integration_test.dart
```

## Runtime evidence

| View | Evidence |
| --- | --- |
| Compact Fretboard, C + E query | [Before scroll](evidence/iphone-fretboard-from-notes.png), [after scroll](evidence/iphone-fretboard-scrolled.png) |
| Compact Piano, C + E query | [Portrait](evidence/iphone-piano-from-notes.png), [readable summary](evidence/iphone-piano-summary.png) |
| Short landscape Piano | [Search controls](evidence/iphone-piano-landscape.png), [cards after scrolling](evidence/iphone-piano-landscape-scrolled.png) |
| Wide Piano, query retained after applying C | [Applied result](evidence/ipad-piano-from-notes-applied.png) |
| Wide Piano, independent chord browsing | [By chord](evidence/ipad-piano-by-chord.png) |

The screenshots retain Studio's native instrument geometry, dark surfaces,
accented selection and horizontal diagrams. The V2 fixed-canvas composition
supersedes the earlier whole-page Studio compact layout. On short viewports,
users still scroll inspector content to reach every control; that scroll no
longer moves the instrument. Auxiliary summary/actions on the landscape
instrument side can scroll independently.

## Limits and scope

Guitar generation includes complete shapes within four adjacent frets plus
open/capo strings; it does not certify fingering ergonomics. Piano generation
includes ordered inversions/open spacings in the configured range, spanning at
most 23 semitones, without dropping chord tones. Neither claims every theoretical
permutation or doubling. Search has no arbitrary small result cap; lists are
built lazily and generated results cached. Large guitar searches can contain
tens of thousands of candidates; release-device performance is not benchmarked.

No persistence schema, dependency, signing or deployment change is required.
Flutter's automatic Xcode project rewrites during simulator builds were reverted.
Instrument undo and a Save/Library redesign remain outside this phase. Android,
web release and the full repository test suite were not run for this change.

## Delegation and documentation

Three fresh GPT-6 Luna xhigh agents started the layout, voicing and Song
workstreams. Their usage limit interrupted implementation; the parent integrated
and completed their saved work. A fresh Luna 6 xhigh final audit found no
functional regression and requested completion of the landscape evidence and
plan checklist. Another fresh Luna 6 xhigh agent handled the compact summary
refinement found during native review. The audit agent then rechecked the
updated screenshots, completed plan and summary diff: both acceptance gaps were
closed and no new actionable issue was found.

PRODUCT, DESIGN, README, Fretboard/Piano guides and Song/Writer guides describe
the shipped behavior. AGENTS was reviewed and records the persistent fixed
canvas, mounted panel, captured query and temporary Song contracts.
