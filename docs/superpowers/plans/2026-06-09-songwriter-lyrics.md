# Songwriter Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-section free-text lyrics to Songwriter projects, rendered primarily under the lead-sheet bar row in the Sheet variant and as a collapsible block in Track/Classic variants.

**Architecture:** Lyrics live on `SongSection` as a nullable `String?` (whole-section text blob, not bar-quantized). Persistence rides existing `SongSection` JSON round-trip. A new mutator `setSectionLyrics` on `SongwriterNotifier` writes through the standard debounced session save. UI: a single shared editor sheet (`section_lyrics_sheet.dart`) reused across all three layout variants; rendering is variant-specific.

**Tech Stack:** Dart, Flutter, Riverpod (`flutter_riverpod`), `flutter_test`, `shared_preferences` (existing session store).

**Non-goals (deferred):**
- Bar-quantized syllable alignment (e.g. `[C]wo[F]rd` inline markers).
- Multi-verse stanzas per section (single text blob for now; newlines free).
- Playback karaoke/highlight sync.

---

## File Structure

**Created:**
- `lib/features/songwriter/section_lyrics_sheet.dart` — modal multiline editor opened from each layout's section heading.
- `test/models/song_section_lyrics_test.dart` — round-trip + copyWith tests for the new field.
- `test/store/songwriter_lyrics_test.dart` — `setSectionLyrics` mutator tests.
- `test/features/songwriter/songwriter_lyrics_render_test.dart` — widget tests for sheet/track rendering and edit-entry tap.

**Modified:**
- `lib/models/songwriter.dart` — add `lyrics` field to `SongSection` (constructor, `copyWith`, `toJson`, `fromJson`).
- `lib/store/songwriter_store.dart` — add `setSectionLyrics(sectionId, String? lyrics)` mutator.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — render lyrics below `_BarRow`; add tap-to-edit affordance.
- `lib/features/songwriter/songwriter_screen_track.dart` — render lyrics inside section strip (small collapsible block).
- `lib/features/songwriter/songwriter_section_card.dart` — render lyrics in Classic variant card footer.

No file moves. Each task below is independently committable.

---

## Task 1: Add `lyrics` field to `SongSection` model

**Files:**
- Modify: `lib/models/songwriter.dart` (constructor at 285, `copyWith` at 294, `toJson` at 310, `fromJson` at 319)
- Test: `test/models/song_section_lyrics_test.dart`

- [ ] **Step 1: Write the failing test**

`test/models/song_section_lyrics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('section round-trips with lyrics field', () {
    const section = SongSection(
      id: 's1',
      lengthBars: 8,
      order: 0,
      lyrics: 'Hello darkness my old friend\nIve come to talk',
    );
    final back = SongSection.fromJson(section.toJson());
    expect(back.lyrics, section.lyrics);
  });

  test('section defaults lyrics to null', () {
    const section = SongSection(id: 's2', lengthBars: 4, order: 0);
    expect(section.lyrics, isNull);
  });

  test('copyWith clears lyrics when clearLyrics: true', () {
    const section = SongSection(
      id: 's3',
      lengthBars: 4,
      order: 0,
      lyrics: 'first take',
    );
    final cleared = section.copyWith(clearLyrics: true);
    expect(cleared.lyrics, isNull);
  });

  test('copyWith preserves lyrics when not set', () {
    const section = SongSection(
      id: 's4',
      lengthBars: 4,
      order: 0,
      lyrics: 'verse one',
    );
    final next = section.copyWith(lengthBars: 8);
    expect(next.lyrics, 'verse one');
    expect(next.lengthBars, 8);
  });

  test('fromJson tolerates missing lyrics key', () {
    final back = SongSection.fromJson({
      'id': 's5',
      'lengthBars': 4,
      'order': 0,
    });
    expect(back.lyrics, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/song_section_lyrics_test.dart`
Expected: FAIL with "The named parameter 'lyrics' isn't defined" on the `SongSection` constructor.

- [ ] **Step 3: Add `lyrics` to `SongSection`**

Edit `lib/models/songwriter.dart`. In the `SongSection` class, add the field, constructor param, `copyWith` param + `clearLyrics`, JSON read/write. Final class body:

