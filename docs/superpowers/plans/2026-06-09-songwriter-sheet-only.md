# Songwriter Sheet-Only + Chord-Anchored Lyrics + Drum-In-Sheet Implementation Plan

> **Supersedes:** `2026-06-09-songwriter-lyrics-per-block.md` (do not execute that one alongside this — this plan absorbs its scope and reframes the targets to Sheet-only).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
1. Delete the Track and Classic Writer layouts entirely. **Sheet is the only Writer.**
2. Extend the Sheet variant to host all lane types — **harmony** (chord cells with per-block multi-verse lyrics + silent placeholders, aligned to bar grid), **drum** (per-section drum lanes rendered as a strip beneath harmony with bar-aligned pattern tiles), and **save** (kept as the existing chip strip below drum lanes — promoted to a proper full-width row if visual clarity requires it).
3. Drop the `WriterLayout` setting, picker UI, and persistence migration logic.

**Architecture:**
- One Writer entry-point: `SongwriterScreen` directly renders `SongwriterScreenSheet`. No layout switch, no enum, no persisted preference.
- **Section repeat = visual instance duplication.** `section.repeat = N` renders N stacked `_SectionInstance` blocks. Each instance has its own harmony bar row, its own lyric row (reading `block.lyrics[instanceIndex]`), and its own drum/save lane strips. Chord blocks are SHARED across instances (one source of truth — editing a chord in instance 2 mutates the underlying `SongBlock`, so instance 1 sees the same change). Lyrics are PER-INSTANCE (`block.lyrics: List<String>` indexed by instance).
- `_BarCell` becomes the shared atom: chord glyph OR silent dot OR empty dot. Each `_BarCell` belongs to one instance; lyric is rendered in a separate parallel row of cells aligned to the same `Expanded(flex: spanBars)` widths, directly under the harmony row of that instance.
- Drum lanes render as a `_BarRow`-style strip under each instance's lyric row — same wrap-to-4-bars layout, same flex math, tiles show pattern name + open `drum_pattern_sheet.dart` on tap. Drum patterns are shared across instances (same `patternId`).
- Save-lane chips render once per section (NOT per instance) below the last instance.
- Lyrics live on `SongBlock` (`List<String>` indexed by instance, `isSilent: bool`). `SongSection.lyrics` is removed.

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages.

**Migration policy:**
- Legacy `AppSettings.writerLayout` JSON key: silently ignored on load.
- Legacy `SongSection.lyrics` blobs: silently dropped on load.
- No upgrade UI. No user-visible migration prompt.

**Non-goals (deferred):**
- Bar-quantized syllable / melismatic alignment inside a single chord cell.
- Karaoke playback scroll.
- Sheet-variant drum-pattern inline preview thumbnails (tile shows pattern name only).
- Auto-shrinking the verse list when `section.repeat` decreases (storage preserves user input; UI clamps editor).
- Re-introducing Track / Classic layouts as a toggle.
- Per-instance drum / save lane variation. Drum patterns and save references are shared across instances of a section. Only lyrics vary per instance.
- Collapsible "show first instance only" toggle for large `section.repeat`. Defer until visual feedback warrants it.

---

## File Structure

**Created:**
- `test/models/song_block_lyrics_test.dart`
- `test/models/song_block_silent_test.dart`
- `test/store/songwriter_block_lyrics_test.dart`
- `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
- `test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
- `test/features/songwriter/songwriter_sheet_drum_lane_test.dart`

**Modified:**
- `lib/models/songwriter.dart`
- `lib/models/save_system.dart` — drop `AppSettings.writerLayout` field + `WriterLayout` enum + `_writerLayoutFromName`.
- `lib/schema/rules/songwriter_rules.dart`
- `lib/store/songwriter_store.dart`
- `lib/store/settings_store.dart` — drop `setWriterLayout`.
- `lib/features/songwriter/songwriter_screen.dart` — collapse to a direct `SongwriterScreenSheet` render; remove the layout switch and the `_SongwriterScreenClassic` class.
- `lib/features/songwriter/songwriter_header.dart` — remove the layout picker (lines ~580-604).
- `lib/features/songwriter/harmony_chord_sheet.dart`
- `lib/features/songwriter/songwriter_screen_sheet.dart`

**Deleted (with `git rm`):**
- `lib/features/songwriter/songwriter_screen_track.dart`
- `lib/features/songwriter/songwriter_section_card.dart`
- `lib/features/songwriter/songwriter_block_tile.dart` (was the Track tile widget — Sheet uses `_BarCell` internally; verify no other importers remain before deletion)
- `lib/features/songwriter/section_lyrics_sheet.dart`
- `test/features/songwriter/section_lyrics_sheet_test.dart`
- `test/features/songwriter/songwriter_lyrics_render_test.dart`
- `test/features/songwriter/songwriter_drum_lane_render_test.dart`
- `test/features/songwriter/songwriter_section_card_test.dart`
- `test/features/songwriter/songwriter_section_pills_test.dart`
- `test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart` (Track-only)
- `test/models/song_section_lyrics_test.dart`

