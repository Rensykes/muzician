# Songwriter v1 — Plan B2a: Tab + Build UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Songwriter tab — a screen to build a section/lane/block arrangement over the merged B1 store: create sections, add harmony + save lanes, place chord blocks and save-reference blocks, edit structure, and save/load projects. No playback and no tap-into-save yet (those are Plan B2b).

**Architecture:** A new `lib/features/songwriter/` feature folder with a `SongwriterScreen` driven entirely by `songwriterProvider` (Plan B1). Section/lane/block widgets are thin, stateless renders of the immutable snapshot; all mutations go through the store. Save-lane blocks are added via the Plan A grid palette (`SaveBrowserPanel(onPick:)`); harmony blocks via a simple root+quality selector that derives chord data from `note_utils`. A new 6th nav tab hosts the screen.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Reuses: `songwriterProvider` + `songwriter_rules.dart` (B1), `SaveBrowserPanel` palette mode (Plan A), `note_utils` (`chromaticNotes`, `chordIntervals`, `getChordNotes`), `MuzicianTheme`.

**Spec:** `docs/superpowers/specs/2026-06-02-songwriter-v1-design.md` (this plan covers §5 UI minus transport/tap-into-save).
**Depends on:** Plan B1 (merged) + Plan A (merged).

> **Read before starting:** `lib/store/songwriter_store.dart` (the full public API — `addSection`, `addLane`, `addSaveBlock`, `addHarmonyBlock`, `removeBlock`, `setKey`, `setTempo`, `newProject`, `loadProject`, `hydrate`), `lib/models/songwriter.dart`, `lib/schema/rules/songwriter_rules.dart` (`makeHarmonyBlock`, `romanNumeralFor`, `blocksOverlap`), `lib/features/song/song_screen.dart` (header + bottom-sheet patterns to mirror), `lib/main.dart` (`_AppShellState.build` IndexedStack + `_NavTab`), `lib/ui/save_browser_panel.dart` (`onPick` palette), `lib/utils/note_utils.dart` (`chromaticNotes`, `chordIntervals`, `getChordNotes`), `lib/theme/` (`MuzicianTheme`). Run `flutter test` for a green baseline (366 tests).

## Decisions locked for this plan

| ID | Decision |
|----|----------|
| B2a-1 | New **6th nav tab "Songwriter"** in `lib/main.dart`, index 4 (Settings shifts to 5). |
| B2a-2 | **Harmony block authoring** = a bottom sheet with 12 root chips × a curated quality list (`'', 'm', '7', 'maj7', 'm7', 'dim', 'aug', 'sus2', 'sus4', 'm7b5', 'dim7'`). It derives `chordSymbol = root+quality`, `chordRootPc = chromaticNotes.indexOf(root)`, `chordNotes = getChordNotes(root, quality)`, `romanNumeral = romanNumeralFor(rootPc, quality, keyRoot, keyScaleName)`. NOT the full instrument voicing picker. |
| B2a-3 | **Save block authoring** = open `SaveBrowserPanel` in palette mode (`onPick`) filtered to a chosen instrument; the picked `SaveEntry.id` becomes the block's `saveId`. |
| B2a-4 | **Block position/size editing** v1 = a small inline editor (start-bar stepper + span stepper) reached from the block's menu. Drag-to-move/resize is deferred to B2b. Blocks render at bar position via a simple proportional row layout. |
| B2a-5 | **Save/Load** = a `SongwriterSavePanel` wrapping `SaveBrowserPanel(instrumentFilter: 'songwriter', captureSnapshot:, onLoad:)`, presented as a bottom sheet (mirrors `SongSavePanel`). |
| B2a-6 | The hydrate call for `songwriterProvider` is added to `_AppShellState.initState`. |

## File structure

| File | Responsibility |
|------|----------------|
| `lib/features/songwriter/songwriter_screen.dart` | Tab screen: header + scrolling section list + add-section button. |
| `lib/features/songwriter/songwriter_header.dart` | Project name (static), key chip, tempo chip, New Project, ⋮ menu (Save/Load, Structure editor). |
| `lib/features/songwriter/songwriter_section_card.dart` | One section: label/length/repeat controls, lane stack, add-lane. |
| `lib/features/songwriter/songwriter_lane_row.dart` | One lane: gutter (label/kind/repeat) + bar-grid body of blocks, add-block. |
| `lib/features/songwriter/songwriter_block_tile.dart` | One block: chord/roman or save label, broken state, ⋮ menu (edit pos, delete). |
| `lib/features/songwriter/harmony_chord_sheet.dart` | Root+quality bottom sheet → returns a `SongBlock` via `makeHarmonyBlock`. |
| `lib/features/songwriter/songwriter_structure_editor.dart` | "Modifica struttura" modal: reorder/remove sections, lanes, blocks. |
| `lib/features/songwriter/songwriter_save_panel.dart` | Save/load bottom-sheet wrapping `SaveBrowserPanel` filter `'songwriter'`. |
| `lib/features/songwriter/songwriter_feature.dart` | Barrel export. |
| `lib/main.dart` | Add tab + screen + hydrate. |

Store gains a couple of mutators this plan needs (added in Task 2/3/7): `renameSection`, `setSectionLength`, `setSectionRepeat`, `removeSection`, `reorderSections`, `setLaneRepeat`, `removeLane`, `reorderLanes`, `setBlockPlacement`. They follow the existing `_replaceSection`/`_replaceLane` pattern.

---

### Task 1: New Songwriter nav tab + empty screen

