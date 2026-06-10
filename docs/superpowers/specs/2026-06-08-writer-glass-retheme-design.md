# Writer Glass Retheme

Full visual migration of the Songwriter ("Writer") tab from raw Material widgets
to the app's glassmorphism dark theme, matching Fretboard, Piano, and Roll pages.

## Problem

The Writer page uses default Material `Scaffold`, `Card`, `ActionChip`,
`showModalBottomSheet`, and hardcoded `Colors.teal`.  Every other page uses:

- `MuzicianTheme.gradientColors` background
- `CompactAppBar` + `StatusChip`
- Glass containers (`glassBg` / `glassBorder`)
- `showWidgetSheet` (glass bottom sheets)
- Themed accent colors (`sky`, `teal`, `violet`, `emerald`, `orange`)

Result: Writer looks like a different app.

## Scope

Visual retheme only.  No changes to data model, store, rules, or business logic.
No new features.  No structural layout changes beyond splitting the header.

---

## 1. Screen Shell (`songwriter_screen.dart`)

### Before

```dart
Scaffold(
  body: SafeArea(child: Column([header, Expanded(ListView(...))]))
)
```

### After

```dart
Theme(
  data: MuzicianTheme.dark(),
  child: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: MuzicianTheme.gradientColors,
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Column([
        CompactAppBar(title: 'Writer', chipLabel: projectName, actions: [helpIcon, menuIcon]),
        _WriterConfigStrip(...),
        Expanded(ListView(...)),
      ]),
    ),
  ),
)
```

Remove `Scaffold` — the gradient container replaces it.  The parent app scaffold
already provides the bottom navigation bar.

### Empty state

Replace the plain `Text('Build a song...')` with an `InstrumentInsightHint`:

- Icon: `Icons.edit_note_rounded`, color `sky`
- Title: "Start composing"
- Subtitle: "Add a section, build lanes, and drop chord blocks"

### Add Section button

Replace `TextButton.icon` with a glass chip:

```dart
GestureDetector(
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: MuzicianTheme.sky.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: MuzicianTheme.sky.withValues(alpha: 0.3)),
    ),
    child: Row([Icon(Icons.add_rounded, sky), Text('Add section', sky)]),
  ),
)
```

---

## 2. Header → CompactAppBar + _WriterConfigStrip (`songwriter_header.dart`)

### Before

Single `Row` packing: project name chip, play button, metronome button, spacer,
key chip, tempo chip, new-project button, overflow menu — all on one 44px line.

### After — two visual layers

**Layer 1: `CompactAppBar`**

```
Writer  (projectName)                    ?  ⋮
```

- `title: 'Writer'`
- `chipLabel: projectName` (taps to rename via dialog — existing behavior)
- `actions: [helpIcon, overflowMenuIcon]`
- Help icon opens `showAppInfoPanel(context, initialTab: ...)` (if Writer tab
  exists in info panel) or is omitted for now.
- Overflow menu keeps "Save / Load" and "Edit structure".

**Layer 2: `_WriterConfigStrip`**

44px glass bar, same visual language as Roll's `_TransportStrip`:

```dart
Container(
  height: 44,
  margin: EdgeInsets.fromLTRB(12, 4, 12, 4),
  decoration: BoxDecoration(
    color: MuzicianTheme.glassBg,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: MuzicianTheme.glassBorder),
  ),
  child: Row([
    _ConfigReadout(label: 'KEY', value: keyLabel, onTap: openKeySheet),
    divider,
    _ConfigReadout(label: 'BPM', value: '$tempo', accent: true, onTap: openTempoSheet),
    divider,
    playButton,          // same ▶/⏹ toggle
    metronomeButton,     // same 🎵/muted toggle
    divider,
    newProjectButton,    // ⊞ icon
  ]),
)
```

`_ConfigReadout` follows the same pattern as Roll's `_Readout`: label in
`textMuted` 9px + value in `textPrimary` 12–14px.

