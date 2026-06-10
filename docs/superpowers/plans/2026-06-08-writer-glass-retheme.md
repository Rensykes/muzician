# Writer Glass Retheme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the Songwriter ("Writer") tab from raw Material widgets to the app's glassmorphism dark theme, matching Fretboard, Piano, and Roll pages.

**Architecture:** Visual-only changes across 9 files. Replace Material `Scaffold`/`Card`/`ActionChip`/`showModalBottomSheet` with themed equivalents from `_mockup_shell.dart` and `muzician_theme.dart`. Split the current single-row header into `CompactAppBar` + a glass config strip.

**Tech Stack:** Flutter, Riverpod, existing `MuzicianTheme` + `_mockup_shell.dart` primitives

**Branch:** `writer-glass-retheme` (already created from `main`)

**Spec:** `docs/superpowers/specs/2026-06-08-writer-glass-retheme-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/features/songwriter/songwriter_grid.dart` | Modify | BarRuler text styling |
| `lib/features/songwriter/songwriter_screen.dart` | Modify | Gradient shell, empty state, add-section chip |
| `lib/features/songwriter/songwriter_header.dart` | Modify | CompactAppBar + _WriterConfigStrip, sheet wrappers |
| `lib/features/songwriter/songwriter_section_card.dart` | Modify | Glass card, glass pills, add-lane chip |
| `lib/features/songwriter/songwriter_lane_row.dart` | Modify | Lane label colors, grid/playhead colors, button styles |
| `lib/features/songwriter/songwriter_block_tile.dart` | Modify | Block color scheme, text styles, border radius |
| `lib/features/songwriter/songwriter_block_preview.dart` | Modify | All sheets → showWidgetSheet, card border colors |
| `lib/features/songwriter/songwriter_save_panel.dart` | Modify (caller) | Sheet wrapper → showWidgetSheet |
| `lib/features/songwriter/harmony_chord_sheet.dart` | Modify | Sheet wrapper → showWidgetSheet |

---

## Task 1: BarRuler Glass Text (`songwriter_grid.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_grid.dart`

This is the simplest file — zero dependencies on other tasks. Good warm-up.

- [ ] **Step 1: Add theme import**

Add at top of file:
```dart
import '../../theme/muzician_theme.dart';
```

- [ ] **Step 2: Replace BarRuler text style**

In `BarRuler.build()`, replace:
```dart
final style = Theme.of(context).textTheme.labelSmall;
```
with:
```dart
const style = TextStyle(
  color: MuzicianTheme.textMuted,
  fontSize: 10,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);
```

Also add to imports at top:
```dart
import 'dart:ui' show FontFeature;
```

- [ ] **Step 3: Verify build**