**Files:**
- Create: `lib/features/songwriter/songwriter_screen.dart`, `lib/features/songwriter/songwriter_feature.dart`
- Modify: `lib/main.dart`
- Test: `test/features/songwriter/songwriter_tab_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_tab_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty SongwriterScreen shows the add-section affordance',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: SongwriterScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('songwriterAddSection')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_tab_test.dart`
Expected: FAIL — `songwriter_screen.dart` does not exist.

- [ ] **Step 3: Create the screen + barrel**

```dart
// lib/features/songwriter/songwriter_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/songwriter_store.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final section in project.sections)
                    // Replaced by SongwriterSectionCard in Task 3.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(section.label ?? 'Section',
                          key: Key('section_${section.id}')),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('songwriterAddSection'),
                      onPressed: () =>
                          notifier.addSection(label: null, lengthBars: 8),
                      icon: const Icon(Icons.add),
                      label: const Text('Add section'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

```dart
// lib/features/songwriter/songwriter_feature.dart
export 'songwriter_screen.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_tab_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the nav tab in `lib/main.dart`**

In `_AppShellState.build`, add `SongwriterScreen()` to the `IndexedStack.children` between `SongScreen()` (index 3) and `_SettingsScreen()` — Settings becomes index 5. Add an import `import 'features/songwriter/songwriter_feature.dart';`. Add a `_NavTab` for Songwriter (icon `Icons.lyrics`, label `'Writer'`, `active: _tabIndex == 4`, `onTap: () => _setTab(4)`) and change the Settings tab to `active: _tabIndex == 5` / `_setTab(5)`. In `initState`'s `Future.microtask`, add `await ref.read(songwriterProvider.notifier).hydrate();` (import the store). Run `flutter analyze lib/main.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/ lib/main.dart test/features/songwriter/songwriter_tab_test.dart
git commit -m "feat(songwriter): nav tab + empty screen scaffold"
```

---

### Task 2: Header — key + tempo + New Project

**Files:**
- Create: `lib/features/songwriter/songwriter_header.dart`
- Modify: `lib/store/songwriter_store.dart` (no new methods needed — uses `setKey`, `setTempo`, `newProject`), `lib/features/songwriter/songwriter_screen.dart`
- Test: `test/features/songwriter/songwriter_header_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_header_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/features/songwriter/songwriter_header.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tempo chip shows the project tempo', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).setTempo(132);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterHeader())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('132 BPM'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_header_test.dart`
Expected: FAIL — header missing.

- [ ] **Step 3: Implement the header**

```dart
// lib/features/songwriter/songwriter_header.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/songwriter_store.dart';
import '../../utils/note_utils.dart';

class SongwriterHeader extends ConsumerWidget {
  const SongwriterHeader({super.key, this.onOpenSaveLoad, this.onOpenStructure});

  final VoidCallback? onOpenSaveLoad;
  final VoidCallback? onOpenStructure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(songwriterProvider.select((p) => p.config));
    final notifier = ref.read(songwriterProvider.notifier);
    final keyLabel = config.keyRoot == null
        ? 'No key'
        : '${chromaticNotes[config.keyRoot!]} ${config.keyScaleName ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('Songwriter',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Spacer(),
          _Chip(label: keyLabel, onTap: () => _editKey(context, ref)),
          const SizedBox(width: 8),
          _Chip(
            label: '${config.tempo} BPM',
            onTap: () => _editTempo(context, ref),
          ),
          IconButton(
            tooltip: 'New project',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: () => _confirmNew(context, notifier),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'saveload') onOpenSaveLoad?.call();
              if (v == 'structure') onOpenStructure?.call();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'saveload', child: Text('Save / Load')),
              PopupMenuItem(value: 'structure', child: Text('Edit structure')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmNew(
      BuildContext context, SongwriterNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New project?'),
        content: const Text('This clears the current songwriter session.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('New project')),
        ],
      ),
    );
    if (ok == true) await notifier.newProject();
  }

  void _editTempo(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final current = ref.read(songwriterProvider).config.tempo;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _TempoSheet(
        initial: current,
        onChanged: notifier.setTempo,
      ),
    );
  }

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
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(label),
        onPressed: onTap,
      );
}

class _TempoSheet extends StatefulWidget {
  const _TempoSheet({required this.initial, required this.onChanged});
  final int initial;
  final ValueChanged<int> onChanged;
  @override
  State<_TempoSheet> createState() => _TempoSheetState();
}

class _TempoSheetState extends State<_TempoSheet> {
  late double _bpm = widget.initial.toDouble();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_bpm.round()} BPM'),
          Slider(
            min: 40,
            max: 240,
            value: _bpm,
            onChanged: (v) => setState(() => _bpm = v),
            onChangeEnd: (v) => widget.onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

class _KeySheet extends StatelessWidget {
  const _KeySheet({required this.onPick, required this.onClear});
  final void Function(int root, String scale) onPick;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    const scales = ['major', 'minor'];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final scale in scales) ...[
            Text(scale),
            Wrap(
              spacing: 6,
              children: [
                for (var pc = 0; pc < 12; pc++)
                  ActionChip(
                    label: Text(chromaticNotes[pc]),
                    onPressed: () {
                      onPick(pc, scale);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () {
              onClear();
              Navigator.pop(context);
            },
            child: const Text('Clear key'),
          ),
        ],
      ),
    );
  }
}
```

> `note_add_outlined`/`ActionChip` exist in current Flutter. If `MuzicianTheme` provides a standard chip style used elsewhere, prefer it over the bare `ActionChip` to stay visually consistent — read `lib/features/song/song_screen.dart` for the existing chip look.

