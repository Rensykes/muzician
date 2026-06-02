# Songwriter — Plan A: Save Grid View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a list⇄grid display toggle to `SaveBrowserPanel`, with identifying cards per save, plus a "palette" pick mode the Songwriter tab (Plan B) reuses to add blocks.

**Architecture:** Purely additive. A new preference (`AppSettings.saveBrowserGrid`) chooses the layout; a pure helper (`saveCardLabel`) derives a card's identity from the snapshot's existing `pendingChord`/`pendingScale`/`selectedNotes`; new card widgets render the grid; an optional `onPick` callback puts the panel into pick mode. No save data or music logic changes.

**Tech Stack:** Flutter, Riverpod (`NotifierProvider`), `shared_preferences`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-02-songwriter-save-grid-design.md`

> **Read before starting:** `lib/ui/save_browser_panel.dart` (esp. `_SaveBrowserPanelState.build` ~lines 448–578, and the `_FolderRow`/`_SaveRow` sub-widgets from line 581), `lib/models/save_system.dart` (`AppSettings` ~610–667, `InstrumentSnapshot` ~54–76), `lib/store/settings_store.dart`. Run `flutter test` once first to confirm a green baseline.

---

### Task 1: Add `saveBrowserGrid` preference to `AppSettings`

**Files:**
- Modify: `lib/models/save_system.dart` (`AppSettings`, ~lines 610–667)
- Test: `test/models/app_settings_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/models/app_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  test('saveBrowserGrid defaults to false and round-trips', () {
    const s = AppSettings();
    expect(s.saveBrowserGrid, false);

    final json = s.copyWith(saveBrowserGrid: true).toJson();
    final back = AppSettings.fromJson(json);
    expect(back.saveBrowserGrid, true);
  });

  test('missing saveBrowserGrid in stored json falls back to false', () {
    final back = AppSettings.fromJson(<String, dynamic>{});
    expect(back.saveBrowserGrid, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/app_settings_test.dart`
Expected: FAIL — `saveBrowserGrid` is not defined on `AppSettings`.

- [ ] **Step 3: Add the field**

In `AppSettings`, add the field, constructor default, `copyWith` param, and JSON in/out (mirror the existing `metronomeEnabled` lines exactly):

```dart
  // Render the save browser as a card grid instead of a list.
  final bool saveBrowserGrid;
```
Add to the `const AppSettings({...})` initializer list: `this.saveBrowserGrid = false,`
Add to `copyWith` params: `bool? saveBrowserGrid,` and body: `saveBrowserGrid: saveBrowserGrid ?? this.saveBrowserGrid,`
Add to `toJson`: `'saveBrowserGrid': saveBrowserGrid,`
Add to `fromJson`: `saveBrowserGrid: json['saveBrowserGrid'] as bool? ?? false,`

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/app_settings_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/save_system.dart test/models/app_settings_test.dart
git commit -m "feat(save): add saveBrowserGrid preference"
```

---

### Task 2: Add the `setSaveBrowserGrid` setter to the settings store

**Files:**
- Modify: `lib/store/settings_store.dart`
- Test: `test/store/settings_store_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/store/settings_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setSaveBrowserGrid updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setSaveBrowserGrid(true);
    expect(container.read(settingsProvider).saveBrowserGrid, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/settings_store_test.dart`
Expected: FAIL — `setSaveBrowserGrid` is not defined.

- [ ] **Step 3: Add the setter**

In `SettingsNotifier` (after `setMetronomeEnabled`):

```dart
  Future<void> setSaveBrowserGrid(bool grid) async {
    state = state.copyWith(saveBrowserGrid: grid);
    await _persist();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/settings_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/store/settings_store.dart test/store/settings_store_test.dart
git commit -m "feat(save): add setSaveBrowserGrid setter"
```

---

### Task 3: Card label resolution helper

**Files:**
- Create: `lib/ui/save_card_label.dart`
- Test: `test/ui/save_card_label_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/save_card_label_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';
import 'package:muzician/ui/save_card_label.dart';

FretboardSnapshot _snap({
  PendingChord? chord,
  PendingScale? scale,
  List<String> notes = const [],
}) => FretboardSnapshot(
      tuning: TuningName.standard,
      numFrets: 12,
      capo: 0,
      selectedCells: const [],
      selectedNotes: notes,
      viewMode: FretboardViewMode.exact,
      pendingChord: chord,
      pendingScale: scale,
    );

void main() {
  test('chord wins', () {
    final l = saveCardLabel(_snap(
      chord: const PendingChord(root: 'C', quality: 'maj7', symbol: 'Cmaj7'),
    ));
    expect(l.kind, SaveCardLabelKind.chord);
    expect(l.text, 'Cmaj7');
  });

  test('scale when no chord', () {
    final l = saveCardLabel(_snap(
      scale: const PendingScale(root: 'A', scaleName: 'Dorian'),
    ));
    expect(l.kind, SaveCardLabelKind.scale);
    expect(l.text, 'A Dorian');
  });

  test('notes when no chord/scale', () {
    final l = saveCardLabel(_snap(notes: const ['C', 'E', 'G']));
    expect(l.kind, SaveCardLabelKind.notes);
    expect(l.notes, ['C', 'E', 'G']);
  });

  test('highlight fallback when empty', () {
    final l = saveCardLabel(_snap());
    expect(l.kind, SaveCardLabelKind.highlight);
    expect(l.text, 'Highlight');
  });
}
```

> If `FretboardViewMode`/`TuningName` import paths differ, open `lib/models/fretboard.dart` and fix the import — do not change the test logic.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/save_card_label_test.dart`
Expected: FAIL — `save_card_label.dart` does not exist.

- [ ] **Step 3: Implement the helper**

```dart
// lib/ui/save_card_label.dart
import '../models/save_system.dart';

enum SaveCardLabelKind { chord, scale, notes, highlight }

class SaveCardLabel {
  final SaveCardLabelKind kind;
  final String? text;          // chord symbol, scale name, or 'Highlight'
  final List<String> notes;    // populated only for kind == notes
  const SaveCardLabel(this.kind, {this.text, this.notes = const []});
}

/// Derives a glanceable identity for a save card from data already on the
/// snapshot — no new music logic. Resolution order: chord, scale, notes,
/// then a literal "Highlight" fallback for selections with no derivable
/// chord/scale.
SaveCardLabel saveCardLabel(InstrumentSnapshot snapshot) {
  final chord = snapshot.pendingChord;
  if (chord != null) {
    return SaveCardLabel(SaveCardLabelKind.chord, text: chord.symbol);
  }
  final scale = snapshot.pendingScale;
  if (scale != null) {
    return SaveCardLabel(
      SaveCardLabelKind.scale,
      text: '${scale.root} ${scale.scaleName}',
    );
  }
  if (snapshot.selectedNotes.isNotEmpty) {
    return SaveCardLabel(
      SaveCardLabelKind.notes,
      notes: snapshot.selectedNotes,
    );
  }
  return const SaveCardLabel(SaveCardLabelKind.highlight, text: 'Highlight');
}

/// Material icon name proxy for the snapshot's instrument, used by the card.
/// Returns an [IconData] so callers stay declarative.
```

Append the instrument-icon helper in the same file:

```dart
import 'package:flutter/material.dart';

IconData saveInstrumentIcon(String instrument) {
  switch (instrument) {
    case 'piano':
      return Icons.piano;
    case 'piano_roll':
      return Icons.grid_on;
    case 'song':
      return Icons.queue_music;
    case 'songwriter':
      return Icons.library_music;
    case 'fretboard':
    default:
      return Icons.music_note;
  }
}
```

> Move the `import 'package:flutter/material.dart';` to the top of the file with the other import.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/save_card_label_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/save_card_label.dart test/ui/save_card_label_test.dart
git commit -m "feat(save): add save card label resolver"
```

---

### Task 4: Save + folder card widgets

**Files:**
- Modify: `lib/ui/save_browser_panel.dart` (add `_SaveCard`, `_FolderCard` near the other sub-widgets, after line 581)
- Test: `test/ui/save_card_widget_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/save_card_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/ui/save_browser_panel.dart' show SaveCardForTest;

void main() {
  testWidgets('save card shows name and chord label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SaveCardForTest(
          name: 'My Riff',
          instrument: 'fretboard',
          labelText: 'Cmaj7',
          noteChips: const [],
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('My Riff'), findsOneWidget);
    expect(find.text('Cmaj7'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/save_card_widget_test.dart`
Expected: FAIL — `SaveCardForTest` not exported.

- [ ] **Step 3: Implement the card widgets**

Add to `lib/ui/save_browser_panel.dart` (after the existing sub-widgets). Keep styling consistent with `_SaveRow`/`_FolderRow` (reuse their colors/text styles by reading those widgets first):

```dart
/// Grid card for a single save. Self-contained so it can be widget-tested
/// without the full panel; the panel passes resolved label/notes in.
class _SaveCard extends StatelessWidget {
  final String name;
  final String instrument;
  final String? labelText;       // chord symbol / scale / 'Highlight'
  final List<String> noteChips;  // shown when labelText is null
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SaveCard({
    required this.name,
    required this.instrument,
    required this.labelText,
    required this.noteChips,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(saveInstrumentIcon(instrument), size: 16),
              const Spacer(),
            ]),
            const SizedBox(height: 6),
            if (labelText != null)
              Text(
                labelText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              )
            else
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: noteChips
                    .take(6)
                    .map((n) => Text(n, style: theme.textTheme.bodySmall))
                    .toList(),
              ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Folder card — navigates into the folder on tap.
class _FolderCard extends StatelessWidget {
  final String name;
  final int childCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderCard({
    required this.name,
    required this.childCount,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder, size: 18),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$childCount', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Test-only re-export so the card can be widget-tested in isolation.
@visibleForTesting
Widget SaveCardForTest({
  required String name,
  required String instrument,
  required String? labelText,
  required List<String> noteChips,
  required VoidCallback onTap,
}) =>
    _SaveCard(
      name: name,
      instrument: instrument,
      labelText: labelText,
      noteChips: noteChips,
      onTap: onTap,
    );
```

> Add `import 'package:flutter/foundation.dart' show visibleForTesting;` if not already imported. Confirm `withValues` exists in the installed Flutter; if the analyzer flags it, use `.withOpacity(0.3)` instead.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/save_card_widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/save_browser_panel.dart test/ui/save_card_widget_test.dart
git commit -m "feat(save): add save and folder grid cards"
```

---

### Task 5: Mode toggle + grid body in the panel

**Files:**
- Modify: `lib/ui/save_browser_panel.dart` (`_Header` ~line 583, `build` body ~lines 510–575)
- Test: `test/ui/save_browser_grid_toggle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/save_browser_grid_toggle_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the grid toggle flips the saveBrowserGrid pref',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).hydrate();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SaveBrowserPanel(instrumentFilter: 'fretboard')),
      ),
    ));

    expect(container.read(settingsProvider).saveBrowserGrid, false);
    await tester.tap(find.byKey(const Key('saveBrowserGridToggle')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).saveBrowserGrid, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/save_browser_grid_toggle_test.dart`
Expected: FAIL — no widget with key `saveBrowserGridToggle`.

- [ ] **Step 3: Add the toggle and grid body**

In `build`, read the preference near the top:

```dart
    final gridMode = ref.watch(settingsProvider).saveBrowserGrid;
```

Pass a toggle callback + current mode into `_Header`. Add to `_Header`'s constructor `required this.gridMode` (`bool`) and `required this.onToggleGrid` (`VoidCallback`), and render an `IconButton` in the header row:

```dart
            IconButton(
              key: const Key('saveBrowserGridToggle'),
              icon: Icon(gridMode ? Icons.view_list : Icons.grid_view),
              tooltip: gridMode ? 'List view' : 'Grid view',
              onPressed: onToggleGrid,
            ),
```

Wire the callback in `build` where `_Header(...)` is constructed:

```dart
          gridMode: gridMode,
          onToggleGrid: () =>
              ref.read(settingsProvider.notifier).setSaveBrowserGrid(!gridMode),
```

Then branch the body. Keep the existing `Column` of `_FolderRow`/`_SaveRow` for list mode; add a grid branch. Replace the inner `Column(children: [...])` (lines ~514–573) with:

```dart
            child: gridMode
                ? _buildGrid(context, subFolders, saves, activeSession, notifier,
                    insideFolder)
                : _buildList(context, subFolders, saves, activeSession, notifier,
                    hasPrev, hasNext, insideFolder),
```

Extract the existing list body into a private method `_buildList(...)` returning the same `Column` you removed (move it verbatim). Add `_buildGrid`:

```dart
  Widget _buildGrid(
    BuildContext context,
    List<SaveFolder> subFolders,
    List<SaveEntry> saves,
    ActiveSession? activeSession,
    SaveSystemNotifier notifier,
    bool insideFolder,
  ) {
    final cards = <Widget>[
      ...subFolders.map((folder) => _FolderCard(
            name: folder.name,
            childCount: getChildFolders(
                    ref.read(saveSystemProvider), folder.id)
                .length,
            onTap: () => setState(() {
              _currentFolderId = folder.id;
              _selectedSaveId = null;
            }),
            onLongPress: () => _handleRenameFolder(folder),
          )),
      ...saves.map((save) {
        final label = saveCardLabel(save.snapshot);
        return _SaveCard(
          name: save.name,
          instrument: save.snapshot.instrument,
          labelText: label.kind == SaveCardLabelKind.notes ? null : label.text,
          noteChips: label.notes,
          selected: _selectedSaveId == save.id,
          onTap: () {
            if (widget.onPick != null) {
              widget.onPick!(save);
            } else if (widget.onLoad != null) {
              _handleLoad(save);
            } else {
              setState(() => _selectedSaveId = save.id);
            }
          },
          onLongPress: () => _handleRenameSave(save),
        );
      }),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.of(context).size.width < 360 ? 2 : 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.3,
      children: cards,
    );
  }
```

> Import `saveCardLabel`, `SaveCardLabelKind`, `saveInstrumentIcon` from `save_card_label.dart` at the top of the panel. Import `getChildFolders` from the rules file if not already imported (`lib/schema/rules/save_system_rules.dart`). `widget.onPick` is added in Task 6 — for this task, reference only `widget.onLoad`; add the `onPick` branch in Task 6 so this task compiles. (Use just the `onLoad`/`else` branch here.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/save_browser_grid_toggle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/save_browser_panel.dart test/ui/save_browser_grid_toggle_test.dart
git commit -m "feat(save): grid display mode + header toggle"
```

---

### Task 6: Palette pick mode (`onPick`)

**Files:**
- Modify: `lib/ui/save_browser_panel.dart` (`SaveBrowserPanel` props + tap handling in both list and grid)
- Test: `test/ui/save_browser_pick_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/save_browser_pick_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/ui/save_browser_panel.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/fretboard.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grid tap in palette mode invokes onPick, not load',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.hydrate();
    await settings.setSaveBrowserGrid(true);

    // Seed one fretboard save at root.
    final ss = container.read(saveSystemProvider.notifier);
    ss.createSave(
      'Riff',
      FretboardSnapshot(
        tuning: TuningName.standard,
        numFrets: 12,
        capo: 0,
        selectedCells: const [],
        selectedNotes: const ['C', 'E', 'G'],
        viewMode: FretboardViewMode.exact,
      ),
    );

    SaveEntry? picked;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SaveBrowserPanel(
            instrumentFilter: 'fretboard',
            onPick: (e) => picked = e,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Riff'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.name, 'Riff');
  });
}
```

> If `createSave` requires navigating into a folder first, adjust the seeding to create a folder and navigate in (read `save_system_store.dart` `createSave`). Keep the assertion identical.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/save_browser_pick_test.dart`
Expected: FAIL — `onPick` is not a parameter of `SaveBrowserPanel`.

- [ ] **Step 3: Add the `onPick` prop and wire both modes**

In `SaveBrowserPanel`:

```dart
  /// Palette mode: when set, tapping a save returns it to the caller instead
  /// of running the normal load action, and the panel host should dismiss.
  final void Function(SaveEntry entry)? onPick;
```
Add `this.onPick,` to the constructor.

In the grid `onTap` (Task 5), the `widget.onPick` branch is now valid — leave it as written.

In list mode, the `_SaveRow.onTap` currently toggles selection. When `widget.onPick != null`, call it instead:

```dart
                    onTap: () {
                      if (widget.onPick != null) {
                        widget.onPick!(save);
                        return;
                      }
                      setState(() {
                        _selectedSaveId =
                            _selectedSaveId == save.id ? null : save.id;
                      });
                    },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/save_browser_pick_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/save_browser_panel.dart test/ui/save_browser_pick_test.dart
git commit -m "feat(save): palette pick mode for save browser"
```

---

### Task 7: Full verification + viewport check

**Files:** none (verification only)

- [ ] **Step 1: Analyze**

Run: `dart format lib/ui/save_browser_panel.dart lib/ui/save_card_label.dart lib/models/save_system.dart lib/store/settings_store.dart`
Run: `flutter analyze`
Expected: no errors.

- [ ] **Step 2: Run the full affected test set**

Run: `flutter test test/models/app_settings_test.dart test/store/settings_store_test.dart test/ui/`
Expected: all PASS.

- [ ] **Step 3: Manual viewport check**

Launch the app (`flutter run`), open any instrument save panel, toggle grid mode. Confirm: cards render with icon + label + name; folders navigate; toggle persists across an app restart. Verify on one compact width (≈360 px) showing 2 columns and one wide width showing 3 columns.

- [ ] **Step 4: Commit any formatting**

```bash
git add -A
git commit -m "chore(save): format + verify grid view" --allow-empty
```

---

## Self-Review Notes

- **Spec coverage:** toggle (Task 5), card face + resolution order incl. Highlight fallback (Tasks 3–4), folder cards (Task 4), persistence (Tasks 1–2), palette mode (Task 6), viewport check (Task 7). Thumbnails intentionally excluded per spec. ✓
- **Type consistency:** `saveCardLabel` → `SaveCardLabel{kind,text,notes}`; `SaveCardLabelKind{chord,scale,notes,highlight}`; `onPick` signature identical in prop, grid, and list. ✓
- **Cross-task dependency:** Task 5 builds the grid referencing only `onLoad`; Task 6 adds the `onPick` branch. Both noted inline so tasks compile in order.
