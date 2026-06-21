# Songwriter Per-Block Lyrics + Silent Placeholders + Multi-Verse Implementation Plan

> **SUPERSEDED by `2026-06-09-songwriter-sheet-only.md`.** That plan absorbs this scope, additionally deletes the Track and Classic Writer layouts, and surfaces drum lanes inside the Sheet variant. Do not execute this plan directly — the dispatch prompt points to the superseding plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-section lyric blobs with chord-anchored per-block lyrics that align with chord cells in the Sheet variant, support **silent placeholder blocks** (lyric-bearing cells with no chord) for instrumental/vocal-only bars, and support **multi-verse** repeat lyrics (one lyric line per `section.repeat` pass) stacked vertically under each chord cell.

**Architecture:**
- Remove `SongSection.lyrics: String?`. Add `SongBlock.lyrics: List<String>` where each index is one verse-pass (0 = first time the section is heard, 1 = second pass, …). Empty string `""` = no lyric for that pass. List length is decoupled from `section.repeat` — UI clamps the editable count, but storage keeps whatever the user typed.
- Add `SongBlock.isSilent: bool` (default false). A **silent placeholder block** has `isSilent: true`, all chord fields null, and (typically) at least one non-empty lyric. Rendered in the bar grid as a dim dot/dash cell that carries lyrics underneath.
- Replace the `section_lyrics_sheet.dart` editor with inline lyric inputs inside `harmony_chord_sheet.dart`. The harmony sheet gains a "Silent placeholder" toggle that switches the picker into lyric-only mode.
- Sheet/track/classic variants render lyrics directly under their owning `_BarCell`, one stacked line per verse, aligned to the chord's bar span.

**Tech Stack:** Dart, Flutter, Riverpod, `flutter_test`. No new packages.

**Migration policy:** Existing `SongSection.lyrics` blobs are **discarded on load** (the feature shipped recently; assume no production lyrics in user data). JSON fromJson silently drops the old `lyrics` key.

**Non-goals (deferred):**
- Bar-quantized syllable markers / melismatic alignment within a chord cell.
- Per-block multi-instrument lyric translations (e.g. backing-vocal layer).
- Karaoke / playback-time scroll.
- Repeat-count-aware auto-resizing of the verse list (UI clamps editing; storage keeps user input verbatim).
- Save-lane / drum-lane lyrics (lyrics live on harmony blocks only).

---

## File Structure

**Created:**
- `test/models/song_block_lyrics_test.dart`
- `test/models/song_block_silent_test.dart`
- `test/store/songwriter_block_lyrics_test.dart`
- `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
- `test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`

**Modified:**
- `lib/models/songwriter.dart` — remove `SongSection.lyrics` + related `copyWith` flag; add `SongBlock.lyrics`, `SongBlock.isSilent`, factories' JSON.
- `lib/schema/rules/songwriter_rules.dart` — extend `makeHarmonyBlock` with optional `lyrics`; add `makeSilentBlock`.
- `lib/store/songwriter_store.dart` — remove `setSectionLyrics`; add `setBlockLyric(sectionId, laneId, blockId, verseIndex, String?)`, `setBlockLyrics(sectionId, laneId, blockId, List<String>)`, `addSilentBlock(...)`.
- `lib/features/songwriter/harmony_chord_sheet.dart` — add lyric inputs (N inputs based on the owning section's `repeat`) + "Silent placeholder" toggle.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — replace `_LyricsBlock` with `_BarCell` lyric stacking; route empty-cell tap to a chord-or-silent picker.
- `lib/features/songwriter/songwriter_block_tile.dart` — render lyrics under the chord glyph (track variant).
- `lib/features/songwriter/songwriter_section_card.dart` — replace `_ClassicLyricsRow` with per-block rendering.
- `lib/features/songwriter/songwriter_lane_row.dart` — pass-through changes for silent-block rendering.

**Deleted:**
- `lib/features/songwriter/section_lyrics_sheet.dart`
- `test/features/songwriter/section_lyrics_sheet_test.dart`
- `test/features/songwriter/songwriter_lyrics_render_test.dart` (superseded by new alignment test)

---

## Task 1: Remove `SongSection.lyrics`

**Files:**
- Modify: `lib/models/songwriter.dart` (`SongSection` class around line 277)
- Test: existing `test/models/song_section_lyrics_test.dart` will fail — that's intentional. Delete it after the model change.

- [ ] **Step 1: Delete the now-obsolete tests**

```bash
git rm test/models/song_section_lyrics_test.dart
```

- [ ] **Step 2: Strip `lyrics` from `SongSection`**

In `lib/models/songwriter.dart`, remove:
- the `final String? lyrics;` field,
- the `this.lyrics` constructor param,
- the `lyrics:` line in `copyWith`,
- the `clearLyrics` bool param + branches,
- the `'lyrics'` key in `toJson()`,
- the `lyrics:` line in `fromJson()`.

`fromJson` silently ignores any legacy `lyrics` key in stored JSON (Dart maps tolerate extra keys).

- [ ] **Step 3: Strip the store mutator**

In `lib/store/songwriter_store.dart`, remove the `setSectionLyrics` method entirely.

- [ ] **Step 4: Verify the project compiles**

Run: `flutter analyze lib/`
Expected: errors only at the call sites of `setSectionLyrics` / `section.lyrics` (handled in Task 5+). Note them and continue.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(songwriter): drop SongSection.lyrics in favor of per-block lyrics"
```