Run: `cd /Users/francescolacriola/dev/ws/muzician && flutter analyze lib/features/songwriter/songwriter_grid.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/songwriter/songwriter_grid.dart
git commit -m "style(songwriter): glass theme BarRuler text

Use MuzicianTheme.textMuted with tabular figures for bar numbers.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Screen Shell (`songwriter_screen.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen.dart`

Replace `Scaffold` with gradient container, add glass empty state and add-section chip.

- [ ] **Step 1: Add imports**

Add to existing imports:
```dart
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
```

- [ ] **Step 2: Replace `_openSaveLoad` method body**

Replace:
```dart
void _openSaveLoad(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SizedBox(height: 480, child: SongwriterSavePanel()),
  );
}
```
with:
```dart
void _openSaveLoad(BuildContext context) {
  showWidgetSheet(
    context: context,
    title: 'Save / Load',
    child: const SongwriterSavePanel(),
  );
}
```

- [ ] **Step 3: Replace build method**

Replace the entire `build` method with:
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final project = ref.watch(songwriterProvider);
  final notifier = ref.read(songwriterProvider.notifier);
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: MuzicianTheme.gradientColors,
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SongwriterHeader(
            onOpenSaveLoad: () => _openSaveLoad(context),
            onOpenStructure: () => _openStructure(context),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (project.sections.isEmpty)
                  const _EmptyState(key: Key('songwriterEmptyHint')),
                for (final section in project.sections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SongwriterSectionCard(sectionId: section.id),
                  ),
                _AddSectionChip(
                  key: const Key('songwriterAddSection'),
                  onTap: () => notifier.addSection(label: null, lengthBars: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Add _EmptyState widget**

Add after the class closing brace:
```dart
class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 48,
            color: MuzicianTheme.sky.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          const Text(
            'Start composing',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add a section, build lanes, and drop chord blocks',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Add _AddSectionChip widget**

```dart
class _AddSectionChip extends StatelessWidget {
  const _AddSectionChip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MuzicianTheme.sky.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MuzicianTheme.sky.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: MuzicianTheme.sky),
              SizedBox(width: 6),
              Text(
                'Add section',
                style: TextStyle(
                  color: MuzicianTheme.sky,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Remove unused `Scaffold` import dependency**

Remove the `import 'songwriter_save_panel.dart';` if the `SongwriterSavePanel` is still needed — keep it. Check: it IS still used in `_openSaveLoad`. Keep the import.

- [ ] **Step 7: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_screen.dart`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/songwriter/songwriter_screen.dart
git commit -m "style(songwriter): gradient shell, glass empty state and add-section chip

Replace Scaffold with gradient container matching other instrument pages.
Add themed empty state with sky icon and glass add-section chip.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Header Refactor (`songwriter_header.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_header.dart`

Split the current single-row header into `CompactAppBar` + `_WriterConfigStrip`.

- [ ] **Step 1: Add imports**

Add to existing imports:
```dart
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
```

- [ ] **Step 2: Replace `SongwriterHeader.build` method**

Replace the entire `build` method with:
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final config = ref.watch(songwriterProvider.select((p) => p.config));
  final notifier = ref.read(songwriterProvider.notifier);
  final keyLabel = config.keyRoot == null
      ? 'No key'
      : '${chromaticNotes[config.keyRoot!]} ${config.keyScaleName ?? ''}'
            .trim();
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CompactAppBar(
        title: 'Writer',
        chipLabel: ref.watch(songwriterProvider.select((p) => p.name)),
        actions: [
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(
              Icons.more_vert,
              color: MuzicianTheme.textSecondary,
              size: 22,
            ),
            onSelected: (v) {
              if (v == 'saveload') onOpenSaveLoad?.call();
              if (v == 'structure') onOpenStructure?.call();
              if (v == 'rename') _editProjectName(
                context, ref,
                ref.read(songwriterProvider).name,
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'saveload', child: Text('Save / Load')),
              PopupMenuItem(value: 'structure', child: Text('Edit structure')),
              PopupMenuItem(value: 'rename', child: Text('Rename project')),
            ],
          ),
        ],
      ),
      _WriterConfigStrip(
        keyLabel: keyLabel,
        tempo: config.tempo,
        onKeyTap: () => _editKey(context, ref),
        onTempoTap: () => _editTempo(context, ref),
        onNewProject: () => _confirmNew(context, notifier),
      ),
    ],
  );
}
```

- [ ] **Step 3: Replace `_editTempo` method**

Replace:
```dart
void _editTempo(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(songwriterProvider.notifier);
  final current = ref.read(songwriterProvider).config.tempo;
  showModalBottomSheet<void>(
    context: context,
    builder: (_) =>
        _TempoSheet(initial: current, onChanged: notifier.setTempo),
  );
}
```
with:
```dart
void _editTempo(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(songwriterProvider.notifier);
  final current = ref.read(songwriterProvider).config.tempo;
  showWidgetSheet(
    context: context,
    title: 'Tempo',
    child: _TempoSheet(initial: current, onChanged: notifier.setTempo),
  );
}
```

- [ ] **Step 4: Replace `_editKey` method**

Replace:
```dart
void _editKey(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(songwriterProvider.notifier);
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => _KeySheet(
      onPick: (root, scale) => notifier.setKey(root, scale),
      onClear: () => notifier.setKey(null, null),
    ),
  );
}
```
with:
```dart
void _editKey(BuildContext context, WidgetRef ref) {
  final notifier = ref.read(songwriterProvider.notifier);
  showWidgetSheet(
    context: context,
    title: 'Key',
    child: _KeySheet(
      onPick: (root, scale) => notifier.setKey(root, scale),
      onClear: () => notifier.setKey(null, null),
    ),
  );
}
```

- [ ] **Step 5: Add `_WriterConfigStrip` widget**

Add after the `SongwriterHeader` class (before `_editProjectName`):
```dart
class _WriterConfigStrip extends ConsumerWidget {
  const _WriterConfigStrip({
    required this.keyLabel,
    required this.tempo,
    required this.onKeyTap,
    required this.onTempoTap,
    required this.onNewProject,
  });
  final String keyLabel;
  final int tempo;
  final VoidCallback onKeyTap;
  final VoidCallback onTempoTap;
  final VoidCallback onNewProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      songwriterPlaybackProvider.select(
        (s) => s.status == SongwriterPlaybackStatus.playing,
      ),
    );
    final metronomeOn = ref.watch(
      settingsProvider.select((s) => s.metronomeEnabled),
    );
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Row(
        children: [
          _ConfigReadout(label: 'KEY', value: keyLabel, onTap: onKeyTap),
          _stripDivider(),
          _ConfigReadout(label: 'BPM', value: '$tempo', onTap: onTempoTap),
          _stripDivider(),
          IconBtn(
            icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            onTap: () {
              final t = ref.read(songwriterPlaybackProvider.notifier);
              playing ? t.stopPlayback() : t.startPlayback();
            },
          ),
          IconBtn(
            icon: metronomeOn ? Icons.music_note : Icons.music_off,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .setMetronomeEnabled(!metronomeOn),
          ),
          _stripDivider(),
          IconBtn(
            icon: Icons.add_box_outlined,
            onTap: onNewProject,
          ),
        ],
      ),
    );
  }

  static Widget _stripDivider() => Container(
    width: 1,
    height: 24,
    color: MuzicianTheme.glassBorder,
  );
}

