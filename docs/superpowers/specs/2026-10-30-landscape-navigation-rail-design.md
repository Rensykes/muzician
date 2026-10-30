# Landscape Navigation Rail and Instrument Dock — Design

## Problem

On wide/landscape viewports (observed at 1440×900 on
https://muzician.bytebakehouseinc.xyz/):

- The global navigation is a full-width 56px bottom bar (`_AppShell` in
  `lib/main.dart`). In landscape, height is the scarce dimension, so the bar
  wastes the most valuable space.
- Fretboard and Piano pin the canvas at 212/226px and put a 316–360px side
  inspector beside it. Below the canvas there are ~400px of empty space holding
  only the empty-state hint. The canvas width is also reduced by the side
  inspector, so fewer frets/keys are visible.
- Piano Roll and Writer already use the full height well; only the navigation
  needs to change for them.

## Goals

1. Replace the bottom bar with a compact left navigation rail on landscape
   viewports, keeping the bottom bar for portrait and narrow screens.
2. On tall-enough wide viewports, give Fretboard/Piano a full-width canvas,
   modestly scaled up, with a multi-column inspector dock below it.
3. Preserve all workspace, provider, panel, scroll and selection state across
   rail ↔ bar and layout-tier changes (rotation, window resize, theme switch).

## Non-goals

- No changes to Piano Roll or Writer internals (Roll keeps its own
  Quick/Scale/Hum recorder/Save/Import tool row).
- No change to the legacy (non-Studio) instrument layout, Song code or data.
- No changes to compact portrait or short-landscape instrument layouts beyond
  the narrower width caused by the rail.
- No new routing; navigation stays index-based with `IndexedStack`.

## Design

### 1. Adaptive navigation

- `useNavigationRail(Size size)` returns `size.width >= 600 && size.width > size.height`.
  This includes phone landscape (e.g. 844×390).
- `StudioNavigationRail`: ~80px wide, left edge, opaque `StudioPalette.surface`
  with a 0.5px right border matching the bar's top border. Workspace
  destinations (Fretboard, Piano, Roll, Song, Writer) are stacked from the top;
  Settings is pinned at the bottom. Song stays visible, disabled, with the lock
  badge, tooltip and "Temporarily unavailable" semantic hint. Items are ≥56px
  tall and the full rail width (≥44px targets), with icon + 11px label, active
  color `palette.sky`. If the height is too small, the rail scrolls rather than
  overflowing.
- Both rail and bar render each destination with `ValueKey('nav_<Label>')`
  (existing tests and behaviors rely on these keys). Only one of them is
  mounted at a time.
- Rail and bar share a single destination list and the same `_setTab`
  callback, including haptics and the Song guard.
- The workspace `IndexedStack` is wrapped in a `KeyedSubtree` with a
  `GlobalKey`, so switching between rail and bar reparents rather than
  recreates the workspaces.
- With the rail visible, the rail consumes the left safe-area inset
  (`SafeArea(right: false)`), and the workspace receives
  `MediaQuery.removePadding(removeLeft: true)` so the inset is not applied twice.
- The rail/bar are hidden during startup hydration, recovery and failure views,
  exactly like the bar today.

### 2. Fretboard/Piano dock tier (Studio only)

`_StudioInstrumentWorkspace` gains a third tier. Tier selection on the body
`LayoutBuilder` constraints:

| Tier | Condition | Layout |
| --- | --- | --- |
| compact | `!wide` | unchanged |
| side | `wide && (shortLandscape \|\| maxHeight < 640)` | unchanged side inspector |
| dock | `wide && !shortLandscape && maxHeight >= 640` | new |

Dock layout (`Key('studioInstrumentDockLayout')`), top to bottom: header →
controls (Input/View menus) → scaled full-width canvas → audition controls →
selection disclosure → dock filling the remaining height.

- When the body width is ≥ 1100, the dock (`Key('instrumentDock')`) shows three
  columns at once: Notes (flex 3) | Voicings (flex 4) | Setup (flex 3), each
  with a small section title and its own vertical scroll. The dock header row
  holds Scale, Library and the collapse toggle (`instrumentInspectorToggle`).
  There are no tabs and no Setup shortcut, because Setup is always visible.
- When the body width is < 1100, the dock area reuses the existing tabbed
  inspector at full width.
- When collapsed, the dock shows only its header row, so Scale, Library and
  expand stay reachable. Selection and audition stay above the dock.
- Each panel subtree (scroll view plus content) is wrapped in a `KeyedSubtree`
  with a per-panel `GlobalKey`. Scroll offsets, carousel offsets and detection
  state survive tier changes, collapse and theme changes. Existing
  `ValueKey('instrumentInspector<Label>Scroll')` keys stay on the scroll views.

### 3. Canvas scaling

- New `ScaledInstrumentBoard(scale, baseHeight, child)` is a `LayoutBuilder` +
  `FittedBox(fit: BoxFit.fill, alignment: topLeft)` around
  `SizedBox(width: maxWidth / scale, height: baseHeight)`. Flutter transforms
  hit testing and pointer `localPosition` through `FittedBox`, so the painters,
  gestures and horizontal scrolling of `GuitarFretboard`/`PianoKeyboard` are
  untouched.
- The canvas is always wrapped (scale 1.0 is an identity), so the board's
  element tree and scroll controller survive tier changes.
- `dockCanvasScale(double bodyHeight) = 1 + 0.25 * ((bodyHeight - 640) / 400).clamp(0, 1)`
  applies in the dock tier only: 640 → 1.0, 1040+ → 1.25. All other tiers use 1.0.
- The canvas `SizedBox(key: studioInstrumentCanvas)` height becomes
  `baseHeight * scale`, where `baseHeight` is 212 (with mode segment) or 226.

### 4. Documentation

Update `DESIGN.md` (Shared workspace structure; Fretboard and Piano), `README.md`
(Features navigation paragraph), and `AGENTS.md` (Instrument UX V2 paragraph)
to describe the rail and the dock tier.

## Testing

- Unit: `useNavigationRail` for 390×844 (false), 844×390 (true), 1024×768
  (true), 1440×900 (true), 599×400 (false) and 700×800 (false); `dockCanvasScale`
  at 600, 640, 840, 1040 and 1400.
- Widget: rail renders all destinations with `nav_*` keys, Song disabled with
  hint, Settings below the workspaces, tap callbacks; and the rail does not
  overflow at height 360.
- Shell: at 1440×900 the rail is shown and there is no bottom bar; at 390×844
  the bar is shown and there is no rail. Resizing between them keeps the
  `IndexedStack` index and does not recreate workspace state.
- Instrument: the 1440×900 dock shows three columns and the canvas height is
  greater than base; the 1024×768 dock shows the tabbed inspector, and the
  canvas is full width with no side inspector. The 844×390 and 390×844 tiers
  are unchanged. Voicings scroll offset is retained across a dock ↔ side resize
  and collapse. `ScaledInstrumentBoard` delivers taps at scaled positions to
  the right child coordinates.
- Full `flutter test` and `flutter analyze` must pass. Visual verification at
  1440×900, 1024×768, 844×390 and 390×844.