Play/metronome buttons: `_IconBtn` style from `transport_strip.dart` (44×44,
`InkResponse`, `textSecondary` icons).

### Dialogs

- `_TempoSheet` → wrap in `showWidgetSheet(title: 'Tempo', child: ...)`
- `_KeySheet` → wrap in `showWidgetSheet(title: 'Key', child: ...)`
- Project name dialog stays as `AlertDialog` (quick text input).
- New project confirmation stays as `AlertDialog`.

---

## 3. Section Cards (`songwriter_section_card.dart`)

### Before

```dart
Card(child: Padding(padding: EdgeInsets.all(8), child: Column(...)))
```

### After

```dart
Container(
  margin: EdgeInsets.fromLTRB(0, 0, 0, 12),
  padding: EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: MuzicianTheme.glassBg,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: MuzicianTheme.glassBorder),
  ),
  child: Column(...),
)
```

The outer `ListView` already has `padding: EdgeInsets.all(12)`, so horizontal
margin comes from the list padding.

### Section header row

- Label `TextFormField`: `color: MuzicianTheme.textPrimary`, hint:
  `MuzicianTheme.textMuted`
- `_ValuePill` → glass pill:
  ```dart
  Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: MuzicianTheme.teal.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: MuzicianTheme.teal.withValues(alpha: 0.3)),
    ),
    child: Row([Text(label, teal), Icon(Icons.arrow_drop_down, teal, size: 16)]),
  )
  ```
- Remove section `×` → `IconBtn` with `MuzicianTheme.textSecondary`

### BarRuler

- Numbers: `MuzicianTheme.textMuted`, `fontSize: 10`, `fontWeight: w600`,
  `fontFeatures: [FontFeature.tabularFigures()]`

### Add Lane button

- `PopupMenuButton` child: glass chip with `emerald` accent,
  `Icons.add_rounded`, "Add lane" label.

### Stepper dialogs

Keep as `AlertDialog` — they're quick numeric inputs, not panels.

---

## 4. Lane Rows (`songwriter_lane_row.dart`)

### Lane label (72px gutter)

- Harmony lanes: `MuzicianTheme.violet`, `fontSize: 12`, `fontWeight: w600`
- Save lanes: `MuzicianTheme.teal`, `fontSize: 12`, `fontWeight: w600`
- Custom labels (user-typed): below kind label, `MuzicianTheme.textMuted`,
  `fontSize: 10`

### Grid painter

Replace `Theme.of(context).dividerColor.withValues(alpha: 0.4)` with
`MuzicianTheme.glassBorder`.

### Playhead painter

Replace `Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)` with
`MuzicianTheme.sky.withValues(alpha: 0.7)`.

### Add block `+` button

Style as `IconBtn` with accent color matching lane kind:
- Harmony: `MuzicianTheme.violet`
- Save: `MuzicianTheme.teal`

### Remove lane `×` button

`IconBtn` with `MuzicianTheme.textSecondary`, `size: 16`.

---

## 5. Block Tiles (`songwriter_block_tile.dart`)

### Color scheme

```dart
Color _blockFill(SongBlock block, bool highlighted, bool broken) {
  if (broken) return MuzicianTheme.red.withValues(alpha: 0.25);
  final base = block.chordRootPc != null ? MuzicianTheme.violet : MuzicianTheme.teal;
  return base.withValues(alpha: highlighted ? 0.45 : 0.25);
}

Border? _blockBorder(SongBlock block, bool highlighted, bool broken) {
  if (broken) return Border.all(color: MuzicianTheme.red.withValues(alpha: 0.5));
  final base = block.chordRootPc != null ? MuzicianTheme.violet : MuzicianTheme.teal;
  if (highlighted) return Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5);
  return Border.all(color: base.withValues(alpha: 0.5));
}
```

### Text styling

- Primary label (chord symbol / save name): `MuzicianTheme.textPrimary`,
  `fontSize: 13`, `fontWeight: w700`