> **Before deleting `songwriter_block_tile.dart`:** run `grep -rn "songwriter_block_tile\|SongwriterBlockTile" lib/ test/` to confirm no other feature depends on it. If anything outside Songwriter imports it, abort that delete and report.

---

## Task 1: Demolish Track and Classic Writer variants

**Files:**
- Delete: `lib/features/songwriter/songwriter_screen_track.dart`
- Delete: `lib/features/songwriter/songwriter_section_card.dart`
- Delete: `lib/features/songwriter/songwriter_block_tile.dart` (only if no other module imports it)
- Modify: `lib/features/songwriter/songwriter_screen.dart`
- Delete: the per-variant tests listed above

- [ ] **Step 1: Confirm no out-of-feature imports**

Run:

```bash
grep -rn "songwriter_screen_track\|songwriter_section_card\|songwriter_block_tile" \
  lib/ test/ \
  | grep -v "^lib/features/songwriter/" \
  | grep -v "^test/features/songwriter/"
```

Expected: no output. If any line appears, stop and report — those callers must be migrated before this task continues.

- [ ] **Step 2: Delete the variant files and their tests**

```bash
git rm \
  lib/features/songwriter/songwriter_screen_track.dart \
  lib/features/songwriter/songwriter_section_card.dart \
  lib/features/songwriter/songwriter_block_tile.dart \
  test/features/songwriter/songwriter_drum_lane_render_test.dart \
  test/features/songwriter/songwriter_lyrics_render_test.dart \
  test/features/songwriter/songwriter_section_card_test.dart \
  test/features/songwriter/songwriter_section_pills_test.dart \
  test/features/songwriter/songwriter_block_tile_harmony_tap_test.dart
```

- [ ] **Step 3: Collapse `songwriter_screen.dart`**

Replace the entire file body with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'songwriter_screen_sheet.dart';

class SongwriterScreen extends ConsumerWidget {
  const SongwriterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      const SongwriterScreenSheet();
}
```

- [ ] **Step 4: Verify the project compiles**

Run: `flutter analyze lib/features/songwriter/ lib/features/songwriter`
Expected: no errors caused by missing imports. Errors at call sites in `songwriter_header.dart` (the layout picker) and in `settings_store.dart` / `save_system.dart` (the enum) are expected — those are fixed in Task 2.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(songwriter): delete Track and Classic layouts"
```

---

## Task 2: Drop `WriterLayout` enum, setting field, setter, and header picker

**Files:**
- Modify: `lib/models/save_system.dart`
- Modify: `lib/store/settings_store.dart`
- Modify: `lib/features/songwriter/songwriter_header.dart`

- [ ] **Step 1: Remove the enum and the field**

In `lib/models/save_system.dart`:
- Remove `final WriterLayout writerLayout;` from `AppSettings` plus the `writerLayout` constructor param, the `copyWith` line, the `toJson` key, and the `fromJson` call. The `fromJson` factory simply omits the `writerLayout` line — leftover JSON keys are silently ignored by Dart maps.
- Remove the `enum WriterLayout { classic, track, sheet }` declaration.
- Remove the `_writerLayoutFromName` helper.

- [ ] **Step 2: Remove the setter**

In `lib/store/settings_store.dart`:
- Remove the `setWriterLayout` method.
- Remove any `WriterLayout` imports.

- [ ] **Step 3: Remove the header picker**

In `lib/features/songwriter/songwriter_header.dart`:
- Locate the layout picker (search for `WriterLayout.values` — lines ~580-604).
- Remove the picker widget tree, any related state, and the surrounding label/divider so the header lays out cleanly.
- Remove the `WriterLayout` import.

If a test exists for the layout picker (search `grep -rn "writer.layout\|writerLayout" test/`), delete it.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors related to `WriterLayout`. Existing analyzer warnings on this branch (unrelated work in the working tree) are not in scope.

