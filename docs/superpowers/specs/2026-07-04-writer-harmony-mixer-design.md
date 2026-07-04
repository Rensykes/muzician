# Writer: Section Mixer + Multiple Harmony Lanes — Design

Date: 2026-07-04
Status: Approved (sections 1–2 explicitly; 3–6 under "proceed without confirmations")

## Goal

Two Writer features:

1. **Per-section mixer** — volume, pan, and mute for every lane in a section
   (harmony, save, drum, audio).
2. **Multiple harmony lanes per section** — e.g. Verse has "Harmony 1",
   "Harmony 2", "Harmony 3" to emulate double tracking / complementary
   tracking. New lanes start empty.

Decisions made during brainstorming:

- Mixer is **per-section** (lanes live per section in the model; no
  cross-section lane identity).
- Mixer covers **all lane kinds**, not just harmony.
- New harmony lanes start **empty** (no duplicate-lane action).
- Mixer strips get **mute** (no solo).
- Per-chord **lyrics stay on the first harmony lane only**; extra harmony
  lanes are pure chord layers.

## 1. Data model (`lib/models/songwriter.dart`)

`SongLane` gains three fields:

```dart
final double volume; // 0.0–1.0, default 1.0
final double pan;    // -1.0..1.0, default 0.0 (center)
final bool muted;    // default false
```

- `copyWith` extended with the three fields.
- `toJson` always writes them; `fromJson` reads with defaults
  (`volume ?? 1.0`, `pan ?? 0.0`, `muted ?? false`) so legacy saves load
  unchanged. No migration needed.
- No changes to `SongBlock` or `SongSection`.

## 2. Store API (`lib/store/songwriter_store.dart`)

```dart
void setLaneVolume({required String sectionId, required String laneId, required double volume}) // clamps 0..1
void setLanePan({required String sectionId, required String laneId, required double pan})       // clamps -1..1
void setLaneMuted({required String sectionId, required String laneId, required bool muted})
```

All implemented via the existing `_replaceLane` helper (persist + no-op
short-circuit for free). `addLane` itself is unchanged; harmony-lane call
sites label new lanes "Harmony N" where N = current harmony-lane count in the
section + 1.

## 3. Playback (`lib/schema/rules/songwriter_playback_rules.dart`, transport, engine)

### Event model

`SongwriterPlaybackEvent` replaces flat `midiNotes` / `drumLanes` with
volume/pan groups, mirroring the Song feature's `noteGroups` precedent
(`lib/models/song_playback.dart`):

```dart
final List<({double volume, double pan, List<int> midiNotes})> noteGroups;
final List<({double volume, double pan, List<DrumLaneId> drumLanes})> drumGroups;
```

- `flattenPlaybackEvents` buckets notes/drums per `(lane.volume, lane.pan)`.
- Muted lanes are skipped entirely.
- The same chord in two lanes with different pan fires twice, once per
  bucket — that is the double-tracking effect.

### Engine (`lib/utils/note_player.dart`)

- `previewNote` and `playDrumLane` gain a `pan` parameter (default 0.0);
  playback calls `player.setBalance(pan)` next to the existing `setVolume`.
  Pooled players get balance set per play, so no reset is needed.
- audioplayers 6 supports `setBalance` on all targeted platforms (web via
  StereoPannerNode).

### Transport (`lib/store/songwriter_playback_store.dart`)

- Note/drum sink typedefs change to accept groups; the tick loop iterates
  groups. Effective gain = existing base (0.6 notes / 0.8 drums) × lane
  volume.
- Audio lanes: `songwriterSchedulableAudioClips` multiplies scheduled clip
  volume by lane volume, drops muted lanes, and carries lane pan;
  `startClip` gains a `balance` parameter applied via `setBalance` in
  `lib/store/song_audio_player_sink.dart`.
- Mix changes made mid-play take effect on the next play (events and clip
  schedule are computed at transport start). Acceptable; not a live mixer.

### Audition beds

`sectionHarmonyLoop` / `sectionAuditionBed` / `_sectionChordBed`: skip muted
lanes; otherwise stay flat (no vol/pan groups). They are sketch backing for
the drum/audio editors — keeping them flat keeps scope small.

## 4. UI — multiple harmony lanes (`lib/features/songwriter/songwriter_screen_sheet.dart`)

- `_SectionSheet` stops doing `firstWhere(kind == harmony)`; it collects all
  harmony lanes (by `order`) and `_SectionInstance` renders one `_BarRow` per
  harmony lane, stacked, before drum/audio lane rows (same pattern the drum
  lane loop already uses).
- When a section has more than one harmony lane, each bar row gets a small
  lane-label header ("Harmony 1", "Harmony 2", …) with an overflow action to
  delete the lane (existing `removeLane`). With one lane, the header is
  hidden — current look preserved.
- Lyric affordances (per-chord lyric rows, lyric fields in the chord sheet)
  render only for the first harmony lane: `_BarRow` gains an `isPrimary`
  flag; secondary lanes hide lyric UI and skip lyric writes.
- Section overflow menu gains "Add harmony lane" (next to the existing add
  drum/audio lane items) → `addLane(kind: harmony, label: 'Harmony N')`.
- `onEnsureLane` (auto-create harmony lane on first chord tap) applies only
  to the primary lane path; secondary lanes always exist before render.
- `setSectionRepeat`'s lyric padding currently pads blocks on every harmony
  lane; harmless, left as-is.

## 5. UI — mixer sheet (new widget, e.g. `lib/features/songwriter/songwriter_mixer_sheet.dart`)

- Entry point: mixer icon button in the section heading row (next to the
  verses stepper / overflow menu) → modal bottom sheet, matching existing
  Writer sheet styling.
- One strip per lane in section order. Strip contents:
  - kind icon + label (fallback: "Harmony" / "Save" / "Beat" / "Sample"),
  - volume slider 0–100 %,
  - pan slider −1..+1 with center detent (snap to 0 within a small
    threshold), labelled L / C / R,
  - mute toggle (icon button; muted strip renders dimmed).
- Controls call `setLaneVolume` / `setLanePan` / `setLaneMuted` directly;
  state is watched from the provider so the sheet is live.

## 6. Export (`lib/schema/rules/song_from_writer_rules.dart`)

- Today all harmony lanes across all sections merge into one Song note
  track. Change: one note track per harmony-lane **index** ("Harmony 1"
  track collects the first harmony lane of every section, etc.).
- Track volume = lane muted ? 0.0 : lane volume, taken from the first
  section that has a lane at that index (per-section divergence is a noted
  limitation — `SongTrack` volume is per track).
- Save/drum lanes already get per-lane tracks; their track volume maps the
  same way. `SongTrack` has no pan field, so pan is dropped on export
  (documented limitation).

## 7. Testing

- Model: JSON round-trip for the new fields; legacy JSON (fields absent)
  loads with defaults.
- Store: clamp behavior for volume/pan; mute toggle; multiple harmony lanes
  addable; persistence via existing `_set` path.
- Playback rules: bucketing by (volume, pan); muted lanes silent; two
  harmony lanes with the same chord and different pan produce two groups;
  audition beds skip muted lanes.
- Export rules: per-index harmony tracks; volume mapping incl. mute → 0.
- Widgets: mixer sheet strips update the store; multi-lane section renders
  N bar rows; lane-label headers appear only when >1 harmony lane; lyric UI
  only on the primary lane; "Add harmony lane" menu item works.
- Full suite must stay green (baseline 801 tests on main).
