# Writer Section Mixer + Multiple Harmony Lanes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-section mixer (volume / pan / mute per lane, all kinds) and multiple harmony lanes per section for double-tracking.

**Architecture:** Three fields on `SongLane` (`volume`, `pan`, `muted`) flow through pure playback rules as `(volume, pan)` buckets, into `NotePlayer.setBalance` / audio-sink `setBalance`. UI drops the single-harmony-lane assumption in `songwriter_screen_sheet.dart` and adds a per-section mixer bottom sheet. Export maps harmony lanes to per-index Song tracks with volume.

**Tech Stack:** Flutter, Riverpod, audioplayers 6 (`setBalance`), package:test / flutter_test.

Spec: `docs/superpowers/specs/2026-07-04-writer-harmony-mixer-design.md`

## Global Constraints

- Defaults: `volume = 1.0`, `pan = 0.0`, `muted = false`; legacy JSON without the fields must load with these defaults (no migration).
- Clamps: volume 0.0–1.0, pan −1.0..1.0.
- Muted lanes are fully skipped in playback flattening, audition beds, and audio-clip scheduling.
- Per-chord lyric UI only on the first (primary) harmony lane.
- Full suite green at the end (baseline 801 tests).
- Branch: `feature/writer-harmony-mixer`.

---

### Task 1: SongLane volume/pan/muted model fields

**Files:**
- Modify: `lib/models/songwriter.dart` (class `SongLane`, ~line 355)
- Test: `test/models/songwriter_lane_mix_test.dart` (new)

**Interfaces:**
- Produces: `SongLane.volume: double`, `SongLane.pan: double`, `SongLane.muted: bool`; `copyWith({double? volume, double? pan, bool? muted, ...})`; JSON keys `volume`, `pan`, `muted`.

- [ ] **Step 1: failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongLane defaults volume 1, pan 0, unmuted', () {
    const lane = SongLane(id: 'l1', kind: SongLaneKind.harmony, order: 0);
    expect(lane.volume, 1.0);
    expect(lane.pan, 0.0);
    expect(lane.muted, false);
  });

  test('SongLane mix fields survive JSON round-trip', () {
    const lane = SongLane(
      id: 'l1', kind: SongLaneKind.harmony, order: 0,
      volume: 0.5, pan: -0.7, muted: true,
    );
    final back = SongLane.fromJson(lane.toJson());
    expect(back.volume, 0.5);
    expect(back.pan, -0.7);
    expect(back.muted, true);
  });

  test('legacy JSON without mix fields loads defaults', () {
    final back = SongLane.fromJson({'id': 'l1', 'kind': 'harmony', 'order': 0});
    expect(back.volume, 1.0);
    expect(back.pan, 0.0);
    expect(back.muted, false);
  });

  test('copyWith sets mix fields', () {
    const lane = SongLane(id: 'l1', kind: SongLaneKind.harmony, order: 0);
    final c = lane.copyWith(volume: 0.3, pan: 0.4, muted: true);
    expect((c.volume, c.pan, c.muted), (0.3, 0.4, true));
  });
}
```

- [ ] **Step 2: run — expect FAIL** (`flutter test test/models/songwriter_lane_mix_test.dart`, "No named parameter")
- [ ] **Step 3: implement** — add to `SongLane`: fields `final double volume; final double pan; final bool muted;` with constructor defaults `this.volume = 1.0, this.pan = 0.0, this.muted = false`; extend `copyWith`; `toJson` adds `'volume': volume, 'pan': pan, 'muted': muted`; `fromJson` reads `volume: (json['volume'] as num?)?.toDouble() ?? 1.0, pan: (json['pan'] as num?)?.toDouble() ?? 0.0, muted: json['muted'] as bool? ?? false`.
- [ ] **Step 4: run — expect PASS**
- [ ] **Step 5: commit** `feat(songwriter): add volume/pan/muted to SongLane`

### Task 2: store setters

**Files:**
- Modify: `lib/store/songwriter_store.dart` (after `setLaneRepeat`, ~line 284)
- Test: `test/store/songwriter_lane_ops_test.dart` (extend)

**Interfaces:**
- Consumes: `_replaceLane` helper.
- Produces: `setLaneVolume({required String sectionId, required String laneId, required double volume})`, `setLanePan({...required double pan})`, `setLaneMuted({...required bool muted})` on `SongwriterNotifier`.

- [ ] **Step 1: failing tests** — in existing lane-ops test file, group `'lane mix ops'`: set volume 0.5 → lane.volume 0.5; volume 1.7 → clamped 1.0; pan −2 → clamped −1.0; toggle muted true/false. Use the file's existing container/notifier setup pattern.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement**

```dart
void setLaneVolume({
  required String sectionId,
  required String laneId,
  required double volume,
}) => _replaceLane(
  sectionId,
  laneId,
  (l) => l.copyWith(volume: volume.clamp(0.0, 1.0)),
);