```dart
class SongSection {
  final String id;
  final String? label; // optional free text
  final int lengthBars;
  final int order;
  final int repeat; // loops the whole section N times
  final String? lyrics; // free-text lyrics for the whole section
  final List<SongLane> lanes;

  const SongSection({
    required this.id,
    required this.lengthBars,
    required this.order,
    this.label,
    this.repeat = 1,
    this.lyrics,
    this.lanes = const [],
  });

  SongSection copyWith({
    String? label,
    int? lengthBars,
    int? order,
    int? repeat,
    String? lyrics,
    List<SongLane>? lanes,
    bool clearLabel = false,
    bool clearLyrics = false,
  }) => SongSection(
    id: id,
    label: clearLabel ? null : (label ?? this.label),
    lengthBars: lengthBars ?? this.lengthBars,
    order: order ?? this.order,
    repeat: repeat ?? this.repeat,
    lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
    lanes: lanes ?? this.lanes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'lengthBars': lengthBars,
    'order': order,
    'repeat': repeat,
    'lyrics': lyrics,
    'lanes': lanes.map((l) => l.toJson()).toList(),
  };

  factory SongSection.fromJson(Map<String, dynamic> json) => SongSection(
    id: json['id'] as String,
    label: json['label'] as String?,
    lengthBars: json['lengthBars'] as int? ?? 4,
    order: json['order'] as int? ?? 0,
    repeat: json['repeat'] as int? ?? 1,
    lyrics: json['lyrics'] as String?,
    lanes:
        (json['lanes'] as List?)
            ?.map((l) => SongLane.fromJson(l as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/song_section_lyrics_test.dart`
Expected: PASS (5/5).

- [ ] **Step 5: Run existing section tests to confirm no regressions**

