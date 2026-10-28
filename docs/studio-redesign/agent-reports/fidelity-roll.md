# Piano Roll Studio fidelity refinement — 19 October 2026

## Delivered

Compared the Roll concept (`06-studio-piano-roll.png`) with the actual phone and iPad captures (`05-roll-studio-portrait.png`, `13-roll-studio-ipad.png`). The main mismatch was the tall legacy builder pill layout inside a shallow Studio inspector: normal phone portrait only exposed its title and Root, hiding musical choices and Add Stack.

- Studio builder now uses Chord / Custom segments, four compact Root / Quality / Inversion / Duration fields, and a mint Add stack action carrying the actual note preview. Each field/action remains at least 44 logical pixels high. These use the existing canonical and lossless editing operations; no octave, velocity or other invented control was added.
- Fields open named, closeable choice dialogs through the live Studio route helper. A theme switch while a chooser is open retains its route and updates the surface.
- Inspector tabs have an active underline. The phone dock is bounded to 33% of available height (80–220px), preserving scroll at short heights/large text. Normal compact portrait shows the full canonical builder without scrolling. Toolbar/utility buttons use compact 44px targets rather than padded 48px hit boxes.
- Grid frame uses an 8px Studio radius. Pitch sidebar has visible white/black keys; grid rows are clearer, scale rows use a restrained musical tint, and sufficiently wide note blocks include octave labels.
- Fixed a reproduced tall-iPad defect: the sidebar/grid Row centered its content when shorter than its viewport, leaving a 135px gap below the ruler at 834×1210. Studio stretches that Row so the pitch rows begin under the ruler. Legacy Row alignment remains unchanged.

## Preservation

Raw Listener, all four synchronized scroll controllers, gesture state machine, zoom bounds, resize handle, note/time math, playback, five tools, Quick, column versus note selection, scale/save/import/Hum actions and capability flags are unchanged. Song retains its legacy layout, palette, builder and behavior. Canonical x = tick × cell width; y = (range end − MIDI note) × row height. No store/model/rule changes.

## Verification

- `dart format` via the cached SDK binary: clean, four changed Dart paths.
- `flutter test --no-pub test/features/piano_roll`: **78 PASS**.
- `flutter analyze --no-pub`: **PASS**, no issues (2.1s).
- Existing tests cover both themes at 390×844, 844×390, 844×310, 390×450 and 1024×768, plus 320px / 1.5× text, tools, Quick, selection, sheets, isolated hosts and retained live-theme grid/builder state.
- New regressions at 390×700, 1024×768 and 834×1210 assert all canonical fields/Add stack are hit-testable without scrolling, ≥44px field heights, grid >220px, Duration 1/2 inserts 8-tick notes, an open chooser follows a live theme switch without replacing its element, and grid top aligns with ruler bottom.
- The tall-iPad test failed with the prior 135px gap and passed after the Row alignment fix.

Feature guide `docs/piano_roll.md` updated. AGENTS reviewed; no persistent rule/architecture change needed. Parent owns shared header, navigation, transport, README reconciliation and final native screenshot recapture. Native screenshots reviewed here were the pre-refinement evidence; no claim that a new native capture was completed by this agent.