class _ConfigReadout extends StatelessWidget {
  const _ConfigReadout({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Remove old `_Chip` widget**

Delete the `_Chip` class (it's no longer used — the project name is now in `CompactAppBar.chipLabel`, key/tempo are in the config strip):
```dart
class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    onPressed: onTap,
  );
}
```

- [ ] **Step 7: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_header.dart`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/songwriter/songwriter_header.dart
git commit -m "style(songwriter): CompactAppBar + glass config strip

Split monolithic header row into CompactAppBar (title + project chip
+ overflow menu) and _WriterConfigStrip (key/bpm readouts + transport
buttons) following the TransportStrip glass-bar pattern.
Wrap tempo/key pickers in showWidgetSheet.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Section Cards (`songwriter_section_card.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_section_card.dart`

Replace `Card` with glass container, glass pills, themed text, and a glass add-lane chip.

- [ ] **Step 1: Add imports**

Add:
```dart
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
```

- [ ] **Step 2: Replace `Card` wrapper with glass container**

In `SongwriterSectionCard.build`, replace:
```dart
return Card(
  child: Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
```
with:
```dart
return Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: MuzicianTheme.glassBg,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: MuzicianTheme.glassBorder),
  ),
  child: Column(
```

And remove the corresponding closing `)` from the old `Card(child: Padding(` nesting. The closing structure should be:
```dart
      ),  // Column
    );    // Container
```

- [ ] **Step 3: Style the section label TextFormField**

In the `TextFormField`, update the `decoration` and add a `style` parameter:
```dart
TextFormField(
  key: Key('sectionLabel_$sectionId'),
  initialValue: section.label ?? '',
  style: const TextStyle(
    color: MuzicianTheme.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
  decoration: const InputDecoration(
    isDense: true,
    hintText: 'Section name (optional)',
    hintStyle: TextStyle(color: MuzicianTheme.textMuted),
    border: InputBorder.none,
  ),
  onFieldSubmitted: (v) =>
      notifier.renameSection(sectionId, v.isEmpty ? null : v),
),
```

- [ ] **Step 4: Replace remove-section IconButton with IconBtn**

Replace:
```dart
IconButton(
  key: Key('removeSection_$sectionId'),
  icon: const Icon(Icons.close, size: 18),
  onPressed: () {
```
with:
```dart
IconBtn(
  key: Key('removeSection_$sectionId'),
  icon: Icons.close_rounded,
  color: MuzicianTheme.textSecondary,
  onTap: () {
```

Note: `IconBtn` from `_mockup_shell.dart` accepts `key` as a super parameter. Check if it has `key` in its constructor — it does: `const IconBtn({super.key, ...})`.

- [ ] **Step 5: Replace add-lane PopupMenuButton child**

Replace:
```dart
child: const Padding(
  padding: EdgeInsets.all(8),
  child: Text('+ lane'),
),
```
with:
```dart
child: Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  decoration: BoxDecoration(
    color: MuzicianTheme.emerald.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: MuzicianTheme.emerald.withValues(alpha: 0.3),
    ),
  ),
  child: const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.add_rounded, size: 16, color: MuzicianTheme.emerald),
      SizedBox(width: 6),
      Text(
        'Add lane',
        style: TextStyle(
          color: MuzicianTheme.emerald,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
),
```

- [ ] **Step 6: Replace `_ValuePill` widget**

Replace the entire `_ValuePill` class with:
```dart
class _ValuePill extends StatelessWidget {
  const _ValuePill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: MuzicianTheme.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MuzicianTheme.teal.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.teal,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: MuzicianTheme.teal, size: 16),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_section_card.dart`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/songwriter/songwriter_section_card.dart
git commit -m "style(songwriter): glass section cards with themed pills

Replace Material Card with glass container. Style section label,
value pills (teal accent), remove button, and add-lane chip (emerald).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Lane Rows (`songwriter_lane_row.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_lane_row.dart`

Theme lane labels, grid/playhead colors, and the add-block button.

- [ ] **Step 1: Add import**

Add:
```dart
import '../../theme/muzician_theme.dart';
```

- [ ] **Step 2: Style lane label**

Replace:
```dart
SizedBox(
  width: 72,
  child: Text(
    lane.label ??
        (lane.kind == SongLaneKind.harmony ? 'Harmony' : 'Lane'),
  ),
),
```
with:
```dart
SizedBox(
  width: 72,
  child: Text(
    lane.label ??
        (lane.kind == SongLaneKind.harmony ? 'Harmony' : 'Lane'),
    style: TextStyle(
      color: lane.kind == SongLaneKind.harmony
          ? MuzicianTheme.violet
          : MuzicianTheme.teal,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
),
```

- [ ] **Step 3: Replace grid painter color**

Replace:
```dart
painter: BarGridPainter(
  lengthBars: lengthBars,
  color: Theme.of(
    context,
  ).dividerColor.withValues(alpha: 0.4),
),
```
with:
```dart
painter: BarGridPainter(
  lengthBars: lengthBars,
  color: MuzicianTheme.glassBorder,
),
```

- [ ] **Step 4: Replace playhead painter color**

Replace:
```dart
painter: PlayheadPainter(
  bar: activeBar!.toDouble(),
  lengthBars: lengthBars,
  color: Theme.of(
    context,
  ).colorScheme.primary.withValues(alpha: 0.7),
),
```
with:
```dart
painter: PlayheadPainter(
  bar: activeBar!.toDouble(),
  lengthBars: lengthBars,
  color: MuzicianTheme.sky.withValues(alpha: 0.7),
),
```

- [ ] **Step 5: Style add-block button**

Replace:
```dart
IconButton(
  key: Key('addBlock_$laneId'),
  icon: const Icon(Icons.add),
  onPressed: () async {
```
with:
```dart
IconButton(
  key: Key('addBlock_$laneId'),
  icon: Icon(
    Icons.add_rounded,
    color: lane.kind == SongLaneKind.harmony
        ? MuzicianTheme.violet
        : MuzicianTheme.teal,
  ),
  onPressed: () async {
```

- [ ] **Step 6: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_lane_row.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_lane_row.dart
git commit -m "style(songwriter): themed lane labels, grid and playhead colors

Violet for harmony lanes, teal for save lanes. Grid uses glassBorder,
playhead uses sky accent.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Block Tiles (`songwriter_block_tile.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`

Replace hardcoded `Colors.teal`/`Colors.tealAccent`/`Colors.red` with themed block fill/border logic.

- [ ] **Step 1: Add import**

Add:
```dart
import '../../theme/muzician_theme.dart';
```

- [ ] **Step 2: Replace Container decoration in build method**

Replace:
```dart
child: Container(
  margin: const EdgeInsets.symmetric(horizontal: 1),
  decoration: BoxDecoration(
    color: broken
        ? Colors.red.withValues(alpha: 0.25)
        : widget.highlighted
        ? Colors.tealAccent
        : Colors.teal,
    borderRadius: BorderRadius.circular(6),
    border: widget.highlighted
        ? Border.all(color: Colors.white, width: 1.5)
        : null,
  ),
```
with:
```dart
child: Container(
  margin: const EdgeInsets.symmetric(horizontal: 1),
  decoration: BoxDecoration(
    color: _blockFill(block, widget.highlighted, broken),
    borderRadius: BorderRadius.circular(8),
    border: _blockBorder(block, widget.highlighted, broken),
  ),
```

- [ ] **Step 3: Add color helper methods**

Add these as static methods or top-level functions (place before the `_PlacementDialog` class):
```dart
Color _blockFill(SongBlock block, bool highlighted, bool broken) {
  if (broken) return MuzicianTheme.red.withValues(alpha: 0.25);
  final base = block.chordRootPc != null
      ? MuzicianTheme.violet
      : MuzicianTheme.teal;
  return base.withValues(alpha: highlighted ? 0.45 : 0.25);
}

Border _blockBorder(SongBlock block, bool highlighted, bool broken) {
  if (broken) {
    return Border.all(color: MuzicianTheme.red.withValues(alpha: 0.5));
  }
  final base = block.chordRootPc != null
      ? MuzicianTheme.violet
      : MuzicianTheme.teal;
  if (highlighted) {
    return Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5);
  }
  return Border.all(color: base.withValues(alpha: 0.5));
}
```

- [ ] **Step 4: Style primary/secondary text**

Replace:
```dart
Text(primary, maxLines: 1, overflow: TextOverflow.ellipsis),
if (secondary != null)
  Text(
    secondary,
    style: const TextStyle(fontSize: 10),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
```
with:
```dart
Text(
  primary,
  style: const TextStyle(
    color: MuzicianTheme.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  ),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
),
if (secondary != null)
  Text(
    secondary,
    style: const TextStyle(
      color: MuzicianTheme.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
```

- [ ] **Step 5: Style resize handle**

Replace:
```dart
child: Container(
  width: 8,
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.3),
    borderRadius: const BorderRadius.horizontal(
      right: Radius.circular(6),
    ),
  ),
),
```
with:
```dart
child: Container(
  width: 8,
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.15),
    borderRadius: const BorderRadius.horizontal(
      right: Radius.circular(8),
    ),
  ),
),
```

- [ ] **Step 6: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_block_tile.dart`
Expected: No issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_block_tile.dart
git commit -m "style(songwriter): themed block tiles with violet/teal/red scheme

Harmony blocks use violet, save blocks use teal, broken use red.
Add text styling and increase border radius to 8.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Block Preview Sheets (`songwriter_block_preview.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_preview.dart`

Replace all `showModalBottomSheet` with `showWidgetSheet` and replace `Theme.of(context).dividerColor` with themed border.

- [ ] **Step 1: Add imports**

Add:
```dart
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
```

- [ ] **Step 2: Replace `showBlockPreviewSheet`**

Replace:
```dart
void showBlockPreviewSheet(BuildContext context, InstrumentSnapshot snapshot) {
  final label = saveCardLabel(snapshot);
  final icon = saveInstrumentIcon(snapshot.instrument);

  showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.text ?? snapshot.instrument,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SavePreviewThumbnail(snapshot: snapshot, width: 200, height: 120),
            if (snapshot.selectedNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final note in snapshot.selectedNotes)
                    Chip(
                      label: Text(note),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
```
with:
```dart
void showBlockPreviewSheet(BuildContext context, InstrumentSnapshot snapshot) {
  final label = saveCardLabel(snapshot);

  showWidgetSheet(
    context: context,
    title: label.text ?? snapshot.instrument,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SavePreviewThumbnail(snapshot: snapshot, width: 200, height: 120),
        if (snapshot.selectedNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final note in snapshot.selectedNotes)
                Chip(
                  label: Text(note),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ],
    ),
  );
}
```

- [ ] **Step 3: Replace `showBrokenReferenceSheet`**

Replace:
```dart
void showBrokenReferenceSheet(
  BuildContext context, {
  required VoidCallback onDelete,
  VoidCallback? onRelink,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This block references a deleted save.'),
          ),
          if (onRelink != null)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Re-link to another save'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onRelink();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete block'),
            onTap: () {
              Navigator.pop(sheetCtx);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}
```
with:
```dart
void showBrokenReferenceSheet(
  BuildContext context, {
  required VoidCallback onDelete,
  VoidCallback? onRelink,
}) {
  showWidgetSheet(
    context: context,
    title: 'Broken Reference',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'This block references a deleted save.',
            style: TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ),
        if (onRelink != null)
          ListTile(
            leading: const Icon(Icons.link, color: MuzicianTheme.textSecondary),
            title: const Text('Re-link to another save',
                style: TextStyle(color: MuzicianTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              onRelink();
            },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: MuzicianTheme.red),
          title: const Text('Delete block',
              style: TextStyle(color: MuzicianTheme.textPrimary)),
          onTap: () {
            Navigator.pop(context);
            onDelete();
          },
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Replace `showHarmonyBlockSheet`**

Replace the `showModalBottomSheet<void>` call in `showHarmonyBlockSheet` with `showWidgetSheet`. The key difference: `showWidgetSheet` provides its own title and padded container, so remove the manual title row.

Replace from `showModalBottomSheet<void>(` to the corresponding closing `);` with:
```dart
showWidgetSheet(
  context: context,
  title: '$title ${numeral ?? ""}'.trim(),
  child: DefaultTabController(
    length: 3,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.chordNotes.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final n in block.chordNotes)
                Chip(
                  label: Text(n),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        const TabBar(
          tabs: [
            Tab(text: 'Voicings'),
            Tab(text: 'Harmony'),
            Tab(text: 'Library'),
          ],
        ),
        SizedBox(
          height: 170,
          child: TabBarView(
            children: [
              _VoicingsTab(
                hasChord: hasChord,
                voicings: voicings,
                onAccept: (v) {
                  Navigator.pop(context);
                  onAcceptVoicing(v);
                },
              ),
              _HarmonyTab(
                hasChord: hasChord,
                thirdAbove: thirdAbove,
                onAccept: (s) {
                  Navigator.pop(context);
                  onAcceptThirdAbove(s);
                },
              ),
              _LibraryTab(
                chordMatches: chordMatches,
                scaleMatches: scaleMatches,
                onAccept: (id) {
                  Navigator.pop(context);
                  onAcceptLibrary(id);
                },
              ),
            ],
          ),
        ),
      ],
    ),
  ),
);
```

- [ ] **Step 5: Replace card border colors**

In `_ThirdAboveCard`, `_VoicingCard`, and `_LibraryMatchCard`, replace all occurrences of:
```dart
border: Border.all(color: Theme.of(context).dividerColor),
```
with:
```dart
border: Border.all(color: MuzicianTheme.glassBorder),
```

Also update the text style in those cards:
```dart
style: const TextStyle(fontSize: 11),
```
becomes:
```dart
style: const TextStyle(fontSize: 11, color: MuzicianTheme.textPrimary),
```

- [ ] **Step 6: Remove unused `saveInstrumentIcon` reference if needed**

Check if `saveInstrumentIcon` is still used — it was in `showBlockPreviewSheet`'s title row icon. Since `showWidgetSheet` provides its own title without an icon, remove the `final icon = saveInstrumentIcon(snapshot.instrument);` line.

- [ ] **Step 7: Verify build**

Run: `flutter analyze lib/features/songwriter/songwriter_block_preview.dart`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/songwriter/songwriter_block_preview.dart
git commit -m "style(songwriter): glass sheets for block preview/harmony/broken ref

Replace all showModalBottomSheet with showWidgetSheet.
Use MuzicianTheme.glassBorder for suggestion card borders.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Save Panel Sheet Wrapper (`songwriter_screen.dart` already done)

The `showWidgetSheet` wrapper for `SongwriterSavePanel` was already handled in Task 2, Step 2. This task is pre-completed.

---

## Task 9: Harmony Chord Sheet (`harmony_chord_sheet.dart`)

**Files:**
- Modify: `lib/features/songwriter/harmony_chord_sheet.dart`

Wrap the `showModalBottomSheet<SongBlock>` in a glass wrapper.

- [ ] **Step 1: Add imports**

Add:
```dart
import '../../theme/muzician_theme.dart';
```

- [ ] **Step 2: Replace showModalBottomSheet wrapper**

The function `showHarmonyChordSheet` returns `Future<SongBlock?>`. Since `showWidgetSheet` returns `Future<void>` (no result), we cannot use `showWidgetSheet` here — we need the return value. Instead, wrap the existing `showModalBottomSheet` with glass styling:

Replace:
```dart
return showModalBottomSheet<SongBlock>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _HarmonySheet(
```
with:
```dart
return showModalBottomSheet<SongBlock>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height * 0.85,
  ),
  builder: (_) => Container(
    decoration: BoxDecoration(
      color: MuzicianTheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border.all(color: MuzicianTheme.glassBorder),
    ),
    child: _HarmonySheet(
```

And add the corresponding closing `)` for the new `Container(` wrapper after the `_HarmonySheet(...)`:
```dart
    ),
  ),
);
```

- [ ] **Step 3: Verify build**

Run: `flutter analyze lib/features/songwriter/harmony_chord_sheet.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/features/songwriter/harmony_chord_sheet.dart
git commit -m "style(songwriter): glass wrapper for harmony chord sheet

Apply dark surface background and glass border to the chord picker
sheet. Cannot use showWidgetSheet because it needs to return SongBlock.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Final Verification

- [ ] **Step 1: Full analyze**

Run: `flutter analyze lib/features/songwriter/`
Expected: No issues.

- [ ] **Step 2: Run existing tests**

Run: `flutter test test/ --reporter compact`
Expected: All pass (no logic changes made).

- [ ] **Step 3: Visual verification**

Build and run in simulator. Navigate to Writer tab. Check:
- Gradient background visible
- CompactAppBar with "Writer" title and project name chip
- Glass config strip with KEY/BPM readouts and transport buttons
- Empty state when no sections
- Add-section chip in sky blue
- Section cards have glass container styling
- Value pills in teal
- Lane labels colored (violet for harmony, teal for save)
- Block tiles colored (violet harmony, teal save, red broken)
- Playhead in sky blue
- All sheets open in glass style

- [ ] **Step 4: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix(songwriter): post-verification glass retheme adjustments

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