---

## Task 2: Add `lyrics` + `isSilent` to `SongBlock`

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

  test('copyWith can toggle isSilent', () {
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
Expected: FAIL — `lyrics`, `isSilent` undefined on `SongBlock`.

- [ ] **Step 3: Add the fields**

In `lib/models/songwriter.dart`, update `SongBlock`. Final shape:

```dart
class SongBlock {
  final String id;
  final int startBar;
  final int spanBars;

  // save-lane reference
  final String? saveId;
  final InstrumentSnapshot? embedded;

  // harmony-lane extras (null on save / silent blocks)
  final String? chordSymbol;
  final String? chordQuality;
  final int? chordRootPc;
  final List<String> chordNotes;
  final String? romanNumeral;

  // drum-lane reference
  final String? patternId;

  // lyric-bearing fields (any harmony / silent block can carry lyrics)
  final List<String> lyrics;
  final bool isSilent;

  const SongBlock({
    required this.id,
    required this.startBar,
    required this.spanBars,
    this.saveId,
    this.embedded,
    this.chordSymbol,
    this.chordQuality,
    this.chordRootPc,
    this.chordNotes = const [],
    this.romanNumeral,
    this.patternId,
    this.lyrics = const [],
    this.isSilent = false,
  });

  int get endBar => startBar + spanBars;

  SongBlock copyWith({
    int? startBar,
    int? spanBars,
    String? saveId,
    InstrumentSnapshot? embedded,
    String? chordSymbol,
    String? chordQuality,
    int? chordRootPc,
    List<String>? chordNotes,
    String? romanNumeral,
    String? patternId,
    List<String>? lyrics,
    bool? isSilent,
    bool clearRomanNumeral = false,
    bool clearSaveId = false,
    bool clearEmbedded = false,
    bool clearPatternId = false,
  }) => SongBlock(
    id: id,
    startBar: startBar ?? this.startBar,
    spanBars: spanBars ?? this.spanBars,
    saveId: clearSaveId ? null : (saveId ?? this.saveId),
    embedded: clearEmbedded ? null : (embedded ?? this.embedded),
    chordSymbol: chordSymbol ?? this.chordSymbol,
    chordQuality: chordQuality ?? this.chordQuality,
    chordRootPc: chordRootPc ?? this.chordRootPc,
    chordNotes: chordNotes ?? this.chordNotes,
    romanNumeral: clearRomanNumeral ? null : (romanNumeral ?? this.romanNumeral),
    patternId: clearPatternId ? null : (patternId ?? this.patternId),
    lyrics: lyrics ?? this.lyrics,
    isSilent: isSilent ?? this.isSilent,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startBar': startBar,
    'spanBars': spanBars,
    'saveId': saveId,
    'embedded': embedded?.toJson(),
    'chordSymbol': chordSymbol,
    'chordQuality': chordQuality,
    'chordRootPc': chordRootPc,
    'chordNotes': chordNotes,
    'romanNumeral': romanNumeral,
    'patternId': patternId,
    'lyrics': lyrics,
    'isSilent': isSilent,
  };

  factory SongBlock.fromJson(Map<String, dynamic> json) => SongBlock(
    id: json['id'] as String,
    startBar: json['startBar'] as int? ?? 0,
    spanBars: json['spanBars'] as int? ?? 1,
    saveId: json['saveId'] as String?,
    embedded: json['embedded'] == null
        ? null
        : InstrumentSnapshot.fromJson(json['embedded'] as Map<String, dynamic>),
    chordSymbol: json['chordSymbol'] as String?,
    chordQuality: json['chordQuality'] as String?,
    chordRootPc: json['chordRootPc'] as int?,
    chordNotes:
        (json['chordNotes'] as List?)?.map((e) => e as String).toList() ??
        const [],
    romanNumeral: json['romanNumeral'] as String?,
    patternId: json['patternId'] as String?,
    lyrics:
        (json['lyrics'] as List?)?.map((e) => e as String).toList() ??
        const [],
    isSilent: json['isSilent'] as bool? ?? false,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/models/song_block_lyrics_test.dart test/models/song_block_silent_test.dart`
Expected: PASS (7/7).

- [ ] **Step 5: Run all model tests**

Run: `flutter test test/models/`
Expected: PASS — existing block tests still green (additive fields).

- [ ] **Step 6: Commit**

```bash
git add lib/models/songwriter.dart test/models/song_block_lyrics_test.dart test/models/song_block_silent_test.dart
git commit -m "feat(songwriter): add SongBlock.lyrics list and isSilent flag"
```

---

## Task 3: Factory + store mutators for lyrics and silent blocks

**Files:**
- Modify: `lib/schema/rules/songwriter_rules.dart` (after `makeHarmonyBlock` at line 159)
- Modify: `lib/store/songwriter_store.dart`
- Test: `test/store/songwriter_block_lyrics_test.dart`

- [ ] **Step 1: Write failing tests**

`test/store/songwriter_block_lyrics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/schema/rules/songwriter_rules.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('makeSilentBlock sets isSilent and seeds an empty lyric line', () {
    final b = makeSilentBlock(startBar: 2, spanBars: 1, verseCount: 2);
    expect(b.isSilent, isTrue);
    expect(b.chordSymbol, isNull);
    expect(b.lyrics, ['', '']);
    expect(b.startBar, 2);
  });

  test('setBlockLyric writes one verse and leaves others untouched', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;

    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 1,
      text: 'second verse line',
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics.length, 2);
    expect(block.lyrics[0], '');
    expect(block.lyrics[1], 'second verse line');
  });

  test('setBlockLyric clears the verse when text is null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;
    n.addHarmonyBlock(
      sectionId: sectionId,
      laneId: laneId,
      block: makeHarmonyBlock(
        startBar: 0,
        spanBars: 1,
        chordSymbol: 'C',
        chordQuality: '',
        chordRootPc: 0,
        chordNotes: const ['C', 'E', 'G'],
      ),
    );
    final blockId = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single.id;

    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: 'temp',
    );
    n.setBlockLyric(
      sectionId: sectionId,
      laneId: laneId,
      blockId: blockId,
      verseIndex: 0,
      text: null,
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.lyrics, isEmpty);
  });

  test('addSilentBlock places a silent block on the harmony lane', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Verse', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.first.id;
    n.addLane(
      sectionId: sectionId,
      kind: SongLaneKind.harmony,
      label: 'Harmony',
    );
    final laneId = container.read(songwriterProvider)
        .sections.first.lanes.first.id;

    n.addSilentBlock(
      sectionId: sectionId,
      laneId: laneId,
      startBar: 2,
      spanBars: 1,
    );

    final block = container.read(songwriterProvider)
        .sections.first.lanes.first.blocks.single;
    expect(block.isSilent, isTrue);
    expect(block.chordSymbol, isNull);
    expect(block.startBar, 2);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/store/songwriter_block_lyrics_test.dart`
Expected: FAIL — `makeSilentBlock`, `setBlockLyric`, `addSilentBlock` undefined.

- [ ] **Step 3: Add factory + mutators**

Append to `lib/schema/rules/songwriter_rules.dart` after `makeHarmonyBlock`:

```dart
SongBlock makeSilentBlock({
  required int startBar,
  required int spanBars,
  int verseCount = 1,
}) => SongBlock(
  id: generateId(),
  startBar: startBar,
  spanBars: spanBars,
  isSilent: true,
  lyrics: List<String>.filled(verseCount.clamp(1, 16), ''),
);
```

In `lib/store/songwriter_store.dart`, add the mutators in the block section (next to `addHarmonyBlock`):

```dart
void setBlockLyric({
  required String sectionId,
  required String laneId,
  required String blockId,
  required int verseIndex,
  required String? text,
}) {
  if (verseIndex < 0) return;
  _replaceLane(sectionId, laneId, (l) => l.copyWith(
    blocks: l.blocks.map((b) {
      if (b.id != blockId) return b;
      final list = [...b.lyrics];
      while (list.length <= verseIndex) {
        list.add('');
      }
      list[verseIndex] = text ?? '';
      while (list.isNotEmpty && list.last.isEmpty) {
        list.removeLast();
      }
      return b.copyWith(lyrics: list);
    }).toList(),
  ));
}

void addSilentBlock({
  required String sectionId,
  required String laneId,
  required int startBar,
  required int spanBars,
  int verseCount = 1,
}) {
  _replaceLane(sectionId, laneId, (l) => l.copyWith(
    blocks: [
      ...l.blocks,
      makeSilentBlock(
        startBar: startBar,
        spanBars: spanBars,
        verseCount: verseCount,
      ),
    ],
  ));
}
```

Verify `_replaceLane` exists in the store (it does — search for `void _replaceLane(`). If the existing mutator uses a different name, reuse the pattern from `addHarmonyBlock`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/store/songwriter_block_lyrics_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Run the full songwriter store suite**

Run: `flutter test test/store/songwriter_*.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/schema/rules/songwriter_rules.dart lib/store/songwriter_store.dart test/store/songwriter_block_lyrics_test.dart
git commit -m "feat(songwriter): block-level lyrics + silent-block mutators"
```

---

## Task 4: Add lyric inputs and silent toggle to harmony chord sheet

**Files:**
- Modify: `lib/features/songwriter/harmony_chord_sheet.dart`
- Test: `test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`

- [ ] **Step 1: Extend the sheet entrypoint signature**

The current `showHarmonyChordSheet` takes `startBar`, `spanBars`, `keyRoot`, `keyScaleName`. Extend it:

```dart
Future<SongBlock?> showHarmonyChordSheet(
  BuildContext context, {
  required int startBar,
  required int spanBars,
  required int? keyRoot,
  required String? keyScaleName,
  SongBlock? existing,
  int verseCount = 1,
});
```

`existing` is the block being edited (null when adding). `verseCount` is the section's `repeat` value (clamped to ≥ 1).

- [ ] **Step 2: Write failing widget tests**

`test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/harmony_chord_sheet.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  testWidgets('renders N lyric inputs for verseCount', (tester) async {
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
                  verseCount: 3,
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

    expect(find.byKey(const Key('lyricInput_0')), findsOneWidget);
    expect(find.byKey(const Key('lyricInput_1')), findsOneWidget);
    expect(find.byKey(const Key('lyricInput_2')), findsOneWidget);
  });

  testWidgets('silent toggle returns a silent block with lyrics intact',
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
                  verseCount: 1,
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

    await tester.enterText(find.byKey(const Key('lyricInput_0')), 'oh');
    await tester.tap(find.byKey(const Key('confirmSilent')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isSilent, isTrue);
    expect(result!.chordSymbol, isNull);
    expect(result!.lyrics, ['oh']);
    expect(result!.startBar, 1);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
Expected: FAIL — keys missing, `verseCount` param missing.

- [ ] **Step 4: Implement**

In `harmony_chord_sheet.dart`:

1. Add `verseCount` and `existing` params to `showHarmonyChordSheet` and forward them to `_HarmonySheet`.
2. Add state to `_HarmonySheetState`:

```dart
bool _silentMode = false;
late final List<TextEditingController> _lyricControllers;

@override
void initState() {
  super.initState();
  _silentMode = widget.existing?.isSilent ?? false;
  final seeds = widget.existing?.lyrics ?? const <String>[];
  _lyricControllers = List.generate(
    widget.verseCount.clamp(1, 16),
    (i) => TextEditingController(text: i < seeds.length ? seeds[i] : ''),
  );
}

@override
void dispose() {
  for (final c in _lyricControllers) {
    c.dispose();
  }
  super.dispose();
}

List<String> _collectLyrics() {
  final list = _lyricControllers.map((c) => c.text).toList();
  while (list.isNotEmpty && list.last.isEmpty) {
    list.removeLast();
  }
  return list;
}
```

3. Render a `Switch`/`SwitchListTile` near the top of the sheet body:

```dart
SwitchListTile(
  key: const Key('silentToggle'),
  title: const Text('Silent placeholder (lyrics only)'),
  subtitle: const Text('No chord — useful for instrumental or vocal-only bars.'),
  value: _silentMode,
  onChanged: (v) => setState(() => _silentMode = v),
),
```

4. Render lyric inputs below the chord picker / silent body:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < _lyricControllers.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TextField(
            key: Key('lyricInput_$i'),
            controller: _lyricControllers[i],
            style: const TextStyle(color: MuzicianTheme.textPrimary),
            decoration: InputDecoration(
              labelText: widget.verseCount > 1 ? 'Verse ${i + 1}' : 'Lyrics',
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
    ],
  ),
),
```

5. When `_silentMode` is true: hide the chord picker UI, show only the lyric inputs + a confirm button keyed `confirmSilent`:

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
            lyrics: _collectLyrics(),
          ),
        );
      },
      child: const Text('Save placeholder'),
    ),
  ),