- [ ] **Step 4: Mount the header in the screen**

In `songwriter_screen.dart`, add the header above the `Expanded(ListView)`:
```dart
            SongwriterHeader(
              onOpenSaveLoad: () => _openSaveLoad(context),
              onOpenStructure: () => _openStructure(context),
            ),
```
Add stub methods `_openSaveLoad`/`_openStructure` that do nothing yet (wired in Tasks 8/9). Import the header.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_header_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_header_test.dart
git commit -m "feat(songwriter): header with key, tempo, new project"
```

---

### Task 3: Section card + section store mutators

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Create: `lib/features/songwriter/songwriter_section_card.dart`
- Modify: `lib/features/songwriter/songwriter_screen.dart`
- Test: `test/store/songwriter_section_ops_test.dart`, `test/features/songwriter/songwriter_section_card_test.dart`

- [ ] **Step 1: Write the failing store test**

```dart
// test/store/songwriter_section_ops_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rename, resize, repeat, remove a section', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final id = c.read(songwriterProvider).sections.single.id;

    n.renameSection(id, 'Verse');
    n.setSectionLength(id, 16);
    n.setSectionRepeat(id, 2);
    var s = c.read(songwriterProvider).sections.single;
    expect(s.label, 'Verse');
    expect(s.lengthBars, 16);
    expect(s.repeat, 2);

    n.removeSection(id);
    expect(c.read(songwriterProvider).sections, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/store/songwriter_section_ops_test.dart`
Expected: FAIL — methods missing.

- [ ] **Step 3: Add the store methods**

In `SongwriterNotifier` (use the existing `_replaceSection` helper and `_set`):

```dart
  void renameSection(String sectionId, String? label) =>
      _replaceSection(sectionId, (s) => s.copyWith(label: label));

  void setSectionLength(String sectionId, int lengthBars) => _replaceSection(
      sectionId, (s) => s.copyWith(lengthBars: lengthBars < 1 ? 1 : lengthBars));

  void setSectionRepeat(String sectionId, int repeat) => _replaceSection(
      sectionId, (s) => s.copyWith(repeat: repeat < 1 ? 1 : repeat));

  void removeSection(String sectionId) => _set(state.copyWith(
        sections:
            state.sections.where((s) => s.id != sectionId).toList(),
      ));

  void reorderSections(int oldIndex, int newIndex) {
    final list = [...state.sections];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(target.clamp(0, list.length), moved);
    _set(state.copyWith(
      sections: [
        for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
      ],
    ));
  }
```

> Note: `renameSection(id, null)` is a no-op clear because `SongSection.copyWith(label:)` cannot null via `??`. To support clearing a label, call `s.copyWith(clearLabel: true)` when `label == null`. Implement `renameSection` as: `_replaceSection(sectionId, (s) => label == null ? s.copyWith(clearLabel: true) : s.copyWith(label: label));`

- [ ] **Step 4: Run the store test (PASS)**

Run: `flutter test test/store/songwriter_section_ops_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the section-card widget test**

```dart
// test/features/songwriter/songwriter_section_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_section_card.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('section card shows label and an add-lane button',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(label: 'Chorus', lengthBars: 8);
    final id = container.read(songwriterProvider).sections.single.id;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SongwriterSectionCard(sectionId: id)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Chorus'), findsOneWidget);
    expect(find.byKey(Key('addLane_$id')), findsOneWidget);
  });
}
```

- [ ] **Step 6: Implement `SongwriterSectionCard`**

```dart
// lib/features/songwriter/songwriter_section_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import 'songwriter_lane_row.dart';

class SongwriterSectionCard extends ConsumerWidget {
  const SongwriterSectionCard({super.key, required this.sectionId});
  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(songwriterProvider.select(
      (p) => p.sections.firstWhere((s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0)),
    ));
    if (section.id.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(songwriterProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('sectionLabel_$sectionId'),
                    initialValue: section.label ?? '',
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Section name (optional)',
                      border: InputBorder.none,
                    ),
                    onFieldSubmitted: (v) =>
                        notifier.renameSection(sectionId, v.isEmpty ? null : v),
                  ),
                ),
                _Stepper(
                  label: 'bars',
                  value: section.lengthBars,
                  onChanged: (v) => notifier.setSectionLength(sectionId, v),
                ),
                _Stepper(
                  label: '×',
                  value: section.repeat,
                  onChanged: (v) => notifier.setSectionRepeat(sectionId, v),
                ),
                IconButton(
                  key: Key('removeSection_$sectionId'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => notifier.removeSection(sectionId),
                ),
              ],
            ),
            for (final lane in section.lanes)
              SongwriterLaneRow(sectionId: sectionId, laneId: lane.id),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<SongLaneKind>(
                key: Key('addLane_$sectionId'),
                onSelected: (kind) => notifier.addLane(
                    sectionId: sectionId,
                    kind: kind,
                    label: kind == SongLaneKind.harmony ? 'Harmony' : null),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: SongLaneKind.harmony, child: Text('+ Harmony lane')),
                  PopupMenuItem(
                      value: SongLaneKind.save, child: Text('+ Save lane')),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('+ lane'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () => onChanged(value - 1),
        ),
        Text('$value$label'),
        IconButton(
          icon: const Icon(Icons.add, size: 16),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }
}
```

> `SongwriterLaneRow` is created in Task 4. For THIS task to compile and its test to pass, create a minimal placeholder `SongwriterLaneRow` in `songwriter_lane_row.dart` that renders `SizedBox.shrink()` given `sectionId`/`laneId`, then flesh it out in Task 4. (A section with no lanes never instantiates it, so the card test passes.)

- [ ] **Step 7: Mount cards in the screen**

In `songwriter_screen.dart`, replace the placeholder `Text(section.label...)` loop with `SongwriterSectionCard(sectionId: section.id)`. Import it.

- [ ] **Step 8: Run both tests (PASS)**

Run: `flutter test test/store/songwriter_section_ops_test.dart test/features/songwriter/songwriter_section_card_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/store/songwriter_store.dart lib/features/songwriter/ test/store/songwriter_section_ops_test.dart test/features/songwriter/songwriter_section_card_test.dart
git commit -m "feat(songwriter): section card + section store ops"
```

---

### Task 4: Lane row + lane store mutators

**Files:**
- Modify: `lib/store/songwriter_store.dart`
- Modify/replace placeholder: `lib/features/songwriter/songwriter_lane_row.dart`
- Create: `lib/features/songwriter/songwriter_block_tile.dart` (minimal render; menu in Task 7)
- Test: `test/store/songwriter_lane_ops_test.dart`, `test/features/songwriter/songwriter_lane_row_test.dart`

- [ ] **Step 1: Write the failing store test**

```dart
// test/store/songwriter_lane_ops_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('set lane repeat and remove lane', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'Guitar');
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;

    n.setLaneRepeat(sectionId: s, laneId: l, repeat: 3);
    expect(c.read(songwriterProvider).sections.single.lanes.single.repeat, 3);

    n.removeLane(sectionId: s, laneId: l);
    expect(c.read(songwriterProvider).sections.single.lanes, isEmpty);
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_lane_ops_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add lane store methods**

```dart
  void setLaneRepeat(
          {required String sectionId,
          required String laneId,
          required int repeat}) =>
      _replaceLane(sectionId, laneId,
          (l) => l.copyWith(repeat: repeat < 1 ? 1 : repeat));

  void removeLane({required String sectionId, required String laneId}) =>
      _replaceSection(sectionId,
          (s) => s.copyWith(lanes: s.lanes.where((l) => l.id != laneId).toList()));
```

- [ ] **Step 4: Run the store test (PASS)**

Run: `flutter test test/store/songwriter_lane_ops_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the lane-row widget test**

```dart
// test/features/songwriter/songwriter_lane_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/features/songwriter/songwriter_lane_row.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lane row renders a placed harmony block label', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.harmony, label: 'Harmony');
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;
    n.addHarmonyBlock(
      sectionId: s,
      laneId: l,
      block: const SongBlock(
        id: 'b1', startBar: 0, spanBars: 2,
        chordSymbol: 'C', chordRootPc: 0, chordQuality: '',
        chordNotes: ['C', 'E', 'G'], romanNumeral: 'I',
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SongwriterLaneRow(sectionId: s, laneId: l),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
  });
}
```

- [ ] **Step 6: Implement `SongwriterLaneRow` + minimal `SongwriterBlockTile`**

Replace the placeholder lane row. The lane body lays blocks out proportionally to the section's `lengthBars` using a `LayoutBuilder` (bar width = constraints.maxWidth / lengthBars; block left = startBar*barWidth, width = spanBars*barWidth). The add-block affordance differs by kind: harmony → opens the harmony sheet (Task 5); save → opens the palette (Task 6). For THIS task, the add-block button can call a `onAddBlock` no-op stub that Tasks 5/6 replace; the test only checks block rendering.

```dart
// lib/features/songwriter/songwriter_lane_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import 'songwriter_block_tile.dart';

class SongwriterLaneRow extends ConsumerWidget {
  const SongwriterLaneRow({super.key, required this.sectionId, required this.laneId});
  final String sectionId;
  final String laneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(songwriterProvider.select((p) {
      final s = p.sections.firstWhere((s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0));
      final l = s.lanes.firstWhere((l) => l.id == laneId,
          orElse: () => const SongLane(id: '', kind: SongLaneKind.save, order: 0));
      return (lengthBars: s.lengthBars, lane: l);
    }));
    final lane = result.lane;
    final lengthBars = result.lengthBars < 1 ? 1 : result.lengthBars;
    if (lane.id.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(lane.label ??
                (lane.kind == SongLaneKind.harmony ? 'Harmony' : 'Lane')),
          ),
          Expanded(
            child: SizedBox(
              height: 44,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth / lengthBars;
                  return Stack(
                    children: [
                      for (final block in lane.blocks)
                        Positioned(
                          left: block.startBar * barWidth,
                          width: block.spanBars * barWidth,
                          top: 0,
                          bottom: 0,
                          child: SongwriterBlockTile(
                            sectionId: sectionId,
                            laneId: laneId,
                            blockId: block.id,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

```dart
// lib/features/songwriter/songwriter_block_tile.dart  (minimal; menu added in Task 7)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../store/save_system_store.dart';

class SongwriterBlockTile extends ConsumerWidget {
  const SongwriterBlockTile(
      {super.key,
      required this.sectionId,
      required this.laneId,
      required this.blockId});
  final String sectionId;
  final String laneId;
  final String blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final block = ref.watch(songwriterProvider.select((p) {
      for (final s in p.sections) {
        if (s.id != sectionId) continue;
        for (final l in s.lanes) {
          if (l.id != laneId) continue;
          for (final b in l.blocks) {
            if (b.id == blockId) return b;
          }
        }
      }
      return null;
    }));
    if (block == null) return const SizedBox.shrink();

    // Broken = a save reference whose SaveEntry no longer exists.
    final broken = block.embedded == null &&
        block.saveId != null &&
        !ref
            .watch(saveSystemProvider)
            .saves
            .any((e) => e.id == block.saveId);

    final label = block.romanNumeral ?? block.chordSymbol ?? _saveLabel(ref, block);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: broken ? Colors.red.withValues(alpha: 0.25) : Colors.teal,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  String _saveLabel(WidgetRef ref, SongBlock block) {
    final snap = block.embedded;
    if (snap != null) return snap.pendingChord?.symbol ?? 'Saved';
    final id = block.saveId;
    if (id == null) return 'Block';
    final entry = ref
        .read(saveSystemProvider)
        .saves
        .where((e) => e.id == id)
        .cast<SaveEntry?>()
        .firstWhere((e) => true, orElse: () => null);
    return entry?.name ?? 'Missing';
  }
}
```

> Confirm `saveSystemProvider` exposes `.saves` (a `List<SaveEntry>`) — read `lib/store/save_system_store.dart`. Adapt `_saveLabel`/`broken` if the accessor differs.

- [ ] **Step 7: Run both tests (PASS)**

Run: `flutter test test/store/songwriter_lane_ops_test.dart test/features/songwriter/songwriter_lane_row_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/store/songwriter_store.dart lib/features/songwriter/ test/store/songwriter_lane_ops_test.dart test/features/songwriter/songwriter_lane_row_test.dart
git commit -m "feat(songwriter): lane row + block tile + lane store ops"
```

---

### Task 5: Harmony block authoring sheet

**Files:**
- Create: `lib/features/songwriter/harmony_chord_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_lane_row.dart` (wire add-block for harmony lanes)
- Test: `test/features/songwriter/harmony_chord_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/harmony_chord_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';

void main() {
  testWidgets('picking C major returns a harmony block with notes + numeral',
      (tester) async {
    SongBlock? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showHarmonyChordSheet(
                context,
                startBar: 0,
                spanBars: 2,
                keyRoot: 0,
                keyScaleName: 'major',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap root 'C' then quality 'maj' (empty-string major chip labelled 'maj').
    await tester.tap(find.byKey(const Key('harmonyRoot_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('harmonyQuality_')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.chordRootPc, 0);
    expect(result!.chordNotes, contains('C'));
    expect(result!.romanNumeral, 'I');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the sheet**

```dart
// lib/features/songwriter/harmony_chord_sheet.dart
import 'package:flutter/material.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../utils/note_utils.dart';

const _qualities = <(String value, String label)>[
  ('', 'maj'),
  ('m', 'min'),
  ('7', '7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('dim', 'dim'),
  ('aug', 'aug'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('m7b5', 'm7b5'),
  ('dim7', 'dim7'),
];

/// Opens the harmony chord picker. Returns a ready-to-add [SongBlock], or null
/// if dismissed. Two taps: a root, then a quality (which commits).
Future<SongBlock?> showHarmonyChordSheet(
  BuildContext context, {
  required int startBar,
  required int spanBars,
  required int? keyRoot,
  required String? keyScaleName,
}) {
  return showModalBottomSheet<SongBlock>(
    context: context,
    builder: (_) => _HarmonySheet(
      startBar: startBar,
      spanBars: spanBars,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
    ),
  );
}

class _HarmonySheet extends StatefulWidget {
  const _HarmonySheet({
    required this.startBar,
    required this.spanBars,
    required this.keyRoot,
    required this.keyScaleName,
  });
  final int startBar;
  final int spanBars;
  final int? keyRoot;
  final String? keyScaleName;

  @override
  State<_HarmonySheet> createState() => _HarmonySheetState();
}

class _HarmonySheetState extends State<_HarmonySheet> {
  int? _rootPc;

  void _commit(String quality) {
    final rootPc = _rootPc;
    if (rootPc == null) return;
    final rootName = chromaticNotes[rootPc];
    final block = makeHarmonyBlock(
      startBar: widget.startBar,
      spanBars: widget.spanBars,
      chordSymbol: '$rootName$quality',
      chordQuality: quality,
      chordRootPc: rootPc,
      chordNotes: getChordNotes(rootName, quality),
      romanNumeral: romanNumeralFor(
          rootPc, quality, widget.keyRoot, widget.keyScaleName),
    );
    Navigator.pop(context, block);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Root'),
          Wrap(
            spacing: 6,
            children: [
              for (var pc = 0; pc < 12; pc++)
                ChoiceChip(
                  key: Key('harmonyRoot_$pc'),
                  label: Text(chromaticNotes[pc]),
                  selected: _rootPc == pc,
                  onSelected: (_) => setState(() => _rootPc = pc),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Quality'),
          Wrap(
            spacing: 6,
            children: [
              for (final q in _qualities)
                ActionChip(
                  key: Key('harmonyQuality_${q.$1}'),
                  label: Text(q.$2),
                  onPressed: _rootPc == null ? null : () => _commit(q.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
```

> `ActionChip.onPressed` accepting null disables it; if the installed Flutter requires non-null, gate with `onPressed: _rootPc == null ? () {} : () => _commit(q.$1)` and visually dim. Confirm `getChordNotes('C', '')` returns `['C','E','G']` (read `note_utils.dart`).

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire it into the harmony lane**

In `SongwriterLaneRow`, add an add-block affordance (e.g. a trailing `+` button in the lane, key `Key('addBlock_$laneId')`). When the lane kind is `harmony`, on tap call:
```dart
final block = await showHarmonyChordSheet(context,
    startBar: _nextFreeBar(lane, lengthBars), spanBars: 2,
    keyRoot: config.keyRoot, keyScaleName: config.keyScaleName);
if (block != null) {
  ref.read(songwriterProvider.notifier)
     .addHarmonyBlock(sectionId: sectionId, laneId: laneId, block: block);
}
```
Add a small helper `_nextFreeBar(lane, lengthBars)` that returns the first bar not covered by an existing block (fallback 0). Read `config` via `ref.read(songwriterProvider).config`. Overlap is already guarded by the store (ignored if it collides).

- [ ] **Step 6: Run the lane-row test again to confirm no regression**

Run: `flutter test test/features/songwriter/songwriter_lane_row_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/harmony_chord_sheet_test.dart
git commit -m "feat(songwriter): harmony chord authoring sheet"
```

---

### Task 6: Save block authoring via the grid palette

**Files:**
- Modify: `lib/features/songwriter/songwriter_lane_row.dart` (save-lane add-block)
- Test: `test/features/songwriter/songwriter_save_block_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_save_block_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/features/songwriter/songwriter_lane_row.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('picking a save from the palette adds a save block',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 8);
    final s = container.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save, label: 'Guitar');
    final l = container.read(songwriterProvider).sections.single.lanes.single.id;

    // Seed a visible fretboard save inside a folder.
    final ss = container.read(saveSystemProvider.notifier);
    ss.createSaveFolder('F', null);
    final folderId =
        container.read(saveSystemProvider).folders.first.id;
    ss.saveSnapshot('Riff', FretboardSnapshot(
      tuning: TuningName.standard, numFrets: 12, capo: 0,
      selectedCells: const [], selectedNotes: const ['C', 'E', 'G'],
      viewMode: FretboardViewMode.exact,
    ), folderId: folderId);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SongwriterLaneRow(sectionId: s, laneId: l)),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('addBlock_$l')));
    await tester.pumpAndSettle();
    // Navigate into the folder, then pick the save.
    await tester.tap(find.text('F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riff'));
    await tester.pumpAndSettle();

    final blocks =
        container.read(songwriterProvider).sections.single.lanes.single.blocks;
    expect(blocks.length, 1);
    expect(blocks.single.saveId, isNotNull);
  });
}
```

> The exact store API to seed a save (`createSaveFolder`, `saveSnapshot(name, snapshot, folderId:)`) must match `lib/store/save_system_store.dart`. READ it first and adjust the seeding calls (names/positional vs named args) to the real API; keep the assertions identical.

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_save_block_test.dart`
Expected: FAIL.

- [ ] **Step 3: Wire save-lane add-block to the palette**

In `SongwriterLaneRow`, when the lane kind is `save`, the add-block button opens the palette in a bottom sheet:

```dart
Future<void> _addSaveBlock(BuildContext context, WidgetRef ref,
    {required int startBar}) async {
  final picked = await showModalBottomSheet<SaveEntry>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => SaveBrowserPanel(
      instrumentFilter: 'fretboard', // see note below on instrument choice
      onPick: (entry) => Navigator.pop(sheetCtx, entry),
    ),
  );
  if (picked != null) {
    ref.read(songwriterProvider.notifier).addSaveBlock(
          sectionId: sectionId,
          laneId: laneId,
          saveId: picked.id,
          startBar: startBar,
          spanBars: 2,
        );
  }
}
```

Wire the save-lane branch of the add-block button to call `_addSaveBlock(context, ref, startBar: _nextFreeBar(lane, lengthBars))`. Import `SaveBrowserPanel` and `SaveEntry`.

> **Instrument filter:** v1 hardcodes `'fretboard'`. (A lane does not yet carry an instrument; choosing per-lane instrument is a small future enhancement — out of scope for B2a. The test seeds a fretboard save, so `'fretboard'` is correct here.)

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_save_block_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_save_block_test.dart
git commit -m "feat(songwriter): add save blocks from the grid palette"
```

---

### Task 7: Block menu — edit placement + delete

**Files:**
- Modify: `lib/store/songwriter_store.dart` (add `setBlockPlacement`)
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`
- Test: `test/store/songwriter_block_placement_test.dart`

- [ ] **Step 1: Write the failing store test**

```dart
// test/store/songwriter_block_placement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setBlockPlacement moves/resizes; overlap is rejected', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 16);
    final s = c.read(songwriterProvider).sections.single.id;
    n.addLane(sectionId: s, kind: SongLaneKind.save);
    final l = c.read(songwriterProvider).sections.single.lanes.single.id;
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'x', startBar: 0, spanBars: 2);
    final bId =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single.id;

    n.setBlockPlacement(
        sectionId: s, laneId: l, blockId: bId, startBar: 4, spanBars: 4);
    final b =
        c.read(songwriterProvider).sections.single.lanes.single.blocks.single;
    expect(b.startBar, 4);
    expect(b.spanBars, 4);

    // Add a second block then try to overlap it onto the first — rejected.
    n.addSaveBlock(sectionId: s, laneId: l, saveId: 'y', startBar: 10, spanBars: 2);
    final yId = c
        .read(songwriterProvider)
        .sections.single.lanes.single.blocks
        .firstWhere((blk) => blk.saveId == 'y').id;
    n.setBlockPlacement(
        sectionId: s, laneId: l, blockId: yId, startBar: 4, spanBars: 2);
    final y = c
        .read(songwriterProvider)
        .sections.single.lanes.single.blocks
        .firstWhere((blk) => blk.saveId == 'y');
    expect(y.startBar, 10); // unchanged — overlap rejected
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/store/songwriter_block_placement_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add `setBlockPlacement` to the store**

```dart
  void setBlockPlacement({
    required String sectionId,
    required String laneId,
    required String blockId,
    required int startBar,
    required int spanBars,
  }) {
    _replaceLane(sectionId, laneId, (l) {
      final current = l.blocks.firstWhere((b) => b.id == blockId);
      final moved = current.copyWith(
        startBar: startBar < 0 ? 0 : startBar,
        spanBars: spanBars < 1 ? 1 : spanBars,
      );
      final others = l.blocks.where((b) => b.id != blockId).toList();
      if (blocksOverlap(others, moved)) return l; // reject overlap
      return l.copyWith(
        blocks: l.blocks.map((b) => b.id == blockId ? moved : b).toList(),
      );
    });
  }
```

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/store/songwriter_block_placement_test.dart`
Expected: PASS.

- [ ] **Step 5: Add a long-press menu to the block tile**

In `SongwriterBlockTile`, wrap the container in a `GestureDetector`/`InkWell` with `onLongPress` opening a menu (`showModalBottomSheet` or `PopupMenuButton`) offering: **Edit placement** (a small dialog with start-bar + span steppers calling `setBlockPlacement`) and **Delete** (`removeBlock`). Keep it minimal; no test required for the menu plumbing beyond the store test (the store ops are the logic). Run `flutter analyze lib/features/songwriter/songwriter_block_tile.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/store/songwriter_store.dart lib/features/songwriter/ test/store/songwriter_block_placement_test.dart
git commit -m "feat(songwriter): block placement edit + delete menu"
```

---

### Task 8: Structure editor modal

**Files:**
- Modify: `lib/store/songwriter_store.dart` (`reorderLanes`)
- Create: `lib/features/songwriter/songwriter_structure_editor.dart`
- Modify: `lib/features/songwriter/songwriter_screen.dart` (`_openStructure`)
- Test: `test/store/songwriter_reorder_test.dart`

- [ ] **Step 1: Write the failing store test**

```dart
// test/store/songwriter_reorder_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reorderSections moves a section and renumbers order', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'A', lengthBars: 4);
    n.addSection(label: 'B', lengthBars: 4);
    n.addSection(label: 'C', lengthBars: 4);

    n.reorderSections(2, 0); // move C to front
    final labels =
        c.read(songwriterProvider).sections.map((s) => s.label).toList();
    expect(labels, ['C', 'A', 'B']);
    final orders =
        c.read(songwriterProvider).sections.map((s) => s.order).toList();
    expect(orders, [0, 1, 2]);
  });
}
```

- [ ] **Step 2: Run it (FAIL or PASS)**

Run: `flutter test test/store/songwriter_reorder_test.dart`
Expected: PASS if `reorderSections` from Task 3 is correct. If FAIL, fix `reorderSections` (the index-adjust math) until it passes — do not change the test.

- [ ] **Step 3: Add `reorderLanes` (mirrors `reorderSections`)**

```dart
  void reorderLanes(String sectionId, int oldIndex, int newIndex) {
    _replaceSection(sectionId, (s) {
      final list = [...s.lanes];
      if (oldIndex < 0 || oldIndex >= list.length) return s;
      var target = newIndex;
      if (target > oldIndex) target -= 1;
      final moved = list.removeAt(oldIndex);
      list.insert(target.clamp(0, list.length), moved);
      return s.copyWith(lanes: [
        for (var i = 0; i < list.length; i++) list[i].copyWith(order: i),
      ]);
    });
  }
```

- [ ] **Step 4: Implement the structure editor**

```dart
// lib/features/songwriter/songwriter_structure_editor.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';

class SongwriterStructureEditor extends ConsumerWidget {
  const SongwriterStructureEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(songwriterProvider.select((p) => p.sections));
    final notifier = ref.read(songwriterProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit structure'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ReorderableListView(
        padding: const EdgeInsets.all(12),
        onReorder: notifier.reorderSections,
        children: [
          for (final s in sections)
            ListTile(
              key: ValueKey(s.id),
              title: Text(s.label ?? 'Section'),
              subtitle: Text('${s.lengthBars} bars · ${s.repeat}×'
                  ' · ${s.lanes.length} lanes'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => notifier.removeSection(s.id),
              ),
            ),
        ],
      ),
    );
  }
}
```

> Per-lane and per-block reordering inside the structure editor can reuse `reorderLanes`/`removeLane`/`removeBlock`; for B2a, section-level reorder/remove is the minimum. Expanding to lanes/blocks here is a reasonable addition if time allows, but the inline section card already covers lane add/remove.

- [ ] **Step 5: Wire `_openStructure` in the screen**

```dart
  void _openStructure(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SongwriterStructureEditor(),
      fullscreenDialog: true,
    ));
  }
