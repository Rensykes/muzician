# Writer Unsaved-State Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an unsaved indicator in Writer and let the user save by overwriting the bound named save or creating a new one, with a per-project "always overwrite" option.

**Architecture:** A per-project binding store (`projectId → {activeSaveId, alwaysOverwrite}`) records which `SaveEntry` the live Writer project is bound to. A derived `writerDirtyProvider` compares the live snapshot JSON against the bound save's snapshot JSON. The header shows an "Unsaved" badge + a Save button; saving a bound project prompts Overwrite / Save-as-new (with a "don't ask again" checkbox), while first-save / save-as-new reuse the existing Save/Load panel.

**Tech Stack:** Flutter, Riverpod (`Notifier`/`Provider`), SharedPreferences, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-22-writer-unsaved-feedback-design.md`

---

## File Structure

- **Create** `lib/store/writer_save_binding_store.dart` — `WriterSaveBinding` model, `WriterSaveBindingNotifier` + provider, `writerDirtyProvider`.
- **Create** `lib/features/songwriter/writer_save_choice_dialog.dart` — overwrite/save-as-new dialog.
- **Modify** `lib/ui/save_browser_panel.dart` — optional `onSaved` / `onLoadSaveId` callbacks.
- **Modify** `lib/features/songwriter/songwriter_save_panel.dart` — bind on load/save.
- **Modify** `lib/features/songwriter/songwriter_header.dart` — Unsaved badge + Save button + overflow Save tile.
- **Modify** `lib/features/songwriter/songwriter_screen_sheet.dart` — `_saveProject` flow, wire `onSave`.
- **Modify** `lib/store/songwriter_store.dart` — clear binding in `newProject`.
- **Modify** `lib/main.dart` — hydrate binding store.
- **Create** tests under `test/store/` and `test/features/songwriter/`.

---

## Task 1: Binding store + dirty provider

**Files:**
- Create: `lib/store/writer_save_binding_store.dart`
- Test: `test/store/writer_save_binding_store_test.dart`

- [ ] **Step 1: Write the failing store test**

Create `test/store/writer_save_binding_store_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = '@muzician/writer_save_bindings/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('bind sets activeSaveId and resets alwaysOverwrite', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.setAlwaysOverwrite('p', true);
    n.bind('p', 'save1');
    final b = c.read(writerSaveBindingProvider)['p']!;
    expect(b.activeSaveId, 'save1');
    expect(b.alwaysOverwrite, false);
  });

  test('setAlwaysOverwrite keeps activeSaveId', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.bind('p', 'save1');
    n.setAlwaysOverwrite('p', true);
    final b = c.read(writerSaveBindingProvider)['p']!;
    expect(b.activeSaveId, 'save1');
    expect(b.alwaysOverwrite, true);
  });

  test('clear removes binding', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(writerSaveBindingProvider.notifier);
    n.bind('p', 'save1');
    n.clear('p');
    expect(c.read(writerSaveBindingProvider)['p'], isNull);
  });

  test('persist + rehydrate round-trip', () async {
    var c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(writerSaveBindingProvider.notifier).bind('p', 'save1');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect((await SharedPreferences.getInstance()).getString(_key), isNotNull);
    c.dispose();
    c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(writerSaveBindingProvider.notifier).hydrate();
    expect(c.read(writerSaveBindingProvider)['p']?.activeSaveId, 'save1');
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/store/writer_save_binding_store_test.dart`
Expected: FAIL — `writer_save_binding_store.dart` does not exist / `writerSaveBindingProvider` undefined.

- [ ] **Step 3: Create the store (model + notifier + provider + dirty provider)**

Create `lib/store/writer_save_binding_store.dart`:

```dart
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/save_system.dart';
import 'save_system_store.dart';
import 'songwriter_store.dart';

const _kWriterBindingsKey = '@muzician/writer_save_bindings/v1';
const _kDebounce = Duration(milliseconds: 500);

/// Per-project link between the live Writer project and a named [SaveEntry].
class WriterSaveBinding {
  final String? activeSaveId;
  final bool alwaysOverwrite;
  const WriterSaveBinding({this.activeSaveId, this.alwaysOverwrite = false});

  WriterSaveBinding copyWith({String? activeSaveId, bool? alwaysOverwrite}) =>
      WriterSaveBinding(
        activeSaveId: activeSaveId ?? this.activeSaveId,
        alwaysOverwrite: alwaysOverwrite ?? this.alwaysOverwrite,
      );

  Map<String, dynamic> toJson() => {
        'activeSaveId': activeSaveId,
        'alwaysOverwrite': alwaysOverwrite,
      };

  factory WriterSaveBinding.fromJson(Map<String, dynamic> json) =>
      WriterSaveBinding(
        activeSaveId: json['activeSaveId'] as String?,
        alwaysOverwrite: json['alwaysOverwrite'] as bool? ?? false,
      );
}

class WriterSaveBindingNotifier
    extends Notifier<Map<String, WriterSaveBinding>> {
  Timer? _debounce;
  bool _hydrated = false;

  @override
  Map<String, WriterSaveBinding> build() {
    ref.onDispose(() => _debounce?.cancel());
    return const {};
  }

  Future<void> hydrate() async {
    if (_hydrated) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kWriterBindingsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        state = map.map(
          (k, v) => MapEntry(
            k,
            WriterSaveBinding.fromJson(v as Map<String, dynamic>),
          ),
        );
      } catch (_) {
        await prefs.remove(_kWriterBindingsKey);
      }
    }
    _hydrated = true;
  }

  /// Binds [projectId] to [saveId] and RESETS alwaysOverwrite. Called on load
  /// and on save (new or save-as-new).
  void bind(String projectId, String saveId) {
    state = {...state, projectId: WriterSaveBinding(activeSaveId: saveId)};
    _schedulePersist();
  }

  void setAlwaysOverwrite(String projectId, bool value) {
    final cur = state[projectId] ?? const WriterSaveBinding();
    state = {...state, projectId: cur.copyWith(alwaysOverwrite: value)};
    _schedulePersist();
  }

  void clear(String projectId) {
    final next = {...state}..remove(projectId);
    state = next;
    _schedulePersist();
  }

  void _schedulePersist() {
    _debounce?.cancel();
    final snapshot = state;
    _debounce = Timer(_kDebounce, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kWriterBindingsKey,
        jsonEncode(snapshot.map((k, v) => MapEntry(k, v.toJson()))),
      );
    });
  }
}