Run: `flutter test test/models/song_section_test.dart test/models/songwriter_snapshot_test.dart`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
git add lib/models/songwriter.dart test/models/song_section_lyrics_test.dart
git commit -m "feat(songwriter): add lyrics field to SongSection"
```

---

## Task 2: Add `setSectionLyrics` mutator to store

**Files:**
- Modify: `lib/store/songwriter_store.dart` (add mutator next to `renameSection` at ~104)
- Test: `test/store/songwriter_lyrics_test.dart`

- [ ] **Step 1: Write the failing test**

`test/store/songwriter_lyrics_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('setSectionLyrics writes lyrics on the target section only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    notifier.addSection(label: 'Chorus', lengthBars: 4);

    final verseId = container.read(songwriterProvider).sections.first.id;
    final chorusId = container.read(songwriterProvider).sections.last.id;

    notifier.setSectionLyrics(verseId, 'line one\nline two');

    final state = container.read(songwriterProvider);
    expect(state.sections.first.lyrics, 'line one\nline two');
    expect(state.sections.last.lyrics, isNull);
    expect(state.sections.last.id, chorusId);
  });

  test('setSectionLyrics with null clears lyrics', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final id = container.read(songwriterProvider).sections.first.id;

    notifier.setSectionLyrics(id, 'temp');
    notifier.setSectionLyrics(id, null);

    expect(container.read(songwriterProvider).sections.first.lyrics, isNull);
  });

  test('setSectionLyrics is a no-op when sectionId is unknown', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final before = container.read(songwriterProvider);

    notifier.setSectionLyrics('nonexistent', 'ignored');

    final after = container.read(songwriterProvider);
    expect(after.sections.length, before.sections.length);
    expect(after.sections.first.lyrics, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/store/songwriter_lyrics_test.dart`
Expected: FAIL with "The method 'setSectionLyrics' isn't defined".

- [ ] **Step 3: Add the mutator**

In `lib/store/songwriter_store.dart`, add this method directly below `renameSection` (currently ending around line 108):

```dart
void setSectionLyrics(String sectionId, String? lyrics) => _replaceSection(
  sectionId,
  (s) => (lyrics == null || lyrics.isEmpty)
      ? s.copyWith(clearLyrics: true)
      : s.copyWith(lyrics: lyrics),
);
```

Note: `_replaceSection` already short-circuits unknown ids by mapping over sections without matching — the third test passes without extra guards.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/store/songwriter_lyrics_test.dart`
Expected: PASS (3/3).

- [ ] **Step 5: Run all songwriter store tests for regressions**

Run: `flutter test test/store/songwriter_*.dart`
Expected: PASS, all green.

- [ ] **Step 6: Commit**

```bash
git add lib/store/songwriter_store.dart test/store/songwriter_lyrics_test.dart
git commit -m "feat(songwriter): setSectionLyrics store mutator"
```

---

## Task 3: Shared lyrics editor sheet widget

**Files:**
- Create: `lib/features/songwriter/section_lyrics_sheet.dart`
- Test: `test/features/songwriter/section_lyrics_sheet_test.dart`

- [ ] **Step 1: Write the failing widget test**

`test/features/songwriter/section_lyrics_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/section_lyrics_sheet.dart';

void main() {
  testWidgets('editor prefills with current lyrics and returns trimmed text',
      (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showSectionLyricsSheet(
                  context: ctx,
                  initial: 'verse one\n',
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

    final field = find.byKey(const Key('sectionLyricsField'));
    expect(field, findsOneWidget);
    final TextField widget = tester.widget(field);
    expect(widget.controller!.text, 'verse one\n');

    await tester.enterText(field, 'verse one\nverse two\n');
    await tester.tap(find.byKey(const Key('sectionLyricsSave')));
    await tester.pumpAndSettle();

    expect(captured, 'verse one\nverse two');
  });

  testWidgets('clear button returns null', (tester) async {
    String? captured = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                captured = await showSectionLyricsSheet(
                  context: ctx,
                  initial: 'existing',
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
    await tester.tap(find.byKey(const Key('sectionLyricsClear')));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/section_lyrics_sheet_test.dart`
Expected: FAIL — file `section_lyrics_sheet.dart` does not exist.

- [ ] **Step 3: Create the editor widget**

`lib/features/songwriter/section_lyrics_sheet.dart`:

```dart
/// Modal bottom sheet for editing a section's lyrics blob.
///
/// Returns the new lyrics string (trimmed of trailing whitespace) on save,
/// or `null` if the user cleared the text or dismissed the sheet.
library;

import 'package:flutter/material.dart';

import '../_mockup_shell.dart';

Future<String?> showSectionLyricsSheet({
  required BuildContext context,
  String? initial,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  String? result;
  await showWidgetSheet(
    context: context,
    title: 'Lyrics',
    child: _SectionLyricsBody(
      controller: controller,
      onSave: (text) {
        result = text.trimRight().isEmpty ? null : text.trimRight();
        Navigator.of(context).pop();
      },
      onClear: () {
        result = null;
        Navigator.of(context).pop();
      },
    ),
  );
  controller.dispose();
  return result;
}

class _SectionLyricsBody extends StatelessWidget {
  const _SectionLyricsBody({
    required this.controller,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final void Function(String text) onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('sectionLyricsField'),
            controller: controller,
            minLines: 4,
            maxLines: 10,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Type lyrics for this section…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                key: const Key('sectionLyricsClear'),
                onPressed: onClear,
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('sectionLyricsSave'),
                onPressed: () => onSave(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/section_lyrics_sheet_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Commit**

```bash
git add lib/features/songwriter/section_lyrics_sheet.dart test/features/songwriter/section_lyrics_sheet_test.dart
git commit -m "feat(songwriter): section lyrics editor sheet"
```

---

## Task 4: Render lyrics in Sheet variant

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (`_SectionSheet.build` ~ line 123; add `_LyricsBlock` widget at file bottom)
- Test: `test/features/songwriter/songwriter_lyrics_render_test.dart`

- [ ] **Step 1: Write the failing widget test**

`test/features/songwriter/songwriter_lyrics_render_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:muzician/features/songwriter/songwriter_screen_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';
import 'package:muzician/store/settings_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('sheet variant renders lyrics below bar row when present',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(songwriterProvider.notifier);
    notifier.addSection(label: 'Verse', lengthBars: 4);
    final id = container.read(songwriterProvider).sections.first.id;
    notifier.setSectionLyrics(id, 'hello sun\nyou shine bright');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    expect(find.text('hello sun\nyou shine bright'), findsOneWidget);
  });

  testWidgets('sheet variant shows lyrics affordance placeholder when empty',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songwriterProvider.notifier)
        .addSection(label: 'Verse', lengthBars: 4);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SongwriterScreenSheet()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('sectionLyricsAdd')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: FAIL — lyrics text not found / `sectionLyricsAdd` key missing.

- [ ] **Step 3: Render lyrics in `_SectionSheet`**