void setLanePan({
  required String sectionId,
  required String laneId,
  required double pan,
}) => _replaceLane(
  sectionId,
  laneId,
  (l) => l.copyWith(pan: pan.clamp(-1.0, 1.0)),
);

void setLaneMuted({
  required String sectionId,
  required String laneId,
  required bool muted,
}) => _replaceLane(sectionId, laneId, (l) => l.copyWith(muted: muted));
```

- [ ] **Step 4: run — PASS**
- [ ] **Step 5: commit** `feat(songwriter): lane volume/pan/mute store setters`

### Task 3: playback rules — grouped events + muted skip

**Files:**
- Modify: `lib/schema/rules/songwriter_playback_rules.dart`
- Test: `test/store/songwriter_playback_test.dart` (update event-shape assertions) + new group tests

**Interfaces:**
- Produces:

```dart
typedef SongwriterNoteGroup = ({double volume, double pan, List<int> midiNotes});
typedef SongwriterDrumGroup = ({double volume, double pan, List<DrumLaneId> drumLanes});

class SongwriterPlaybackEvent {
  const SongwriterPlaybackEvent({
    required this.tick,
    this.noteGroups = const [],
    this.drumGroups = const [],
  });
  final int tick;
  final List<SongwriterNoteGroup> noteGroups;
  final List<SongwriterDrumGroup> drumGroups;
  /// Flat views for callers that don't care about mixing (tests, ruler).
  List<int> get midiNotes => [for (final g in noteGroups) ...g.midiNotes];
  List<DrumLaneId> get drumLanes => [for (final g in drumGroups) ...g.drumLanes];
}
```

- [ ] **Step 1: failing tests** — two harmony lanes, same bar, pans −0.5/+0.5 → one event, two noteGroups with matching pans; muted lane emits nothing; two lanes with identical (volume, pan) merge into one group; drum lane volume 0.5 → drumGroup volume 0.5; `sectionHarmonyLoop` skips muted lanes.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement** — in `flattenPlaybackEvents`, replace `notesAt`/`drumsAt` with:

```dart
final notesAt = <int, Map<(double, double), List<int>>>{};
final drumsAt = <int, Map<(double, double), Set<DrumLaneId>>>{};
```

Inside the lane loop add `if (lane.muted) continue;` and bucket key `(lane.volume, lane.pan)`. Harmony/save case: `((notesAt[tick] ??= {})[key] ??= []).addAll(pitches);`. Drum case: `_tileDrumHits` gains the bucket map for the lane's key (pass `(drumsAt[tick] ??= {})[key] ??= <DrumLaneId>{}` style — refactor `_tileDrumHits` to take a `void Function(int tick, DrumLaneId lane)` callback or a per-lane `Map<int, Set<DrumLaneId>>` then fold into buckets). Emit events:

```dart
SongwriterPlaybackEvent(
  tick: tick,
  noteGroups: [
    for (final e in (notesAt[tick] ?? const {}).entries)
      (volume: e.key.$1, pan: e.key.$2, midiNotes: e.value),
  ],
  drumGroups: [
    for (final e in (drumsAt[tick] ?? const {}).entries)
      (volume: e.key.$1, pan: e.key.$2, drumLanes: e.value.toList()),
  ],
)
```

`_sectionChordBed`: add `if (lane.muted) continue;` (stays flat otherwise). `sectionAuditionBed` drum loop: add same skip.
- [ ] **Step 4: run playback tests — PASS** (fix any assertions still using old flat fields via the new `midiNotes`/`drumLanes` getters)
- [ ] **Step 5: commit** `feat(songwriter): volume/pan groups in playback flattening`

### Task 4: engine + transport — pan-aware sinks

**Files:**
- Modify: `lib/utils/note_player.dart`, `lib/store/drum_pattern_playback_store.dart`, `lib/store/songwriter_playback_store.dart`
- Test: `test/store/songwriter_playback_test.dart`, `test/store/songwriter_metronome_sink_test.dart` (compile fixes), drum store tests

**Interfaces:**
- Produces: `NotePlayer.previewNote(int, {double volume, double pan = 0.0})`, `NotePlayer.playDrumLane(DrumLaneId, {double volume, double pan = 0.0})`; `typedef SongwriterNoteSink = void Function(List<SongwriterNoteGroup> groups)`; `typedef DrumPatternPlaybackSink = Future<void> Function(List<DrumLaneId> lanes, double volume, double pan)`.

- [ ] **Step 1: failing tests** — override `songwriterNoteSinkProvider`/`drumPatternPlaybackSinkProvider` in playback-store test to capture groups; assert lane volume 0.5 pan −1 arrives as group (0.5, −1.0) and drum sink receives `(lanes, 0.8 * laneVolume, pan)`.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement**
  - `note_player.dart`: thread `pan` through `previewNote` → `_play(midi, volume, pan)` → `await player.setBalance(pan.clamp(-1.0, 1.0));` before `play`; same for `playDrumLane` → `_playDrum`. `_playClick`: add `await player.setBalance(0.0);` (pool players are shared — a click after a panned note must recenter).
  - `drum_pattern_playback_store.dart`: typedef gains `double pan`; provider impl `(lanes, volume, pan) async { for (final lane in lanes) { NotePlayer.instance.playDrumLane(lane, volume: volume, pan: pan); } }`; update all existing call sites (grep `drumSink(`/`sink(`) passing `0.0`.
  - `songwriter_playback_store.dart`: note sink provider becomes

```dart
return (groups) {
  for (final g in groups) {
    for (final midi in g.midiNotes) {
      NotePlayer.instance.previewNote(midi, volume: 0.6 * g.volume, pan: g.pan);
    }
  }
};
```

  Tick loop:

```dart
if (event.noteGroups.isNotEmpty) noteSink(event.noteGroups);
for (final g in event.drumGroups) {
  unawaited(drumSink(g.drumLanes, 0.8 * g.volume, g.pan));
}
```

- [ ] **Step 4: full `flutter test test/store` — PASS**
- [ ] **Step 5: commit** `feat(songwriter): pan-aware note/drum sinks`

### Task 5: audio lanes — lane gain/pan/mute into clip scheduling

**Files:**
- Modify: `lib/schema/rules/songwriter_audio_rules.dart`, `lib/store/song_playback_store.dart` (`SongAudioClipSink.startClip` signature + no-op sink), `lib/store/song_audio_player_sink.dart`, `lib/store/songwriter_playback_store.dart` (pass balance), `lib/store/songwriter_audio_audition_store.dart` + record monitor if they call `startClip` (grep)
- Test: `test/store/songwriter_audio_playback_test.dart` (extend)

**Interfaces:**
- Produces: `SongwriterScheduledClip.pan: double` (default 0.0); `startClip({required AudioAsset asset, required int offsetMs, double volume = 1.0, double balance = 0.0, bool loop = false})`.

- [ ] **Step 1: failing tests** — audio lane volume 0.5 → scheduled clip volume 0.5; muted audio lane → no scheduled clips; pan carried to `SongwriterScheduledClip.pan`. Same for `songwriterSectionSchedulableClips`.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement** — both rules: `if (lane.muted) continue;` and construct clips with `volume: lane.volume, pan: lane.pan`. Sink interface + `AudioPlayersClipSink.startClip`: add `double balance = 0.0` → `await player.setBalance(balance.clamp(-1.0, 1.0));` after `setVolume`. Transport `fireAudio`: `balance: clip.pan`.
- [ ] **Step 4: run — PASS**
- [ ] **Step 5: commit** `feat(songwriter): audio lane volume/pan/mute in clip scheduling`

### Task 6: export — per-index harmony tracks + volumes

**Files:**
- Modify: `lib/schema/rules/song_from_writer_rules.dart`
- Test: existing song-from-writer test file (grep `songFromSongwriter` under test/), extend

**Interfaces:**
- Produces: unchanged signature `SongProject songFromSongwriter(...)`; harmony track per harmony-lane index, named first-seen `lane.label` ?? (`'Harmony'` for index 0, `'Harmony ${i+1}'` otherwise); `SongTrack.volume = muted ? 0.0 : lane.volume` for harmony/save/drum tracks (first-seen lane wins per track).

- [ ] **Step 1: failing tests** — section with 2 harmony lanes → 2 note tracks with distinct clips; lane volume 0.4 → track volume 0.4; muted lane → track volume 0.0.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement** — replace single `harmonyTrackId`/`harmonyUsed` with:

```dart
final harmonyTrackIdByIndex = <int, String>{};
final harmonyTrackByIndex = <int, SongTrack>{};
```

In the section loop compute `final harmonyLanes = section.lanes.where((l) => l.kind == SongLaneKind.harmony).toList();` and for a harmony lane `final hIdx = harmonyLanes.indexOf(lane);`. On first sight of an index create the track (`volume: lane.muted ? 0.0 : lane.volume`). Save/drum track creation gains the same `volume:` argument. At the end insert harmony tracks at the front in index order (replaces the `harmonyUsed` insert).
- [ ] **Step 4: run — PASS**
- [ ] **Step 5: commit** `feat(songwriter): per-lane harmony tracks + volumes in Song export`

### Task 7: UI — multiple harmony lanes

**Files:**
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart`
- Test: `test/features/songwriter/` (extend the sheet widget test; grep for `sectionInstance_` keys)

**Interfaces:**
- Consumes: `addLane`, `removeLane`.
- Produces: `_SectionInstance` takes `required List<SongLane> harmonyLanes`; `_BarRow` gains `required bool isPrimary`; section menu item key `addHarmonyLaneSheetAction`; lane header delete key `deleteHarmonyLane_<laneId>`.

- [ ] **Step 1: failing widget tests** — (a) project with 2 harmony lanes renders 2 bar rows + visible "Harmony 2" label; (b) menu "Add harmony lane" adds lane labelled `Harmony N`; (c) per-chord lyric affordance absent on secondary lane's chord sheet.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement**
  - `_SectionSheet`: `final harmonyLanes = section.lanes.where((l) => l.kind == SongLaneKind.harmony).toList();` — pass list (empty → keep current placeholder `SongLane(id: '')` single-entry list so ensure-lane flow still works).
  - `_SectionInstance`: replace single `_BarRow` with `for (var li = 0; li < harmonyLanes.length; li++) ...[ if (harmonyLanes.length > 1) _HarmonyLaneHeader(section, lane, li), _BarRow(..., lane: harmonyLanes[li], isPrimary: li == 0) ]`. `_HarmonyLaneHeader`: label text + delete `IconButton` (confirmation dialog: "Delete <label>? Its chords are removed." → `removeLane`).
  - `_BarRow.isPrimary == false`: hide per-chord lyric row/editor affordances and skip lyric writes (pass `showLyrics: isPrimary` into the harmony chord sheet call; keep silent-block verse padding as-is).
  - Section popup menu: add `addHarmonyLane` item → `addLane(sectionId, kind: harmony, label: 'Harmony ${harmonyCount + 1}')`.
- [ ] **Step 4: run — PASS**
- [ ] **Step 5: commit** `feat(songwriter): multiple harmony lanes per section`

### Task 8: UI — mixer sheet

**Files:**
- Create: `lib/features/songwriter/songwriter_mixer_sheet.dart`
- Modify: `lib/features/songwriter/songwriter_screen_sheet.dart` (section heading: mixer icon button)
- Test: `test/features/songwriter/songwriter_mixer_sheet_test.dart` (new)

**Interfaces:**
- Produces: `Future<void> showSongwriterMixerSheet(BuildContext context, {required String sectionId})`; keys: `sectionMixer_<sectionId>` (opener), `mixerVolume_<laneId>`, `mixerPan_<laneId>`, `mixerMute_<laneId>`.

- [ ] **Step 1: failing widget tests** — open mixer for section with harmony + drum lane → 2 strips; drag volume slider → store volume changes; tap mute → `lane.muted` true; pan slider near center snaps to 0.0.
- [ ] **Step 2: run — FAIL**
- [ ] **Step 3: implement** — modal bottom sheet matching existing Writer sheet styling (copy container/scroll scaffolding from an existing sheet in the feature). Per strip: kind icon (`music_note`/`bookmark`/`graphic_eq`/`mic`), label fallback by kind (`Harmony`/`Save`/`Beat`/`Sample`), `Slider(value: lane.volume, onChanged: v => notifier.setLaneVolume(...))`, `Slider(min: -1, max: 1, value: lane.pan, onChanged: v => notifier.setLanePan(pan: v.abs() < 0.08 ? 0.0 : v))` with `L`/`R` captions, mute `IconButton(icon: volume_off/volume_up)` toggling `setLaneMuted`; muted strip wrapped in `Opacity(0.45)`. Opener: `IconButton(key: Key('sectionMixer_${section.id}'), icon: Icon(Icons.tune), onPressed: () => showSongwriterMixerSheet(context, sectionId: section.id))` in the heading row before the popup menu.
- [ ] **Step 4: run — PASS**
- [ ] **Step 5: commit** `feat(songwriter): per-section mixer sheet`

### Task 9: full verification

- [ ] `dart analyze` — zero new issues
- [ ] `flutter test` — full suite green
- [ ] Push branch, open PR (no auto-merge; user reviews)