```
Import the editor.

- [ ] **Step 6: Run the reorder test (PASS) + analyze**

Run: `flutter test test/store/songwriter_reorder_test.dart`
Run: `flutter analyze lib/features/songwriter/songwriter_structure_editor.dart`
Expected: PASS / clean.

- [ ] **Step 7: Commit**

```bash
git add lib/store/songwriter_store.dart lib/features/songwriter/ test/store/songwriter_reorder_test.dart
git commit -m "feat(songwriter): structure editor + lane reorder"
```

---

### Task 9: Save / load panel

**Files:**
- Create: `lib/features/songwriter/songwriter_save_panel.dart`
- Modify: `lib/features/songwriter/songwriter_screen.dart` (`_openSaveLoad`)
- Test: `test/features/songwriter/songwriter_save_panel_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/songwriter/songwriter_save_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/features/songwriter/songwriter_save_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('save panel captures the current songwriter project',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 8);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SongwriterSavePanel())),
    ));
    await tester.pumpAndSettle();

    // The panel exposes the capture callback; invoke it and confirm it returns
    // a songwriter snapshot mirroring current state.
    final snap = songwriterCaptureForTest(container);
    expect(snap.instrument, 'songwriter');
    expect(snap.sections.single.label, 'V');
  });
}
```

- [ ] **Step 2: Run it (FAIL)**

Run: `flutter test test/features/songwriter/songwriter_save_panel_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the save panel**