- Secondary label (roman numeral): `MuzicianTheme.textMuted`, `fontSize: 10`,
  `fontWeight: w600`

### Resize handle

```dart
Container(
  width: 8,
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.15),
    borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
  ),
)
```

### Border radius

`borderRadius: BorderRadius.circular(8)` (up from 6).

---

## 6. Block Preview & Harmony Sheets (`songwriter_block_preview.dart`)

### All `showModalBottomSheet` → `showWidgetSheet`

**`showBlockPreviewSheet`:**
```dart
showWidgetSheet(
  context: context,
  title: label.text ?? snapshot.instrument,
  child: Column([thumbnail, noteChips]),
);
```

**`showBrokenReferenceSheet`:**
```dart
showWidgetSheet(
  context: context,
  title: 'Broken Reference',
  child: Column([message, relink tile, delete tile]),
);
```

**`showHarmonyBlockSheet`:**
```dart
showWidgetSheet(
  context: context,
  title: '$chordSymbol ${numeral ?? ""}',
  child: Column([noteChips, tabBar, tabBarView]),
);
```

Note: `showWidgetSheet` does not support `isScrollControlled` — the sheet has a
max height.  The harmony block sheet's `TabBarView` with `SizedBox(height: 170)`
fits within this.

### Voicing / ThirdAbove / Library cards

Replace `Theme.of(context).dividerColor` with `MuzicianTheme.glassBorder`.
Text: `fontSize: 11` → keep, but color `MuzicianTheme.textPrimary`.

---

## 7. Grid Painter (`songwriter_grid.dart`)

### BarGridPainter

Color parameter: callers pass `MuzicianTheme.glassBorder` instead of
`Theme.of(context).dividerColor.withValues(alpha: 0.4)`.

### PlayheadPainter

Color parameter: callers pass `MuzicianTheme.sky.withValues(alpha: 0.7)` instead
of `Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)`.

### BarRuler

Style: `TextStyle(color: MuzicianTheme.textMuted, fontSize: 10, fontWeight:
FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])`.

---

## 8. Save Panel (`songwriter_save_panel.dart`)

Wrap the `showModalBottomSheet` → `showWidgetSheet`.  The inner
`SongwriterSavePanel` widget stays — just the sheet host changes.

---

## 9. Harmony Chord Sheet (`harmony_chord_sheet.dart`)

Wrap `showModalBottomSheet` → `showWidgetSheet(title: 'Harmony Block', child:
...)`.  Inner chord picker content stays.

---

## 10. Structure Editor (`songwriter_structure_editor.dart`)

This is a `fullscreenDialog` `MaterialPageRoute`.  It stays as-is for now — it's
a separate full-screen editor, not a sheet.  Future pass can glass-ify it.

---

## Files Changed (9 files)

| File | Change |
|---|---|
| `songwriter_screen.dart` | Gradient shell, empty state, add-section chip |
| `songwriter_header.dart` | CompactAppBar + _WriterConfigStrip, sheets → glass |
| `songwriter_section_card.dart` | Glass card, glass pills, bar ruler text, add-lane chip |
| `songwriter_lane_row.dart` | Lane label colors, grid/playhead colors, button styles |
| `songwriter_block_tile.dart` | Block color scheme, text styles, border radius |
| `songwriter_block_preview.dart` | All sheets → showWidgetSheet, card border colors |
| `songwriter_grid.dart` | BarRuler text style |
| `songwriter_save_panel.dart` | Sheet wrapper → showWidgetSheet |
| `harmony_chord_sheet.dart` | Sheet wrapper → showWidgetSheet |

## Not Changed

- `songwriter_structure_editor.dart` — separate full-screen, out of scope
- `songwriter_undo.dart` — SnackBar logic, no visual change needed
- `songwriter_save_lane_filter.dart` — constants only
- All model / store / rules files — no business logic changes
- `_mockup_shell.dart` — only consumed, not modified