Edit `lib/features/songwriter/songwriter_screen_sheet.dart`. Add the import at top:

```dart
import 'section_lyrics_sheet.dart';
```

In `_SectionSheet.build`, after the existing `_BarRow` block and before the save-lane chip wrap, insert the lyrics block. The full updated `return` becomes:

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
    const SizedBox(height: 10),
    _LyricsBlock(
      sectionId: sectionId,
      lyrics: section.lyrics,
    ),
    if (section.lanes.any((l) => l.kind == SongLaneKind.save)) ...[
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final lane
                in section.lanes.where((l) => l.kind == SongLaneKind.save))
              _SaveLaneChip(
                label: lane.label ?? 'Save',
                count: lane.blocks.length,
              ),
          ],
        ),
      ),
    ],
  ],
);
```

At the bottom of the file, add the widget:

```dart
class _LyricsBlock extends ConsumerWidget {
  const _LyricsBlock({required this.sectionId, required this.lyrics});

  final String sectionId;
  final String? lyrics;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showSectionLyricsSheet(
      context: context,
      initial: lyrics,
    );
    ref.read(songwriterProvider.notifier).setSectionLyrics(sectionId, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = lyrics != null && lyrics!.trim().isNotEmpty;
    if (!has) {
      return GestureDetector(
        key: const Key('sectionLyricsAdd'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _edit(context, ref),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            '+ lyrics',
            style: TextStyle(
              color: MuzicianTheme.textMuted,
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      key: Key('sectionLyrics_$sectionId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 4, right: 4, bottom: 2),
        child: Text(
          lyrics!,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
```

Note: if `MuzicianTheme.textMuted` does not exist, substitute `MuzicianTheme.textSecondary` (whichever low-contrast color the codebase already exposes — grep `theme/muzician_theme.dart`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Run all sheet/screen tests for regressions**

Run: `flutter test test/features/songwriter/`
Expected: PASS, all green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_sheet.dart test/features/songwriter/songwriter_lyrics_render_test.dart
git commit -m "feat(songwriter): render lyrics block in sheet variant"
```

---

## Task 5: Render lyrics in Track variant

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_track.dart` (add `_LyricsStrip` below the per-section lanes; locate by grepping for `'Add harmony lanes'` empty-hint or the section-strip composition)
- Test: extend `test/features/songwriter/songwriter_lyrics_render_test.dart`

- [ ] **Step 1: Add a failing test for track variant**

Append this test to `test/features/songwriter/songwriter_lyrics_render_test.dart`:

```dart
import 'package:muzician/features/songwriter/songwriter_screen_track.dart';

// add inside the existing main():
testWidgets('track variant renders lyrics inside section strip', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final notifier = container.read(songwriterProvider.notifier);
  notifier.addSection(label: 'Verse', lengthBars: 4);
  final id = container.read(songwriterProvider).sections.first.id;
  notifier.setSectionLyrics(id, 'walking down the road');

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SongwriterScreenTrack()),
    ),
  );
  await tester.pump();

  expect(find.text('walking down the road'), findsOneWidget);
});
```

If the existing file already declares a single `main()`, move the new test alongside the others inside that same `main()` block (do not duplicate `main`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: FAIL — "walking down the road" not found in widget tree.

- [ ] **Step 3: Render lyrics in track variant**

In `lib/features/songwriter/songwriter_screen_track.dart`:

1. Add import at top: `import 'section_lyrics_sheet.dart';`
2. Locate the per-section widget (search for the section-strip widget that renders the lanes — likely named `_SectionStrip` or similar; the comment header at line 1 confirms section composition). After the lanes are rendered and before the section divider, insert:

```dart
const SizedBox(height: 6),
_LyricsStrip(sectionId: section.id, lyrics: section.lyrics),
```

3. Add at the bottom of the file (reusing the exact same `_LyricsBlock` pattern from Task 4, but renamed to avoid private-class collision since both files are in the same package directory — Dart privacy is per-library):

```dart
class _LyricsStrip extends ConsumerWidget {
  const _LyricsStrip({required this.sectionId, required this.lyrics});

  final String sectionId;
  final String? lyrics;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showSectionLyricsSheet(
      context: context,
      initial: lyrics,
    );
    ref.read(songwriterProvider.notifier).setSectionLyrics(sectionId, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = lyrics != null && lyrics!.trim().isNotEmpty;
    return GestureDetector(
      key: Key('trackLyrics_$sectionId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          has ? lyrics! : '+ lyrics',
          style: TextStyle(
            color: has
                ? MuzicianTheme.textPrimary
                : MuzicianTheme.textPrimary.withOpacity(0.4),
            fontStyle: has ? FontStyle.normal : FontStyle.italic,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
```

If the existing track file doesn't already import `flutter_riverpod` and the theme, add those imports (mirror `songwriter_screen_sheet.dart`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: PASS (3/3 across both variants).

- [ ] **Step 5: Run full songwriter suite**

Run: `flutter test test/features/songwriter/ test/store/songwriter_*.dart test/models/song_section*.dart`
Expected: PASS, all green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/songwriter/songwriter_screen_track.dart test/features/songwriter/songwriter_lyrics_render_test.dart
git commit -m "feat(songwriter): render lyrics strip in track variant"
```

---

## Task 6: Render lyrics in Classic variant (section card)

**Files:**
- Modify: `lib/features/songwriter/songwriter_section_card.dart` (append lyrics inside the card body after lanes)

- [ ] **Step 1: Add a failing test**

Append to `test/features/songwriter/songwriter_lyrics_render_test.dart`:

```dart
import 'package:muzician/features/songwriter/songwriter_screen.dart';
import 'package:muzician/store/settings_store.dart' show settingsProvider, WriterLayout;

testWidgets('classic variant renders lyrics inside section card', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      // force classic layout regardless of stored preference
    ],
  );
  addTearDown(container.dispose);

  final notifier = container.read(songwriterProvider.notifier);
  notifier.addSection(label: 'Verse', lengthBars: 4);
  final id = container.read(songwriterProvider).sections.first.id;
  notifier.setSectionLyrics(id, 'classic verse');

  // The settings store controls the layout; flip to classic.
  await container.read(settingsProvider.notifier)
      .setWriterLayout(WriterLayout.classic);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SongwriterScreen()),
    ),
  );
  await tester.pump();

  expect(find.text('classic verse'), findsOneWidget);
});
```

If `settingsProvider.notifier.setWriterLayout` is not the exact API, run `grep -n "WriterLayout\|setWriterLayout\|writerLayout" lib/store/settings_store.dart` and use whichever setter exists (e.g. `setLayout(WriterLayout.classic)`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: FAIL — "classic verse" not found.

- [ ] **Step 3: Add lyrics rendering to the section card**

Edit `lib/features/songwriter/songwriter_section_card.dart`. Add import:

```dart
import 'section_lyrics_sheet.dart';
```

Find the card body Column children list (search for where lanes are mapped). After the lanes list and before the trailing add-lane button, append:

```dart
const SizedBox(height: 8),
_ClassicLyricsRow(sectionId: section.id, lyrics: section.lyrics),
```

Append the widget at the file bottom:

```dart
class _ClassicLyricsRow extends ConsumerWidget {
  const _ClassicLyricsRow({required this.sectionId, required this.lyrics});

  final String sectionId;
  final String? lyrics;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showSectionLyricsSheet(
      context: context,
      initial: lyrics,
    );
    ref.read(songwriterProvider.notifier).setSectionLyrics(sectionId, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = lyrics != null && lyrics!.trim().isNotEmpty;
    return InkWell(
      onTap: () => _edit(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lyrics_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                has ? lyrics! : 'Add lyrics…',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: has ? FontStyle.normal : FontStyle.italic,
                  color: has
                      ? MuzicianTheme.textPrimary
                      : MuzicianTheme.textPrimary.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

If `songwriter_section_card.dart` is not already a `ConsumerWidget` host, ensure `flutter_riverpod` is imported (mirror existing imports). If `Icons.lyrics_outlined` is not available in the project's Flutter SDK version, substitute `Icons.notes_rounded`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/songwriter/songwriter_lyrics_render_test.dart`
Expected: PASS (4/4).

- [ ] **Step 5: Run the entire test suite to catch downstream regressions**

Run: `flutter test`
Expected: PASS — all suites green.

- [ ] **Step 6: Manual smoke check in the running app**

Run: `flutter run -d <preferred-device>`
- Switch each layout (Track / Sheet / Classic) via settings.
- Tap the lyrics affordance in each — sheet opens, type, save.
- Confirm lyrics persist across a hot restart (debounced session save).
- Confirm clearing returns the "+ lyrics" affordance.

- [ ] **Step 7: Commit**

```bash
git add lib/features/songwriter/songwriter_section_card.dart test/features/songwriter/songwriter_lyrics_render_test.dart
git commit -m "feat(songwriter): render lyrics row in classic section card"
```

---

## Self-Review Notes

- **Spec coverage:** lyrics field on section (Task 1), store mutator (Task 2), shared editor (Task 3), three variants render + edit (Tasks 4/5/6), persistence ridden by existing JSON path (Task 1) and debounced save (Task 2).
- **No bar-quantization, no per-verse stanzas, no playback sync** — explicitly deferred under non-goals.
- **Naming consistency:** `setSectionLyrics`, `clearLyrics`, `lyrics` used identically across model, store, and UI tasks.
- **All TextStyle / theme references** assume `MuzicianTheme.textPrimary` and `MuzicianTheme.textMuted` exist; fallback noted in Task 4 Step 3. If neither exists, substitute the nearest neutral text color from `lib/theme/muzician_theme.dart`.

---

## Implementation Addendum (Verified Against HEAD)

> Verified on branch `writer-glass-retheme` at the start of this plan.

**Theme tokens — confirmed present in `lib/theme/muzician_theme.dart`:**
- `MuzicianTheme.textPrimary` = `Color(0xFFF1F5F9)`
- `MuzicianTheme.textSecondary` = `Color(0xFF94A3B8)`
- `MuzicianTheme.textMuted` = `Color(0xFF8B9DC3)` ← use this for the "+ lyrics" placeholder
- `MuzicianTheme.textDim` = `Color(0xFF334155)`

No need for fallback substitution — use `MuzicianTheme.textMuted` verbatim in Tasks 4–6.

**`InputDecoration` styling for the editor (Task 3):**
The rest of the app uses dark glass theming. Replace the bare `OutlineInputBorder()` in `section_lyrics_sheet.dart` with:

```dart
decoration: InputDecoration(
  hintText: 'Type lyrics for this section…',
  hintStyle: const TextStyle(color: MuzicianTheme.textMuted),
  filled: true,
  fillColor: MuzicianTheme.glassBg,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: MuzicianTheme.glassBorder),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: MuzicianTheme.glassBorder),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: MuzicianTheme.sky),
  ),
),
style: const TextStyle(color: MuzicianTheme.textPrimary, fontSize: 14, height: 1.4),
```

Add `import '../../theme/muzician_theme.dart';` to the editor file.

**`settingsProvider` writer-layout setter (Task 6):**
Run `grep -n "WriterLayout\|writerLayout" lib/store/settings_store.dart` before writing Task 6. The setter is named `setWriterLayout(WriterLayout)`; if the actual method differs, substitute the real method name and update the test snippet.

**`showWidgetSheet` contract (used by editor in Task 3):**
The shared `showWidgetSheet` helper already pops on `Navigator.pop`. The `_SectionLyricsBody` callbacks rely on that — verify by skimming `lib/features/_mockup_shell.dart` for the `showWidgetSheet` definition. No additional `Navigator.pop` plumbing required.

**Risks / edge cases:**
- **Empty-string lyrics treated as null.** `setSectionLyrics` clears when input is empty or whitespace-only. Tests in Task 2 cover the null case; verify trim semantics match if the editor passes `'   \n  '`.
- **Hot-restart persistence.** Lyrics rides the existing 500 ms debounced session save. Manual smoke (Task 6 Step 6) must wait ≥1 s after editing before hot-restarting.
- **JSON migration safety.** `lyrics` is a new optional key; existing stored sessions (without `lyrics`) decode to `null`. Covered by `fromJson tolerates missing lyrics key` in Task 1.

**Branch strategy:**
- New branch off `writer-glass-retheme`: `songwriter-lyrics`.
- One PR at the end, scoped to `lib/features/songwriter/`, `lib/models/songwriter.dart`, `lib/store/songwriter_store.dart`, plus the three new test files.

**Out-of-scope reminders (do NOT do):**
- No bar-quantized syllable markers.
- No multi-verse per section. Free-text blob only.
- No playback karaoke. Sheet variant remains read-only on lyrics.
- Do not touch `songwriter_structure_editor.dart`.