final writerSaveBindingProvider =
    NotifierProvider<WriterSaveBindingNotifier, Map<String, WriterSaveBinding>>(
        WriterSaveBindingNotifier.new);

/// True when the live Writer project differs from the named save it is bound
/// to. When unbound (or the bound save is missing), dirty when it has content.
final writerDirtyProvider = Provider<bool>((ref) {
  final projectId =
      ref.watch(saveSystemProvider.select((s) => s.selectedProjectId));
  if (projectId == null) return false;
  final project = ref.watch(songwriterProvider);
  final binding = ref.watch(writerSaveBindingProvider)[projectId];
  final saves = ref.watch(saveSystemProvider.select((s) => s.saves));
  final id = binding?.activeSaveId;
  SaveEntry? entry;
  if (id != null) {
    for (final s in saves) {
      if (s.id == id) {
        entry = s;
        break;
      }
    }
  }
  if (entry == null) {
    return project.sections.isNotEmpty || project.drumPatterns.isNotEmpty;
  }
  return jsonEncode(project.toJson()) != jsonEncode(entry.snapshot.toJson());
});
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/store/writer_save_binding_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/store/writer_save_binding_store.dart test/store/writer_save_binding_store_test.dart
git commit -m "feat(writer): add per-project save binding store + dirty provider"
```

---

## Task 2: Dirty provider behavior tests

**Files:**
- Test: `test/store/writer_dirty_test.dart`

- [ ] **Step 1: Write the dirty test**

Create `test/store/writer_dirty_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ProviderContainer seeded() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    return c;
  }

  String pid(ProviderContainer c) =>
      c.read(saveSystemProvider).selectedProjectId!;

  test('unbound empty project is not dirty', () {
    final c = seeded();
    expect(c.read(writerDirtyProvider), false);
  });

  test('unbound project with content is dirty', () {
    final c = seeded();
    c.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    expect(c.read(writerDirtyProvider), true);
  });

  test('bound and unchanged is not dirty', () {
    final c = seeded();
    c.read(songwriterProvider.notifier).addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    expect(c.read(writerDirtyProvider), false);
  });

  test('bound then edited is dirty', () {
    final c = seeded();
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    n.setTempo(200);
    expect(c.read(writerDirtyProvider), true);
  });

  test('bound but save deleted falls back to content check', () {
    final c = seeded();
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = c
        .read(saveSystemProvider.notifier)
        .saveSnapshot('s1', pid(c), c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid(c), saveId);
    c.read(saveSystemProvider.notifier).deleteSave(saveId);
    expect(c.read(writerDirtyProvider), true);
  });
}
```

- [ ] **Step 2: Run test, verify it passes**

Run: `flutter test test/store/writer_dirty_test.dart`
Expected: PASS (5 tests). No implementation needed — `writerDirtyProvider` was built in Task 1. If any case fails, fix the dirty logic in `writer_save_binding_store.dart` before continuing.

- [ ] **Step 3: Commit**

```bash
git add test/store/writer_dirty_test.dart
git commit -m "test(writer): cover writerDirtyProvider bound/unbound cases"
```

---

## Task 3: Save-choice dialog

**Files:**
- Create: `lib/features/songwriter/writer_save_choice_dialog.dart`
- Test: `test/features/songwriter/writer_save_choice_dialog_test.dart`

- [ ] **Step 1: Write the failing dialog test**

Create `test/features/songwriter/writer_save_choice_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/writer_save_choice_dialog.dart';