Run: `flutter test test/store/settings_store_test.dart test/models/app_settings_test.dart`
Expected: PASS. If a settings test asserts the `writerLayout` default or round-trip, update or delete that assertion — the field no longer exists.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(songwriter): drop WriterLayout enum, setting, picker"
```

---

## Task 3: Remove `SongSection.lyrics`

**Files:**
- Modify: `lib/models/songwriter.dart` (`SongSection` class around line 277)
- Modify: `lib/store/songwriter_store.dart` — drop `setSectionLyrics`
- Delete: `test/models/song_section_lyrics_test.dart`

- [ ] **Step 1: Delete the obsolete test**

```bash
git rm test/models/song_section_lyrics_test.dart
```

- [ ] **Step 2: Strip `lyrics` from `SongSection`**

In `lib/models/songwriter.dart`:
- Remove `final String? lyrics;` and the `this.lyrics` constructor param.
- Remove `lyrics` from `copyWith` (and the `clearLyrics` bool).
- Remove the `lyrics` key from `toJson`.
- Remove the `lyrics:` line from `fromJson` — extra keys are silently ignored.

- [ ] **Step 3: Strip the store mutator**

In `lib/store/songwriter_store.dart` remove the `setSectionLyrics` method.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/`
Expected: errors only at call sites in `songwriter_screen_sheet.dart` (the now-doomed `_LyricsBlock`). Continue to Task 4.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(songwriter): drop SongSection.lyrics in favor of per-block lyrics"
```

---

## Task 4: Add `lyrics` + `isSilent` to `SongBlock`

**Files:**
- Modify: `lib/models/songwriter.dart` (`SongBlock` class around line 15)
- Test: `test/models/song_block_lyrics_test.dart`, `test/models/song_block_silent_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/models/song_block_lyrics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongBlock default lyrics is empty list, isSilent false', () {
    const b = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
    expect(b.lyrics, isEmpty);
    expect(b.isSilent, isFalse);
  });

  test('SongBlock round-trips lyrics list', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 2,
      chordSymbol: 'C',
      lyrics: ['hello', 'goodbye', ''],
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.lyrics, ['hello', 'goodbye', '']);
  });

  test('copyWith replaces lyrics list when provided', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 1,
      lyrics: ['one'],
    );
    final next = b.copyWith(lyrics: ['one', 'two']);
    expect(next.lyrics, ['one', 'two']);
  });

  test('fromJson tolerates missing lyrics key', () {
    final back = SongBlock.fromJson({
      'id': 'b1',
      'startBar': 0,
      'spanBars': 1,
    });
    expect(back.lyrics, isEmpty);
  });
}
```

`test/models/song_block_silent_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongBlock round-trips isSilent flag', () {
    const b = SongBlock(
      id: 'b1',
      startBar: 0,
      spanBars: 1,
      isSilent: true,
      lyrics: ['(instrumental)'],
    );
    final back = SongBlock.fromJson(b.toJson());
    expect(back.isSilent, isTrue);
    expect(back.lyrics, ['(instrumental)']);
    expect(back.chordSymbol, isNull);
  });

  test('copyWith toggles isSilent', () {
    const b = SongBlock(id: 'b1', startBar: 0, spanBars: 1);
    expect(b.copyWith(isSilent: true).isSilent, isTrue);
  });

  test('fromJson defaults isSilent to false when absent', () {
    final back = SongBlock.fromJson({
      'id': 'b1',
      'startBar': 0,
      'spanBars': 1,
    });
    expect(back.isSilent, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/models/song_block_lyrics_test.dart test/models/song_block_silent_test.dart`
Expected: FAIL — `lyrics`, `isSilent` undefined.

- [ ] **Step 3: Add the fields**

Apply the exact `SongBlock` rewrite from the per-block plan, Task 2 Step 3 (see `2026-06-09-songwriter-lyrics-per-block.md`). The shape:

```dart
final List<String> lyrics;       // default const []
final bool isSilent;             // default false
```

Add them to the constructor (with defaults), `copyWith`, `toJson`, `fromJson`. Tolerant decode for legacy JSON (missing keys → defaults).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/song_block_lyrics_test.dart test/models/song_block_silent_test.dart`
Expected: PASS (7/7).

- [ ] **Step 5: Run all model tests**

Run: `flutter test test/models/`
Expected: PASS — additive fields don't break round-trips.

- [ ] **Step 6: Commit**

```bash
git add lib/models/songwriter.dart test/models/song_block_lyrics_test.dart test/models/song_block_silent_test.dart
git commit -m "feat(songwriter): add SongBlock.lyrics list and isSilent flag"
```

---

## Task 5: Factory + store mutators for lyrics and silent blocks

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart`
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_block_lyrics_test.dart`

Implementation is identical to the per-block plan's Task 3. Carry over the failing tests, the `makeSilentBlock` factory, and the `setBlockLyric` / `addSilentBlock` mutators verbatim.

- [ ] **Step 1: Write the failing tests** (copy from per-block plan Task 3 Step 1).
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Add factory and mutators** (per-block plan Task 3 Step 3).
- [ ] **Step 4: Verify tests pass.**
- [ ] **Step 5: Run full songwriter store suite.**
- [ ] **Step 6: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart lib/store/songwriter_store.dart test/store/songwriter_block_lyrics_test.dart
git commit -m "feat(songwriter): block-level lyrics + silent-block mutators"
```

---

## Task 6: Harmony chord sheet — single per-instance lyric input + silent toggle

**Files:**
- Modify: `lib/features/songwriter/harmony_chord_sheet.dart`
- Test: `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`

Key change vs the superseded per-block plan: the chord sheet renders exactly **one** lyric input (for the instance the user tapped from), not N. The caller passes the `instanceIndex` and the current lyric text. The returned `SongBlock.lyrics` carries a single-element list whose index the caller knows; the store mutator slots it via `setBlockLyric(blockId, instanceIndex, text)`.

**Updated entrypoint signature:**

```dart
Future<SongBlock?> showHarmonyChordSheet(
  BuildContext context, {
  required int startBar,
  required int spanBars,
  required int? keyRoot,
  required String? keyScaleName,
  SongBlock? existing,
  int instanceIndex = 0,
  String currentLyric = '',
});
```

- `instanceIndex` — which repeat-pass the user tapped from (default 0 = first instance).
- `currentLyric` — the existing lyric for that instance (read from `existing.lyrics[instanceIndex]` if present, else `''`).
- Return value: the returned `SongBlock` carries the chord state plus a single-entry `lyrics: [editedText]`. The caller writes it via `setBlockLyric(blockId, instanceIndex, editedText)` — the sheet itself never knows about the full lyric list.

- [ ] **Step 1: Write the failing widget tests**

`test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  testWidgets('renders a single lyric input prefilled with currentLyric',
      (tester) async {
    SongBlock? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showHarmonyChordSheet(
                  ctx,
                  startBar: 0,
                  spanBars: 1,
                  keyRoot: 0,
                  keyScaleName: 'major',
                  instanceIndex: 2,
                  currentLyric: 'verse 3 lyric',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lyricInput')), findsOneWidget);
    final TextField field = tester.widget(find.byKey(const Key('lyricInput')));
    expect(field.controller!.text, 'verse 3 lyric');
    // Label should mention the instance for clarity.
    expect(find.textContaining('Verse 3'), findsOneWidget);
  });

  testWidgets('silent toggle returns a silent block with the typed lyric',
      (tester) async {
    SongBlock? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showHarmonyChordSheet(
                  ctx,
                  startBar: 1,
                  spanBars: 1,
                  keyRoot: 0,
                  keyScaleName: 'major',
                  instanceIndex: 0,
                  currentLyric: '',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('silentToggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lyricInput')), 'oh');
    await tester.tap(find.byKey(const Key('confirmSilent')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isSilent, isTrue);
    expect(result!.chordSymbol, isNull);
    expect(result!.lyrics, ['oh']); // single-entry list
    expect(result!.startBar, 1);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
Expected: FAIL — params missing, keys absent.

- [ ] **Step 3: Implement**

In `harmony_chord_sheet.dart`:

1. Add `instanceIndex` + `currentLyric` + `existing` params on `showHarmonyChordSheet` and forward them into `_HarmonySheet`.

2. State on `_HarmonySheetState`:

```dart
bool _silentMode = false;
late final TextEditingController _lyricController;

@override
void initState() {
  super.initState();
  _silentMode = widget.existing?.isSilent ?? false;
  _lyricController = TextEditingController(text: widget.currentLyric);
}

@override
void dispose() {
  _lyricController.dispose();
  super.dispose();
}
```

3. Below the chord picker (or in place of it when `_silentMode`), render one input:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
  child: TextField(
    key: const Key('lyricInput'),
    controller: _lyricController,
    style: const TextStyle(color: MuzicianTheme.textPrimary),
    decoration: InputDecoration(
      labelText: 'Verse ${widget.instanceIndex + 1}',
      labelStyle: const TextStyle(color: MuzicianTheme.textMuted),
      filled: true,
      fillColor: MuzicianTheme.glassBg,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: MuzicianTheme.glassBorder),
      ),
    ),
  ),
),
```

4. Silent-mode confirm:

```dart
if (_silentMode)
  Padding(
    padding: const EdgeInsets.all(12),
    child: FilledButton(
      key: const Key('confirmSilent'),
      onPressed: () {
        Navigator.of(context).pop(
          SongBlock(
            id: widget.existing?.id ?? generateId(),
            startBar: widget.startBar,
            spanBars: widget.spanBars,
            isSilent: true,
            lyrics: [_lyricController.text],
          ),
        );
      },
      child: const Text('Save placeholder'),
    ),
  ),
```

5. Chord-pick path: when a chord is selected, return the existing chord-block construction with `.copyWith(lyrics: [_lyricController.text], isSilent: false)`.

6. Silent toggle:

```dart
SwitchListTile(
  key: const Key('silentToggle'),
  title: const Text('Silent placeholder (lyric only)'),
  value: _silentMode,
  onChanged: (v) => setState(() => _silentMode = v),
),
```

- [ ] **Step 4: Verify tests pass**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Existing harmony tests still green**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: PASS — `instanceIndex` defaults to 0, `currentLyric` defaults to `''`, `existing` defaults to null.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/harmony_chord_sheet.dart test/features/songwriter/harmony_chord_sheet_lyrics_test.dart
git commit -m "feat(songwriter): single per-instance lyric input in chord sheet"
```

---

## Task 7: Sheet variant — render N instances of each section, lyrics aligned per instance

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Delete: `lib/features/songwriter/section_lyrics_sheet.dart`, `test/features/songwriter/section_lyrics_sheet_test.dart`
- Test: `test/features/songwriter/songwriter_sheet_instance_test.dart`

The Sheet now renders `section.repeat` stacked `_SectionInstance` widgets. Each instance has its own harmony bar row + its own lyric bar row, but they share the same `SongBlock` chord data (one source of truth) and the same drum patterns. Lyric text is read from `block.lyrics[instanceIndex]`. Editing a chord cell opens `showHarmonyChordSheet` with the tapped instance's index and current lyric.

- [ ] **Step 1: Delete obsolete files**

```bash
git rm lib/features/songwriter/section_lyrics_sheet.dart
git rm test/features/songwriter/section_lyrics_sheet_test.dart
```

- [ ] **Step 2: Write the failing instance test**

`test/features/songwriter/songwriter_sheet_instance_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders section.repeat instances, each with its own lyric row',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: section.id,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ).copyWith(lyrics: ['hello', 'goodbye']),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    // Two instances rendered.
    expect(find.byKey(Key('sectionInstance_${section.id}_0')), findsOneWidget);
    expect(find.byKey(Key('sectionInstance_${section.id}_1')), findsOneWidget);

    // Chord symbol appears once per instance (i.e. twice total).
    expect(find.text('C'), findsNWidgets(2));

    // Each instance shows its own lyric.
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('goodbye'), findsOneWidget);
  });

  testWidgets('silent placeholder dot renders inside each instance',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Bridge', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;

    n.addSilentBlock(
      sectionId: section.id,
      laneId: laneId,
      startBar: 0,
      spanBars: 1,
      verseCount: 2,
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;
    n.setBlockLyric(
      sectionId: section.id,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: '(ahh)',
    );
    n.setBlockLyric(
      sectionId: section.id,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 1,
      text: '(ooh)',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    // Silent dot appears in both instances.
    expect(find.byKey(Key('silentCell_${blockId}_0')), findsOneWidget);
    expect(find.byKey(Key('silentCell_${blockId}_1')), findsOneWidget);
    expect(find.text('(ahh)'), findsOneWidget);
    expect(find.text('(ooh)'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_sheet_instance_test.dart`
Expected: FAIL.

- [ ] **Step 4: Strip `_LyricsBlock`**

In `songwriter_screen_sheet.dart` remove the `_LyricsBlock` widget class and its invocation in `_SectionSheet.build`. Remove the `section_lyrics_sheet.dart` import.

- [ ] **Step 5: Restructure `_SectionSheet.build` to render instances**

Replace the existing `_BarRow` invocation (and any sibling lyric block) with an instance loop:

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _SectionHeading(section: section),
    const SizedBox(height: 14),
    for (var i = 0; i < section.repeat.clamp(1, 32); i++)
      Padding(
        padding: EdgeInsets.only(bottom: i == section.repeat - 1 ? 0 : 18),
        child: _SectionInstance(
          key: Key('sectionInstance_${section.id}_$i'),
          section: section,
          harmonyLane: harmonyLane,
          instanceIndex: i,
          keyRoot: config.keyRoot,
          keyScaleName: config.keyScaleName,
          onEnsureLane: () => notifier.addLane(
            sectionId: sectionId,
            kind: SongLaneKind.harmony,
            label: 'Harmony',
          ),
        ),
      ),
    // Save-lane chip strip renders ONCE per section (not per instance).
    if (section.lanes.any((l) => l.kind == SongLaneKind.save)) ...[
      const SizedBox(height: 12),
      // existing save-lane chip wrap, unchanged
    ],
  ],
);
```

- [ ] **Step 6: Implement `_SectionInstance` widget**

Add at the bottom of the file:

```dart
class _SectionInstance extends ConsumerWidget {
  const _SectionInstance({
    super.key,
    required this.section,
    required this.harmonyLane,
    required this.instanceIndex,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
  });

  final SongSection section;
  final SongLane harmonyLane;
  final int instanceIndex;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.repeat > 1)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '— ${instanceIndex + 1} of ${section.repeat} —',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        _BarRow(
          section: section,
          lane: harmonyLane,
          instanceIndex: instanceIndex,
          keyRoot: keyRoot,
          keyScaleName: keyScaleName,
          onEnsureLane: onEnsureLane,
        ),
        // Drum lanes (one strip per drum lane on this section).
        for (final lane in section.lanes.where((l) => l.kind == SongLaneKind.drum)) ...[
          const SizedBox(height: 8),
          _DrumLaneRow(
            key: Key('sheetDrumLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 7: Thread `instanceIndex` through `_BarRow` and `_BarCell`**

Add `final int instanceIndex;` to both. In `_BarCell`, build the inner Column as:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    if (block == null)
      const Text('·', style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 18))
    else if (block.isSilent)
      Container(
        key: Key('silentCell_${block.id}_$instanceIndex'),
        width: 8, height: 8,
        decoration: const BoxDecoration(
          shape: BoxShape.circle, color: MuzicianTheme.textMuted,
        ),
      )
    else
      Text(
        block.chordSymbol ?? '?',
        style: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    if (block != null) const SizedBox(height: 4),
    if (block != null)
      Text(
        instanceIndex < block.lyrics.length ? block.lyrics[instanceIndex] : '',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: MuzicianTheme.textSecondary,
          fontSize: 12,
          height: 1.25,
        ),
      ),
  ],
)
```

- [ ] **Step 8: Update tap handlers to dispatch per-instance lyric edits**

In `_BarRow._addAt` and `_editBlock` (or wherever the chord sheet is opened), pass:

```dart
final currentLyric = (block != null && instanceIndex < block.lyrics.length)
    ? block.lyrics[instanceIndex]
    : '';
final result = await showHarmonyChordSheet(
  context,
  startBar: bar,
  spanBars: 1,
  keyRoot: keyRoot,
  keyScaleName: keyScaleName,
  existing: block,
  instanceIndex: instanceIndex,
  currentLyric: currentLyric,
);
if (result == null) return;
// Chord-or-silent path: ensure block exists, then write the lyric to the right slot.
final blockId = ... ; // existing block id, or the new id from addHarmonyBlock / addSilentBlock
ref.read(songwriterProvider.notifier).setBlockLyric(
  sectionId: section.id,
  laneId: laneId,
  blockId: blockId,
  verseIndex: instanceIndex,
  text: result.lyrics.isNotEmpty ? result.lyrics.first : null,
);
```

The chord sheet returns a `SongBlock` whose `lyrics` is a single-entry list — the caller slots it via `setBlockLyric` at `instanceIndex`. The chord/silent state on the returned block flows through `addHarmonyBlock` / `addSilentBlock` as before.

- [ ] **Step 9: Verify tests pass**

Run: `flutter test test/features/songwriter/songwriter_sheet_instance_test.dart`
Expected: PASS (2/2).

- [ ] **Step 10: Full songwriter suite green**

Run: `flutter test test/features/songwriter/ test/models/song_block_*.dart test/store/songwriter_*.dart`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat(songwriter): render N section instances with per-instance lyric rows"
```

---

## Task 8: Sheet variant — drum lanes rendered inside each instance

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Test: `test/features/songwriter/songwriter_sheet_drum_lane_test.dart`

Drum lanes appear inside each `_SectionInstance`, beneath the harmony+lyrics row of that instance. The drum pattern data is SHARED across instances (same `patternId` → same `DrumPattern` from `SongwriterProjectSnapshot.drumPatterns`). The tile geometry mirrors `_BarRow`: `Expanded(flex: spanBars.clamp(1, end - i))`, wrap-to-4-bars, identical cell widths to the harmony row directly above.

The `_DrumLaneRow` widget receives `instanceIndex` for keying only — the rendered content is identical across instances.

- [ ] **Step 1: Write the failing alignment test**

`test/features/songwriter/songwriter_sheet_drum_lane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('drum lane renders once per instance, sharing pattern data',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.setSectionRepeat(section.id, 2);
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern(name: 'Backbeat');
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    // One drum lane row per instance.
    expect(find.byKey(Key('sheetDrumLane_${laneId}_0')), findsOneWidget);
    expect(find.byKey(Key('sheetDrumLane_${laneId}_1')), findsOneWidget);
    // Pattern name shown in both.
    expect(find.text('Backbeat'), findsNWidgets(2));
  });

  testWidgets('sheet renders a drum lane below the harmony row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern(name: 'Backbeat');
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    expect(find.byKey(Key('sheetDrumLane_$laneId')), findsOneWidget);
    expect(find.byKey(Key('sheetDrumTile_$patternId')), findsOneWidget);
    expect(find.text('Backbeat'), findsOneWidget);
  });

  testWidgets('tapping the drum tile opens the drum pattern sheet',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final section = container.read(songwriterProvider).sections.first;
    n.addLane(
      sectionId: section.id,
      kind: SongLaneKind.drum,
      label: 'Beat',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes
        .firstWhere((l) => l.kind == SongLaneKind.drum).id;
    final patternId = n.addDrumPattern();
    n.addDrumBlock(
      sectionId: section.id,
      laneId: laneId,
      patternId: patternId,
      startBar: 0,
      spanBars: 4,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(Key('sheetDrumTile_$patternId')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('drumPatternBody_$patternId')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_sheet_drum_lane_test.dart`
Expected: FAIL — keys not present.

- [ ] **Step 3: Render drum lanes inside `_SectionInstance`**

In `songwriter_screen_sheet.dart`, add the import:

```dart
import 'drum_pattern_sheet.dart';
```

The `_SectionInstance` widget (added in Task 7) already loops over `section.lanes.where((l) => l.kind == SongLaneKind.drum)` and emits one `_DrumLaneRow` per drum lane with key `sheetDrumLane_<laneId>_<instanceIndex>`. Now flesh out the widget body. Append at the bottom of the file:

```dart
class _DrumLaneRow extends ConsumerWidget {
  const _DrumLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final ownerByBar = <int, SongBlock>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        ownerByBar[i] = b;
      }
    }
    final patternsById = {
      for (final p in ref.read(songwriterProvider).drumPatterns) p.id: p,
    };
    return LayoutBuilder(
      builder: (context, _) {
        const perRow = 4;
        final rows = <List<Widget>>[];
        for (var start = 0; start < bars; start += perRow) {
          final end = (start + perRow).clamp(0, bars);
          final cells = <Widget>[];
          var i = start;
          while (i < end) {
            final owner = ownerByBar[i];
            if (owner != null && owner.startBar == i) {
              final span = owner.spanBars.clamp(1, end - i);
              final pattern = owner.patternId == null
                  ? null
                  : patternsById[owner.patternId];
              cells.add(Expanded(
                flex: span,
                child: GestureDetector(
                  key: Key(
                    'sheetDrumTile_${owner.patternId ?? owner.id}',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (owner.patternId == null) return;
                    showSongwriterDrumPatternSheet(
                      context: context,
                      patternId: owner.patternId!,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MuzicianTheme.orange.withValues(alpha: 0.18),
                      border: Border.all(
                        color: MuzicianTheme.orange.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.graphic_eq,
                          size: 14,
                          color: MuzicianTheme.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            pattern?.name ?? 'pattern?',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MuzicianTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ));
              i += span;
            } else if (owner != null) {
              i++;
            } else {
              cells.add(Expanded(
                flex: 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: MuzicianTheme.glassBorder,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ));
              i++;
            }
          }
          rows.add(cells);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                lane.label ?? 'Beat',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r == rows.length - 1 ? 0 : 6),
                child: Row(children: rows[r]),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/songwriter/songwriter_sheet_drum_lane_test.dart`
Expected: PASS (3/3 — instance-stacked test plus the two original render / tap tests).

- [ ] **Step 5: Run the full songwriter feature suite**

Run: `flutter test test/features/songwriter/ test/store/songwriter_*.dart test/models/songwriter_*.dart test/models/song_block_*.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_sheet_drum_lane_test.dart
git commit -m "feat(songwriter): render drum lanes in sheet variant"
```

---

## Task 9: Add-drum-lane entry point in the Sheet section heading

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`

The Track variant previously hosted the "Add drum lane" menu. Sheet now needs an equivalent. Add a small overflow menu (3-dot icon button) to `_SectionHeading` with two actions: "Add drum lane" and "Add save lane" (existing functionality). The chord-add flow stays on empty `_BarCell` taps.

- [ ] **Step 1: Add the menu**

In `_SectionHeading.build`, add a `PopupMenuButton<String>` to the right of the existing trailing widgets:

```dart
PopupMenuButton<String>(
  key: Key('sheetSectionMenu_${section.id}'),
  icon: const Icon(Icons.more_vert, color: MuzicianTheme.textPrimary),
  onSelected: (value) async {
    if (value == 'addDrumLane') {
      ref.read(songwriterProvider.notifier).addLane(
            sectionId: section.id,
            kind: SongLaneKind.drum,
            label: 'Beat',
          );
      final laneId = ref
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == section.id)
          .lanes
          .lastWhere((l) => l.kind == SongLaneKind.drum)
          .id;
      final patternId = ref.read(songwriterProvider.notifier)
          .addDrumPattern(name: 'Pattern');
      ref.read(songwriterProvider.notifier).addDrumBlock(
            sectionId: section.id,
            laneId: laneId,
            patternId: patternId,
            startBar: 0,
            spanBars: section.lengthBars,
          );
    }
    // ...other actions follow the existing add-save-lane flow.
  },
  itemBuilder: (_) => const [
    PopupMenuItem(
      key: Key('addDrumLaneSheetAction'),
      value: 'addDrumLane',
      child: ListTile(
        leading: Icon(Icons.graphic_eq),
        title: Text('Add drum lane'),
        dense: true,
      ),
    ),
    // Existing add-save-lane item if needed
  ],
),
```

- [ ] **Step 2: Smoke-test the entry point manually**

Run: `flutter run -d <device>`
- From a section, tap the menu → "Add drum lane".
- Verify a drum-lane strip appears under the harmony row with one tile spanning the full section.
- Tap the tile — drum-pattern sheet opens.
- Toggle steps, close, reopen — persisted.

- [ ] **Step 3: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart
git commit -m "feat(songwriter): add-drum-lane menu in sheet section heading"
```