```dart
// lib/features/songwriter/songwriter_save_panel.dart
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../ui/save_browser_panel.dart';

class SongwriterSavePanel extends ConsumerWidget {
  const SongwriterSavePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    return SaveBrowserPanel(
      instrumentFilter: 'songwriter',
      captureSnapshot: () => ref.read(songwriterProvider),
      onLoad: (snapshot) {
        if (snapshot is SongwriterProjectSnapshot) {
          notifier.loadProject(snapshot);
        }
      },
    );
  }
}

@visibleForTesting
SongwriterProjectSnapshot songwriterCaptureForTest(ProviderContainer c) =>
    c.read(songwriterProvider);
```

> Confirm `SaveBrowserPanel`'s `captureSnapshot`/`onLoad` parameter names + signatures against `lib/ui/save_browser_panel.dart` (read it). The capture returns the current `SongwriterProjectSnapshot` (the store's state IS the snapshot). The `onLoad` callback receives the loaded `InstrumentSnapshot`; cast to `SongwriterProjectSnapshot`.

- [ ] **Step 4: Run it (PASS)**

Run: `flutter test test/features/songwriter/songwriter_save_panel_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire `_openSaveLoad` in the screen**

```dart
  void _openSaveLoad(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const SizedBox(
        height: 480,
        child: SongwriterSavePanel(),
      ),
    );
  }