```

(Import `generateId` from `songwriter_rules.dart` if not already present.)

6. When the user picks a chord (existing path), wrap the returned `SongBlock` with `.copyWith(lyrics: _collectLyrics(), isSilent: false)` before popping.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_lyrics_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Run all existing harmony-sheet tests**

Run: `flutter test test/features/songwriter/harmony_chord_sheet_test.dart`
Expected: PASS (must remain green after the API addition — `verseCount` defaults to 1, `existing` defaults to null).

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/harmony_chord_sheet.dart test/features/songwriter/harmony_chord_sheet_lyrics_test.dart
git commit -m "feat(songwriter): lyric inputs + silent toggle in chord sheet"
```

---

## Task 5: Render lyrics under chord cells in Sheet variant

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (remove `_LyricsBlock`, embed lyrics inside `_BarCell`)
- Test: `test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`

- [ ] **Step 1: Delete obsolete files and tests**

```bash
git rm lib/features/songwriter/section_lyrics_sheet.dart
git rm test/features/songwriter/section_lyrics_sheet_test.dart
git rm test/features/songwriter/songwriter_lyrics_render_test.dart
```

- [ ] **Step 2: Write the failing alignment test**

`test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`:

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

  testWidgets('sheet renders multi-verse lyrics under the chord cell',
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

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('goodbye'), findsOneWidget);
  });

  testWidgets('sheet renders a silent placeholder cell with its lyric',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(songwriterProvider.notifier);

    n.addSection(label: 'Bridge', lengthBars: 2);
    final section = container.read(songwriterProvider).sections.first;
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
      verseCount: 1,
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    expect(find.byKey(Key('silentCell_$blockId')), findsOneWidget);
    expect(find.text('(ahh)'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
Expected: FAIL.

- [ ] **Step 4: Update `_SectionSheet` build**

In `songwriter_screen_sheet.dart`:

1. Remove the import of `section_lyrics_sheet.dart`.
2. Remove the entire `_LyricsBlock` widget class.
3. In `_SectionSheet.build`, remove the `_LyricsBlock` invocation; the build returns:

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    _SectionHeading(section: section),
    const SizedBox(height: 14),
    _BarRow(
      section: section,
      lane: harmonyLane,
      keyRoot: config.keyRoot,
      keyScaleName: config.keyScaleName,
      onEnsureLane: () => notifier.addLane(
        sectionId: sectionId,
        kind: SongLaneKind.harmony,
        label: 'Harmony',
      ),
    ),
    if (section.lanes.any((l) => l.kind == SongLaneKind.save)) ...[
      // existing save-lane chip strip unchanged
    ],
  ],
);
```

- [ ] **Step 5: Update `_BarCell` to render lyrics and silent state**

Locate `_BarCell` (search for `class _BarCell` in the file). Augment its `build` to render a `Column` instead of a single chord glyph:

```dart
@override
Widget build(BuildContext context) {
  final block = this.block;
  final lyrics = block?.lyrics ?? const <String>[];
  final isSilent = block?.isSilent ?? false;
  return Expanded(
    flex: flex,
    child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // existing cell decoration — keep as-is
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (block == null)
              const Text(
                '·',
                style: TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 18,
                ),
              )
            else if (isSilent)
              Container(
                key: Key('silentCell_${block.id}'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MuzicianTheme.textMuted,
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
            if (lyrics.isNotEmpty) const SizedBox(height: 4),
            for (final line in lyrics)
              Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
```

(Preserve the existing decoration / hit-test behavior — only the inner widget tree changes.)

- [ ] **Step 6: Empty-cell tap now offers chord OR silent**

In `_BarRow._addAt`, replace the single `showHarmonyChordSheet` call with a dispatch sheet. Simplest path: keep `showHarmonyChordSheet` as the single entry, and let the user toggle silent inside it. The empty-cell tap stays one tap → one sheet.

Pass the section's `repeat` as `verseCount`:

```dart
final section = ref.read(songwriterProvider).sections
    .firstWhere((s) => s.id == this.section.id);
final block = await showHarmonyChordSheet(
  context,
  startBar: bar,
  spanBars: 1,
  keyRoot: keyRoot,
  keyScaleName: keyScaleName,
  verseCount: section.repeat.clamp(1, 16),
);
if (block == null) return;
if (block.isSilent) {
  ref.read(songwriterProvider.notifier).addSilentBlock(
        sectionId: section.id,
        laneId: laneId,
        startBar: bar,
        spanBars: 1,
        verseCount: section.repeat.clamp(1, 16),
      );
  // Then write each lyric so the test's setBlockLyric flow stays consistent.
  final newBlockId = ref.read(songwriterProvider)
      .sections.firstWhere((s) => s.id == section.id)
      .lanes.firstWhere((l) => l.id == laneId)
      .blocks.lastWhere((b) => b.startBar == bar).id;
  for (var i = 0; i < block.lyrics.length; i++) {
    ref.read(songwriterProvider.notifier).setBlockLyric(
          sectionId: section.id,
          laneId: laneId,
          blockId: newBlockId,
          verseIndex: i,
          text: block.lyrics[i],
        );
  }
  return;
}
// existing chord-add path
ref.read(songwriterProvider.notifier).addHarmonyBlock(
      sectionId: section.id,
      laneId: laneId,
      block: block,
    );
```

(The existing `_editBlock` should mirror this — passing `existing: block` and `verseCount: section.repeat` to `showHarmonyChordSheet`, then applying the returned `lyrics` via `setBlockLyric` per index.)

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
Expected: PASS (2/2).

- [ ] **Step 8: Run the full songwriter feature suite**

Run: `flutter test test/features/songwriter/`
Expected: PASS — the removed lyrics-render test files are gone; all others stay green.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(songwriter): render per-block multi-verse lyrics in sheet variant"
```

---

## Task 6: Render lyrics in Track variant (`songwriter_block_tile.dart`)

**Files:**
- Modify: `lib/features/songwriter/songwriter_block_tile.dart`
- Test: extend `songwriter_sheet_lyrics_alignment_test.dart` with a track-variant case (add a new test inside the same `main()`).

- [ ] **Step 1: Add failing test**

Append to `songwriter_sheet_lyrics_alignment_test.dart`:

```dart
import 'package:muzician/features/songwriter/songwriter_screen_track.dart';

testWidgets('track variant renders lyrics under the chord tile',
    (tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final n = container.read(songwriterProvider.notifier);

  n.addSection(label: 'Verse', lengthBars: 4);
  final section = container.read(songwriterProvider).sections.first;
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
    ).copyWith(lyrics: ['hello']),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SongwriterScreenTrack()),
    ),
  );
  await tester.pump();

  expect(find.text('hello'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
Expected: FAIL on the track variant case.

- [ ] **Step 3: Implement**

In `songwriter_block_tile.dart`, locate the chord tile (search for `chordSymbol`). Wrap its child in a `Column` and append a lyric stack identical to the Sheet `_BarCell` approach:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    // existing chord glyph row
    if (block.lyrics.isNotEmpty) const SizedBox(height: 4),
    for (final line in block.lyrics)
      Text(
        line,
        style: const TextStyle(
          color: MuzicianTheme.textSecondary,
          fontSize: 11,
          height: 1.2,
        ),
      ),
  ],
),
```

If the tile already renders a `Container` with a fixed height, expand it to use intrinsic height so lyrics can stack.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/songwriter_block_tile.dart test/features/songwriter/songwriter_sheet_lyrics_alignment_test.dart
git commit -m "feat(songwriter): render per-block lyrics in track variant"
```

---

## Task 7: Render lyrics in Classic variant + remove `_ClassicLyricsRow`

**Files:**
- Modify: `lib/features/songwriter/songwriter_section_card.dart`

- [ ] **Step 1: Remove the old lyrics row**

Delete the `_ClassicLyricsRow` widget class and its invocation. Remove the `import 'section_lyrics_sheet.dart';` line if it's still present.

- [ ] **Step 2: Reuse the block tile**

Classic already renders `songwriter_block_tile.dart` (or the equivalent classic tile widget) for each block — the Task 6 changes carry over for free. If Classic uses its own tile widget, mirror the lyric stack from Task 6.

- [ ] **Step 3: Manual smoke**

Run: `flutter run -d <device>`
- Add a chord with lyric in each layout variant — confirm alignment.
- Toggle silent mode in the chord sheet — confirm dot cell appears with lyric stacked beneath.
- Set `section.repeat = 3`, add a chord, type three verse lines — confirm three lines render under the chord cell.
- Hot restart — confirm persistence via debounced session save.

- [ ] **Step 4: Commit**

```bash
git add lib/features/songwriter/songwriter_section_card.dart
git commit -m "feat(songwriter): drop classic lyrics row in favor of per-block lyrics"
```

---

## Task 8: Repeat-aware verse defaults and full-suite verification

**Files:**
- Modify: `lib/store/songwriter_store.dart` — make `setSectionRepeat` grow each block's `lyrics` list to match the new repeat count (additive only — do not shrink).

- [ ] **Step 1: Failing test**

Append to `test/store/songwriter_block_lyrics_test.dart`:

```dart
test('setSectionRepeat grows lyrics list on each harmony block', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final n = container.read(songwriterProvider.notifier);

  n.addSection(label: 'Verse', lengthBars: 4);
  final sectionId = container.read(songwriterProvider).sections.first.id;
  n.addLane(
    sectionId: sectionId,
    kind: SongLaneKind.harmony,
    label: 'Harmony',
  );
  final laneId = container.read(songwriterProvider)
      .sections.first.lanes.first.id;
  n.addHarmonyBlock(
    sectionId: sectionId,
    laneId: laneId,
    block: makeHarmonyBlock(
      startBar: 0,
      spanBars: 1,
      chordSymbol: 'C',
      chordQuality: '',
      chordRootPc: 0,
      chordNotes: const ['C', 'E', 'G'],
    ).copyWith(lyrics: ['first']),
  );

  n.setSectionRepeat(sectionId, 3);

  final block = container.read(songwriterProvider)
      .sections.first.lanes.first.blocks.single;
  expect(block.lyrics, ['first', '', '']);
});

test('setSectionRepeat does NOT shrink existing lyrics', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final n = container.read(songwriterProvider.notifier);

  n.addSection(label: 'Verse', lengthBars: 4);
  final sectionId = container.read(songwriterProvider).sections.first.id;
  n.addLane(
    sectionId: sectionId,
    kind: SongLaneKind.harmony,
    label: 'Harmony',
  );
  final laneId = container.read(songwriterProvider)
      .sections.first.lanes.first.id;
  n.addHarmonyBlock(
    sectionId: sectionId,
    laneId: laneId,
    block: makeHarmonyBlock(
      startBar: 0,
      spanBars: 1,
      chordSymbol: 'C',
      chordQuality: '',
      chordRootPc: 0,
      chordNotes: const ['C', 'E', 'G'],
    ).copyWith(lyrics: ['a', 'b', 'c']),
  );

  n.setSectionRepeat(sectionId, 1);

  final block = container.read(songwriterProvider)
      .sections.first.lanes.first.blocks.single;
  expect(block.lyrics, ['a', 'b', 'c']);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/store/songwriter_block_lyrics_test.dart`
Expected: FAIL — `setSectionRepeat` does not yet touch block lyrics.

- [ ] **Step 3: Patch `setSectionRepeat`**

In `songwriter_store.dart`, replace:

```dart
void setSectionRepeat(String sectionId, int repeat) => _replaceSection(
  sectionId,
  (s) => s.copyWith(repeat: repeat < 1 ? 1 : repeat),
);
```

with:

```dart
void setSectionRepeat(String sectionId, int repeat) {
  final clamped = repeat < 1 ? 1 : repeat;
  _replaceSection(sectionId, (s) {
    final lanes = s.lanes.map((l) {
      if (l.kind != SongLaneKind.harmony) return l;
      final blocks = l.blocks.map((b) {
        if (b.lyrics.length >= clamped) return b;
        final padded = [
          ...b.lyrics,
          for (var i = b.lyrics.length; i < clamped; i++) '',
        ];
        return b.copyWith(lyrics: padded);
      }).toList();
      return l.copyWith(blocks: blocks);
    }).toList();
    return s.copyWith(repeat: clamped, lanes: lanes);
  });
}
```

Lists grow, never shrink — preserves typed lyrics when the user later lowers the repeat count.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/store/songwriter_block_lyrics_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite**

Run: `flutter test`
Expected: PASS. Then `flutter analyze` → 0 new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_block_lyrics_test.dart
git commit -m "feat(songwriter): grow block lyrics list when section repeat increases"
```

---

## Self-Review Notes

- **Spec coverage:** chord-anchored lyrics on `SongBlock` (Tasks 2-3); silent placeholder block type (Tasks 2-3, exposed in Task 4); multi-verse lyric inputs in chord sheet (Task 4); per-cell rendering in sheet/track/classic (Tasks 5-7); repeat-aware verse list growth (Task 8); old `SongSection.lyrics` cleanly removed (Task 1) with its editor + tests deleted (Task 5).
- **`SongSection.lyrics` JSON migration:** legacy stored blobs ignored — non-destructive read, no user-visible upgrade dialog.
- **Naming consistency:** `lyrics` (List), `isSilent`, `setBlockLyric`, `addSilentBlock`, `makeSilentBlock`, `verseCount`. Identical across model/store/UI.
- **Theme tokens:** verified `MuzicianTheme.textPrimary` / `textSecondary` / `textMuted` / `glassBg` / `glassBorder` / `surface` all exist (see `lib/theme/muzician_theme.dart`).
- **No shrink on repeat-down:** intentional. Preserves user input across exploratory repeat changes.
- **No syllable / beat-level alignment.** Bar-aligned chord cell is the alignment unit. Future-friendly: lyric `String` per verse can later be replaced with a structured token list without touching the editor's outer flow.