---

## Task 10: Repeat-aware verse growth + full-suite verification

**Files:**
- Modify: `lib/store/songwriter_store.dart` — `setSectionRepeat` grows each harmony block's `lyrics` list to the new repeat count, additive only (never shrinks).
- Test: `test/store/songwriter_block_lyrics_test.dart` (extended)

Identical mechanics to the per-block plan's Task 8; semantics now align with the visual instance model — `lyrics` length matches `section.repeat`, one entry per visible instance.

- [ ] **Step 1: Failing tests** (per-block plan Task 8 Step 1).
- [ ] **Step 2: Run to verify they fail.**
- [ ] **Step 3: Patch `setSectionRepeat`** (per-block plan Task 8 Step 3 — pad each harmony block's `lyrics` with `''` up to the new repeat count, never shrink).
- [ ] **Step 4: Verify tests pass.**
- [ ] **Step 5: Full suite**

Run: `flutter test`
Expected: PASS.

Run: `flutter analyze`
Expected: 0 issues from this branch.

- [ ] **Step 6: Manual smoke-check**

- Open the Writer tab — Sheet is the only view. No layout picker. No Track / Classic option.
- Add a chord — one instance, one lyric row visible. Tap the cell → chord sheet with a single "Verse 1" input.
- Bump `section.repeat = 3` from the section heading pill. Page now shows three stacked instances of the same harmony row, each labeled `— N of 3 —`. Each instance has its own lyric row.
- Tap the cell in instance 2 → chord sheet labels the input "Verse 2" with the current value of `block.lyrics[1]`. Edit, save — only the instance-2 row updates; instance 1 / 3 unchanged.
- Toggle the chord sheet's silent switch → placeholder dot replaces the chord glyph across all instances (chord state is shared). Lyric edit still slots only to the tapped instance.
- Lower `section.repeat = 1` — only one instance visible. Bump back to 3 — the previously typed verse-2 / verse-3 lyrics reappear in the right rows (storage preserved them).
- Add a drum lane via the section heading menu — a drum strip appears under each instance. Pattern name + bar grid identical across instances. Tap any tile → drum-pattern sheet → toggle steps → close. Reopen drum sheet from a DIFFERENT instance — the same steps are visible (pattern is shared).
- Hot restart — confirm everything above survives.

- [ ] **Step 7: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_block_lyrics_test.dart
git commit -m "feat(songwriter): grow block lyrics list when section repeat increases"
```

---

## Self-Review Notes

- **Layout collapse:** Task 1 deletes the variant files; Task 2 strips the enum + setting + picker; Task 9 reseats the drum-lane entry point on the Sheet heading. Writer is Sheet-only end-to-end.
- **Visual repeat:** Task 7 introduces `_SectionInstance` — `section.repeat = N` renders N stacked instances, each with its own harmony row + lyric row. Chord blocks are SHARED; lyric text is per-instance.
- **Sheet completeness:** Task 7 lands per-instance harmony + lyrics + silent placeholders; Task 8 lands drum lanes inside each instance; save-lane chip strip remains untouched (one strip per section, not per instance).
- **Chord sheet flow:** Task 6 simplifies the chord sheet to a single per-instance lyric input. The caller passes `instanceIndex` + `currentLyric`, the sheet returns a single-entry `lyrics` list, the caller slots it via `setBlockLyric(blockId, instanceIndex, text)`. No multi-input form, no verse-stacked text inside cells.
- **Migration:** legacy `writerLayout` and `SongSection.lyrics` JSON keys silently dropped — no user-visible upgrade.
- **No new lane kinds.** `SongLaneKind` stays `{ harmony, save, drum }` from the prior plan.
- **Test surface:** Track-only tests removed (Task 1); Sheet instance + drum tests added (Tasks 7, 8). Net suite stays green at every commit boundary.
- **Theme tokens:** verified `MuzicianTheme.textPrimary` / `textSecondary` / `textMuted` / `orange` / `glassBg` / `glassBorder` / `surface`. No new tokens added.
- **Storage shape:** `block.lyrics: List<String>` length = `section.repeat` after Task 10. Indices not yet typed render `''`. UI never shrinks the list when `repeat` decreases — preserves user input.
- **Vertical density:** `section.repeat = N` multiplies vertical footprint. Acceptable for typical N ≤ 4. Collapsing "show first instance only" toggle is deferred (non-goal).
- **Drum / save lane variation:** explicitly NOT supported per instance. Same pattern / save reference plays back on every repeat. Per-instance variation = future work.