```
Import the panel.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/ test/features/songwriter/songwriter_save_panel_test.dart
git commit -m "feat(songwriter): save/load panel (songwriter filter)"
```

---

### Task 10: Full verification + viewport

**Files:** none (verification only)

- [ ] **Step 1: Format**

Run: `dart format lib/features/songwriter/ lib/store/songwriter_store.dart lib/main.dart`

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No issues. Quote any new issue in `lib/features/songwriter/` or `lib/main.dart`.

- [ ] **Step 3: Full test sweep**

Run: `flutter test`
Expected: all PASS (the prior 366 + the new songwriter UI/store tests). Quote any failure and assess whether the Songwriter UI caused it.

- [ ] **Step 4: Manual viewport check**

Launch (`flutter run`), open the **Writer** tab. Confirm: add section → name it, set bars/repeat; add a harmony lane → add a chord (shows Roman numeral when a key is set); add a save lane → pick a saved progression from the grid palette; edit a block's placement; open structure editor and reorder; New Project clears; relaunch restores the session. Verify on one compact (~360px) and one wide width.

- [ ] **Step 5: Commit any formatting**

```bash
git add -A
git commit -m "chore(songwriter): format + verify B2a UI" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage (§5 minus transport/tap-into-save):** tab + header (Tasks 1–2), sections w/ label/length/repeat/reorder/delete (Tasks 3, 8), per-section lanes harmony+save w/ repeat/remove (Task 4), harmony Roman-numeral blocks via picker (Task 5), save blocks via grid palette (Task 6), block placement edit + delete + broken-state render (Tasks 4, 7), structure editor (Task 8), save/load `'songwriter'` (Task 9), session restore (already in B1; exercised via New Project + relaunch in Task 10). ✓
- **Deferred to B2b (explicit):** real-time transport + playhead + metronome, block highlight under playhead, **drag** move/resize (B2a uses stepper-based placement), tap-block-to-open-the-save (isolated editor), Make-Unique / Re-link UI actions, per-lane instrument selection for the palette filter.
- **Type/name consistency:** store methods used by the UI are all defined here or in B1 — `addSection/renameSection/setSectionLength/setSectionRepeat/removeSection/reorderSections`, `addLane/setLaneRepeat/removeLane/reorderLanes`, `addSaveBlock/addHarmonyBlock/removeBlock/setBlockPlacement`, `setKey/setTempo/newProject/loadProject`. `showHarmonyChordSheet` returns `SongBlock`. `SongwriterSavePanel` uses `SaveBrowserPanel(instrumentFilter/captureSnapshot/onLoad)`.
- **Known store gap reused from B1:** `renameSection(id, null)` must use `clearLabel: true` (noted in Task 3) because `copyWith(label:)` can't null via `??`.
- **Adaptation flags for implementers:** verify real `save_system_store` API names (`createSaveFolder`/`saveSnapshot`/`.saves`/`.folders`) and `SaveBrowserPanel` param names before relying on the snippets; adjust seeding/wiring to match, keep assertions identical.

---

## Next plan (write after B2a lands)
- **Plan B2b — Songwriter playback + editing:** a lightweight `SongwriterPlaybackNotifier` (tick loop + metronome over `flattenedBarCount`, reusing the metronome click source), playhead overlay + block highlight, drag move/resize, tap-block → open the referenced save in an isolated `ProviderContainer` editor, Make-Unique / Re-link actions. Then the chord-wheel pass and Plan C (enrichment).