void main() {
  testWidgets('returns overwrite with dontAskAgain when checkbox + overwrite',
      (tester) async {
    WriterSaveChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result =
                  await showWriterSaveChoiceDialog(context, saveName: 'X'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAlwaysCheckbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();
    expect(result!.action, WriterSaveAction.overwrite);
    expect(result!.dontAskAgain, true);
  });

  testWidgets('returns saveAsNew', (tester) async {
    WriterSaveChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result =
                  await showWriterSaveChoiceDialog(context, saveName: 'X'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAsNew')));
    await tester.pumpAndSettle();
    expect(result!.action, WriterSaveAction.saveAsNew);
    expect(result!.dontAskAgain, false);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/songwriter/writer_save_choice_dialog_test.dart`
Expected: FAIL — file/symbols undefined.

- [ ] **Step 3: Create the dialog**

Create `lib/features/songwriter/writer_save_choice_dialog.dart`:

```dart
import 'package:flutter/material.dart';

enum WriterSaveAction { overwrite, saveAsNew }

class WriterSaveChoice {
  final WriterSaveAction action;
  final bool dontAskAgain;
  const WriterSaveChoice(this.action, this.dontAskAgain);
}

/// Prompts whether to overwrite the bound save or create a new one. Returns
/// null on cancel.
Future<WriterSaveChoice?> showWriterSaveChoiceDialog(
  BuildContext context, {
  required String saveName,
}) =>
    showDialog<WriterSaveChoice>(
      context: context,
      builder: (_) => _WriterSaveChoiceDialog(saveName: saveName),
    );

class _WriterSaveChoiceDialog extends StatefulWidget {
  const _WriterSaveChoiceDialog({required this.saveName});
  final String saveName;
  @override
  State<_WriterSaveChoiceDialog> createState() =>
      _WriterSaveChoiceDialogState();
}

class _WriterSaveChoiceDialogState extends State<_WriterSaveChoiceDialog> {
  bool _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Save changes to '${widget.saveName}'?"),
      content: CheckboxListTile(
        key: const Key('writerSaveAlwaysCheckbox'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _dontAsk,
        onChanged: (v) => setState(() => _dontAsk = v ?? false),
        title: const Text('Always overwrite for this project'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('writerSaveAsNew'),
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.saveAsNew, _dontAsk),
          ),
          child: const Text('Save as new…'),
        ),
        FilledButton(
          key: const Key('writerSaveOverwrite'),
          onPressed: () => Navigator.pop(
            context,
            WriterSaveChoice(WriterSaveAction.overwrite, _dontAsk),
          ),
          child: const Text('Overwrite'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/features/songwriter/writer_save_choice_dialog_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/writer_save_choice_dialog.dart test/features/songwriter/writer_save_choice_dialog_test.dart
git commit -m "feat(writer): add overwrite/save-as-new choice dialog"
```

---

## Task 4: SaveBrowserPanel optional bind callbacks

**Files:**
- Modify: `lib/ui/save_browser_panel.dart`

No new test here (shared widget; binding wiring is covered by Task 6 widget tests + serve-sim). Pure additive callbacks — existing instrument panels pass neither, so behavior is unchanged.

- [ ] **Step 1: Add the callback fields**

In `lib/ui/save_browser_panel.dart`, near the existing `onLoad` field (around line 48), add:

```dart
  /// Called with the new save id after a successful "Save here".
  final void Function(String saveId)? onSaved;

  /// Called with the loaded save's id when a save is loaded (alongside onLoad).
  final void Function(String saveId)? onLoadSaveId;
```

Add them to the constructor (near `this.onLoad,`):

```dart
    this.onSaved,
    this.onLoadSaveId,
```

- [ ] **Step 2: Invoke `onSaved` after saving**

In `_handleSaveHere` (around line 346-350), replace:

```dart
    final snap = capture();
    ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, _currentFolderId!, snap);
    HapticFeedback.mediumImpact();
```

with:

```dart
    final snap = capture();
    final newId = ref
        .read(saveSystemProvider.notifier)
        .saveSnapshot(name, _currentFolderId!, snap);
    if (newId != null) widget.onSaved?.call(newId);
    HapticFeedback.mediumImpact();
```

- [ ] **Step 3: Invoke `onLoadSaveId` on load**

In `_handleLoad` (around line 462-465), replace:

```dart
  void _handleLoad(SaveEntry save) {
    final onLoad = widget.onLoad;
    if (onLoad == null) return;
    ref.read(saveSystemProvider.notifier).loadSave(save.id, onLoad);
  }
```

with:

```dart
  void _handleLoad(SaveEntry save) {
    final onLoad = widget.onLoad;
    if (onLoad == null) return;
    ref.read(saveSystemProvider.notifier).loadSave(save.id, onLoad);
    widget.onLoadSaveId?.call(save.id);
  }
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/ui/save_browser_panel.dart`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/save_browser_panel.dart
git commit -m "feat(save-browser): optional onSaved/onLoadSaveId callbacks"
```

---

## Task 5: Bind on load/save in the Songwriter save panel

**Files:**
- Modify: `lib/features/songwriter/songwriter_save_panel.dart`

- [ ] **Step 1: Wire the callbacks**

In `lib/features/songwriter/songwriter_save_panel.dart`, add the import:

```dart
import '../../store/writer_save_binding_store.dart';
```

Replace the `SaveBrowserPanel(...)` returned in `build` with:

```dart
    return SaveBrowserPanel(
      rootFolderId: selected.id,
      instrumentFilter: 'songwriter',
      captureSnapshot: () => ref.read(songwriterProvider),
      onLoad: (snapshot) {
        if (snapshot is SongwriterProjectSnapshot) {
          notifier.loadProject(snapshot);
        }
      },
      onLoadSaveId: (saveId) => ref
          .read(writerSaveBindingProvider.notifier)
          .bind(selected.id, saveId),
      onSaved: (saveId) =>
          ref.read(writerSaveBindingProvider.notifier).bind(selected.id, saveId),
    );
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/songwriter/songwriter_save_panel.dart`
Expected: No new errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/songwriter/songwriter_save_panel.dart
git commit -m "feat(writer): bind save id on load/save in songwriter save panel"
```

---

## Task 6: Save flow + header indicator (with widget tests)

**Files:**
- Modify: `lib/features/songwriter/songwriter_header.dart`
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/features/songwriter/writer_save_flow_test.dart`

- [ ] **Step 1: Write the failing flow + indicator tests**

Create `test/features/songwriter/writer_save_flow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/writer_save_binding_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Seeds a selected project bound to a save, then makes the project dirty.
  /// Returns (container, projectId, saveId).
  (ProviderContainer, String, String) seedDirtyBound() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    final n = c.read(songwriterProvider.notifier);
    n.addSection(label: 'V', lengthBars: 4);
    final saveId = ss.saveSnapshot('s1', pid, c.read(songwriterProvider))!;
    c.read(writerSaveBindingProvider.notifier).bind(pid, saveId);
    n.setTempo(200); // diverge from the bound save
    return (c, pid, saveId);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: Scaffold(body: SongwriterScreenSheet())),
      ),
    );
    await tester.pump();
  }

  testWidgets('badge shows when dirty and overwrite updates the bound save',
      (tester) async {
    final (c, _, saveId) = seedDirtyBound();
    await pump(tester, c);

    expect(find.byKey(const Key('writerUnsavedBadge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();

    final entry =
        c.read(saveSystemProvider).saves.firstWhere((s) => s.id == saveId);
    expect((entry.snapshot as SongwriterProjectSnapshot).config.tempo, 200);
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('checkbox sets always-overwrite and next save skips the dialog',
      (tester) async {
    final (c, pid, _) = seedDirtyBound();
    await pump(tester, c);

    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('writerSaveAlwaysCheckbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveOverwrite')));
    await tester.pumpAndSettle();

    expect(
      c.read(writerSaveBindingProvider)[pid]!.alwaysOverwrite,
      true,
    );

    // Make dirty again, save → no dialog.
    c.read(songwriterProvider.notifier).setTempo(150);
    await tester.pump();
    await tester.tap(find.byKey(const Key('writerSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writerSaveOverwrite')), findsNothing);
    expect(c.read(writerDirtyProvider), false);
  });

  testWidgets('no badge when project is clean', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ss = c.read(saveSystemProvider.notifier);
    final pid = ss.createProject('Proj', const ProjectConfig())!;
    ss.selectProject(pid);
    await pump(tester, c);
    expect(find.byKey(const Key('writerUnsavedBadge')), findsNothing);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/features/songwriter/writer_save_flow_test.dart`
Expected: FAIL — `writerUnsavedBadge` / `writerSaveButton` not found.

- [ ] **Step 3: Add `clear` to `newProject`**

In `lib/store/songwriter_store.dart`, add the import at the top with the other store imports:

```dart
import 'writer_save_binding_store.dart';
```

In `newProject()` (around line 94-100), after the `songwriterSessionsProvider` remove, add the binding clear:

```dart
  Future<void> newProject() async {
    state = _emptyProject();
    final id = ref.read(saveSystemProvider).selectedProjectId;
    if (id != null) {
      ref.read(songwriterSessionsProvider.notifier).remove(id);
      ref.read(writerSaveBindingProvider.notifier).clear(id);
    }
  }
```

- [ ] **Step 4: Add header indicator + Save button + overflow Save tile**

In `lib/features/songwriter/songwriter_header.dart`:

Add the import:

```dart
import '../../store/writer_save_binding_store.dart';
```

Add an `onSave` field and constructor entry:

```dart
  final VoidCallback? onSave;
```
```dart
    this.onSave,
```

In `build`, after `final notifier = ...`, add:

```dart
    final dirty = ref.watch(writerDirtyProvider);
```

In the non-compact title `Row` children, insert the badge + Save button immediately **before** the `if (onStartTour != null)` help button:

```dart
                  if (dirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Row(
                        key: const Key('writerUnsavedBadge'),
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.circle, size: 8,
                              color: MuzicianTheme.orange),
                          SizedBox(width: 4),
                          Text(
                            'Unsaved',
                            style: TextStyle(
                              color: MuzicianTheme.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (onSave != null)
                    IconBtn(
                      key: const Key('writerSaveButton'),
                      icon: Icons.save_rounded,
                      color: dirty
                          ? MuzicianTheme.orange
                          : MuzicianTheme.textDim,
                      onTap: onSave!,
                    ),
```

In `_showOverflowMenu`, add a "Save" tile as the first child of the `Column`, before the existing "Save / Load" tile (so compact/landscape can still trigger it):

```dart
          _MenuTile(
            icon: Icons.save_rounded,
            label: 'Save',
            onTap: () {
              Navigator.pop(context);
              onSave?.call();
            },
          ),
```

- [ ] **Step 5: Add `_saveProject` and wire `onSave` in the screen sheet**

In `lib/features/songwriter/songwriter_screen_sheet.dart`:

Add imports (with the existing store/model imports near the top):

```dart
import '../../models/save_system.dart';
import '../../store/writer_save_binding_store.dart';
import 'writer_save_choice_dialog.dart';
```

(`HapticFeedback` from `package:flutter/services.dart` and `save_system_store.dart` are already imported.)

Add these methods to `_SongwriterScreenSheetState` (next to `_openSaveLoad`):

```dart
  Future<void> _saveProject(BuildContext context) async {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return;
    final binding = ref.read(writerSaveBindingProvider)[projectId];
    final id = binding?.activeSaveId;
    SaveEntry? entry;
    if (id != null) {
      for (final s in ref.read(saveSystemProvider).saves) {
        if (s.id == id) {
          entry = s;
          break;
        }
      }
    }
    // Unbound or stale binding → first save via the Save/Load panel.
    if (entry == null) {
      _openSaveLoad(context);
      return;
    }
    if (binding!.alwaysOverwrite) {
      _overwrite(entry);
      return;
    }
    final choice =
        await showWriterSaveChoiceDialog(context, saveName: entry.name);
    if (choice == null) return;
    if (choice.action == WriterSaveAction.saveAsNew) {
      _openSaveLoad(context);
      return;
    }
    if (choice.dontAskAgain) {
      ref
          .read(writerSaveBindingProvider.notifier)
          .setAlwaysOverwrite(projectId, true);
    }
    _overwrite(entry);
  }

  void _overwrite(SaveEntry entry) {
    ref
        .read(saveSystemProvider.notifier)
        .updateSnapshot(entry.id, ref.read(songwriterProvider));
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
    );
  }
```

Wire `onSave` into the header (in `build`, the `SongwriterHeader(...)` call):

```dart
              child: SongwriterHeader(
                onOpenSaveLoad: () => _openSaveLoad(context),
                onOpenStructure: () => _openStructure(context),
                onSave: () => _saveProject(context),
                onStartTour: () =>
                    startCoachTour(context, writerCoachSteps(_coachKeys)),
              ),
```

- [ ] **Step 6: Run the flow tests, verify they pass**

Run: `flutter test test/features/songwriter/writer_save_flow_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_header.dart lib/features/songwriter/songwriter_screen_sheet.dart lib/store/songwriter_store.dart test/features/songwriter/writer_save_flow_test.dart
git commit -m "feat(writer): unsaved badge + Save button + overwrite/new flow"
```

---

## Task 7: Hydrate binding store at startup

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the hydrate call**

In `lib/main.dart`, add the import with the other store imports, then add the hydrate after the songwriter sessions hydrate (around line 89):

```dart
      await ref.read(songwriterSessionsProvider.notifier).hydrate();
      await ref.read(writerSaveBindingProvider.notifier).hydrate();
```

Import:

```dart
import 'store/writer_save_binding_store.dart';
```

- [ ] **Step 2: Verify the whole suite + analyzer**

Run: `flutter analyze`
Expected: No new errors/warnings.

Run: `flutter test`
Expected: All tests pass (existing + new).

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(writer): hydrate save binding store on launch"
```

---

## Task 8: Manual verification on simulator (serve-sim)

**Files:** none (verification only)

- [ ] **Step 1: Launch the app on the iOS simulator via the serve-sim skill** and open Writer on a real project (not Dump).

- [ ] **Step 2: Verify unbound dirty** — add a section. Confirm the amber "Unsaved" badge + highlighted Save button appear.

- [ ] **Step 3: Verify first save** — tap Save → Save/Load panel opens → name + save into a folder. Badge clears.

- [ ] **Step 4: Verify dirty-after-edit** — change tempo/key. Badge reappears.

- [ ] **Step 5: Verify overwrite prompt** — tap Save → dialog "Save changes to '<name>'?" → Overwrite → badge clears, "Saved" snackbar.

- [ ] **Step 6: Verify save-as-new** — make dirty, Save → "Save as new…" → panel → new name. New save created and bound (badge clears).

- [ ] **Step 7: Verify "always overwrite"** — make dirty, Save → tick "Always overwrite for this project" → Overwrite. Then make dirty again, Save → no dialog, silent overwrite + snackbar.

- [ ] **Step 8: Verify reset on load** — load a different save → make dirty → Save → dialog appears again (flag reset).

- [ ] **Step 9: Capture a screenshot of the Unsaved badge and the choice dialog** for the PR.

---

## Self-Review

**Spec coverage:**
- Unsaved indicator → Task 1 (dirty provider) + Task 6 (badge). ✓
- Save with overwrite-vs-new prompt → Task 3 (dialog) + Task 6 (`_saveProject`). ✓
- "Don't ask again per project → overwrite" → Task 1 (`alwaysOverwrite`) + Task 6 (checkbox + skip). ✓
- Reuse Save/Load panel for first save / save-as-new → Task 6 (`_openSaveLoad`). ✓
- Reset on different-save-load / new-project → Task 5 (bind resets) + Task 6 (`newProject` clear). ✓
- Persistence → Task 1 (prefs) + Task 7 (hydrate). ✓

**Placeholder scan:** No TBD/TODO; every code step has full code. ✓

**Type consistency:** `WriterSaveBinding{activeSaveId, alwaysOverwrite}`, `bind/setAlwaysOverwrite/clear/get`, `writerSaveBindingProvider`, `writerDirtyProvider`, `WriterSaveAction{overwrite, saveAsNew}`, `WriterSaveChoice{action, dontAskAgain}`, `showWriterSaveChoiceDialog`, keys `writerUnsavedBadge`/`writerSaveButton`/`writerSaveOverwrite`/`writerSaveAsNew`/`writerSaveAlwaysCheckbox` — used consistently across tasks. ✓
