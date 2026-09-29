# Writer: strumming, melody, and project flow

**Status:** Approved by independent plan review and the user; implementation
is complete, independent code reviews passed, and focused validation passed.

## Goal

Make Writer strum patterns and their guitar Harmony sources visible; make
Melody pattern duration, placement, and reuse clear; let each melody pattern
be mapped to playable Piano or Fretboard positions; and let Writer create a
separate Save System project without silently losing the current session.

## Confirmed behavior

- A Guitar Strum lane applies its pattern to chord blocks on one selected
  Fretboard Harmony lane. There may be multiple strum patterns across guitar
  Harmony lanes, and every pattern tile should preview its down/up events.
- Melody supports reuse or creation of patterns at empty bars, including
  arrangements such as A–B–A–B. The UI must show actual pattern duration and
  its placement against the section's total bars.
- A melody pattern has one saved play target (Piano or Fretboard) and saved
  physical position for each note. Fretboard positions are string plus fret;
  Piano positions use the note's MIDI key. Positions must survive reopening.
- Do not open or edit a melody in an instrument view if that instrument cannot
  play every note under its current range, tuning, capo, and fret count.
- “New project” from Writer creates a separate Save System project and opens
  that project's empty Writer session, with a Piano/Fretboard choice. Before
  switching, Writer offers Keep, Discard, or Cancel when the current session
  has changes.
- Discard restores the current project's active named Writer Save when one is
  bound; when no valid Writer Save is bound, it clears that project's Writer
  session and binding. Other named Save entries stay intact.

## Proposed interaction details for plan approval

- Preserve current strum pitch behavior (`chordMidiNotes` from the symbolic
  chord). The reported playback works; this task improves source assignment
  and event visibility without introducing a Fretboard voicing dependency or
  new audio timbres.
- Allow multiple strum lanes to share a guitar Harmony source. Store the
  selected Harmony lane ID explicitly, including when it is the primary lane;
  `null` means unassigned and never means “follow primary.” Disable adding a
  Guitar Strum lane when there is no Fretboard Harmony lane. If an assigned
  source changes to Piano or is removed, keep the stored anchor unresolved,
  show “Unresolved,” keep the lane silent, and let the user repair it; never
  retarget silently. Add a
  persisted root `strumAnchorMigrationVersion` to
  `SongwriterProjectSnapshot`. A missing/older version marks a legacy snapshot;
  resolve each null anchor once using the old primary-Harmony rule and the
  effective project default, then pin that same lane ID only if it is
  Fretboard. If the old primary resolves to Piano or is absent, preserve null
  rather than silently retargeting to another guitar lane. Persist the current
  version even when no guitar source exists. Versioned null anchors stay
  unassigned when a guitar lane is added later.
- Keep the Piano Roll available to correct notes. Gate only the selected
  Piano/Fretboard performance view and its position editing when notes are
  incompatible. The instrument target controls the view and physical mapping;
  audio continues through the existing generic synthesizer.
- Default a melody block to the pattern's full duration when the following
  bars are free. Allow the user to shorten or extend placement, and show clear
  clipping behavior when placement is shorter than the pattern.
- Ask for Piano/Fretboard on every Writer project creation, and save that
  choice on the project's config without changing the global default.
- “Scarta” restores the bound active Writer Save if present; if no valid Writer
  Save is bound, clear the current Writer session and binding. Preserve all
  named Save entries.

## Current behavior and code evidence

### Strumming

`SongLane.anchorLaneId` already stores a Guitar Strum lane's selected Harmony
source. The UI gap is in `_PatternLaneRow` in
`lib/features/songwriter/songwriter_screen_sheet.dart`: its anchor dropdown
currently includes every Harmony lane and tiles show only a pattern name.
However, filtering the dropdown alone is insufficient. New strum lanes can be
created unanchored; Writer playback and Writer-to-Song conversion both resolve
a null anchor to the primary Harmony lane, which can be Piano. The store also
accepts a non-Fretboard anchor, and changing/removing a Harmony lane can make an
existing anchor invalid. Make Fretboard-only assignment a store and playback
invariant, and apply the same resolver rules in
`lib/schema/rules/song_from_writer_rules.dart`; do not silently route a strum
through a Piano or stale lane.

Filter the source options to guitar lanes and validate the same constraint in
store mutations, playback, and Song export. Run the versioned migration once
for project-scoped Writer sessions, named Writer Save snapshots, and each
bound `WriterSaveBinding.materializedBaselineJson` when hydrated into the
selected project's effective Harmony default. Apply the same snapshot
transformation to a binding baseline; never replace the baseline with the live
snapshot as a shortcut, since that would erase a real dirty delta. Persist the
migrated snapshots, bindings, and their version markers together before
exposing them as editable; migration must also mark a snapshot with no
available guitar source so a later added guitar lane cannot acquire it
accidentally. Store the
selected lane ID even when the user selects the primary lane, so removing that
source cannot silently retarget the strum to the next primary lane. Resolve
the effective instrument,
not the nullable serialized field: legacy lanes with no explicit
`harmonyInstrument` inherit the selected project's default. Centralize this
resolution so UI, store, playback, and Writer-to-Song export agree. The two
pure rule entry points do not read Settings; pass the effective project
default explicitly from their callers, deriving it from project config and
the Settings fallback exactly as `SongwriterNotifier` does:

```dart
final guitarHarmonyLanes = section.lanes.where(
  (candidate) =>
      candidate.kind == SongLaneKind.harmony &&
      effectiveHarmonyInstrument(candidate, projectDefault) ==
          HarmonyLaneInstrument.fretboard,
);
```

Keep the persisted migration version explicit and backward-compatible:

```dart
'strumAnchorMigrationVersion': strumAnchorMigrationVersion,
strumAnchorMigrationVersion:
    json['strumAnchorMigrationVersion'] as int? ?? 0,
```

Each strum tile should render a compact, ordered preview of the assigned
`GuitarStrumPattern.events` (for example, arrows positioned on the pattern's
tick grid). Once the migration version is current, an absent anchor is
unassigned and must not resolve to the current primary lane. Retain the
detailed editor in
`lib/features/songwriter/guitar_strum_pattern_sheet.dart`.

An invalid or missing source must never fall back to a Piano Harmony lane.
Apply the proposed unassigned/silent/repairable behavior described above.

### Melody length and placement

`NotePattern.lengthTicks` is the pattern duration;
`SongBlock.spanBars` is the placement window; and `SongSection.lengthBars` is
the full timeline. Playback repeats a pattern within its block and clips events
to that block. The empty-bar action in `_PatternLaneRow` currently always
creates a new one-bar pattern, and tiles show only the pattern name. There is
no Writer UI to resize a pattern block even though `SongwriterNotifier`
already exposes `setBlockPlacement`.

Show exact pattern duration in musical units (bars plus remaining beats/ticks)
alongside the block's placed bars and the resulting repeat/clip behavior; retain
the section bar ruler as overall context. Do not round a non-bar-aligned
`lengthTicks` up and present that as its exact duration. Empty bars should offer
**Use existing pattern** and **Create new pattern**. Reuse means another
`SongBlock` points to the same `patternId` and keeps the pattern's performance
mapping.

Add a Writer placement control backed by `setBlockPlacement`. Preflight
placements against both `section.lengthBars` and neighboring blocks, and
render multi-bar blocks that cross the four-column row boundary as continuation
segments in each row. Create/reuse the pattern and add its first block in one
history group. On the initial Piano Roll save for a newly created pattern,
expand only that initial placement to the full duration when bars are
available. When editing a reused pattern later changes its duration, leave its
existing block spans unchanged and show clip/repeat behavior. This avoids
adding a persisted marker for default versus user-resized spans.

### Instrument play state

Writer stores `melodyPatterns` as `List<NotePattern>` in
`SongwriterProjectSnapshot` (`lib/models/songwriter.dart`). `NotePattern` and
`NotePatternNote` in `lib/models/song_project.dart` are also used by Song. The
isolated Piano Roll bridge preserves note IDs when converting to and from the
editor (`lib/schema/rules/song_pattern_bridge_rules.dart`), but it currently
has no instrument-position state. Keep Writer's physical mapping in its own
snapshot field rather than adding Writer-only fields to the shared Song
pattern model:

```dart
class WriterMelodyPerformance {
  final HarmonyLaneInstrument instrument;
  final Map<String, FretboardNotePosition> fretboardPositionsByNoteId;
}

class FretboardNotePosition {
  final int stringIndex;
  final int fret;
}
```

Store performance state in the Writer project session, keyed by melody
`patternId`, and in the canonical `WriterBlockSnapshot` for Save System block
reuse. A `SongwriterProjectSnapshot` field alone is not sufficient: Writer
blocks can be saved, restored, reused, or made unique through canonical
snapshots that currently carry the `NotePattern` but no instrument mapping.
Add the mapping as an optional backward-compatible field to
`WriterBlockSnapshot` and carry it through `writerBlockSnapshotFor`, block
insert/restore, canonical snapshot apply, and Make Unique paths. A legacy
pattern without a target remains unassigned until the user chooses one.
Serialize new fields as optional so existing Writer sessions and named saves
still load. Piano's persisted `NotePatternNote.midiNote` is its key position.
Fretboard candidates come from
`tunings[state.currentTuning]`, `state.capo`, and `state.numFrets`; a candidate
must produce the note's MIDI pitch. Piano candidates must lie within
`pianoRanges[state.currentRange]`.

```dart
bool canOpenOnInstrument(NotePattern pattern, Set<int> playableMidis) =>
    pattern.notes.every((note) => playableMidis.contains(note.midiNote));
```

Add a Writer instrument-performance view for selecting Piano/Fretboard,
showing the notes on the chosen instrument, and choosing a valid Fretboard
position per note. Persist guitar coordinates with the repository's
zero-based `stringIndex` convention and physical fret. A fret must be between
the capo and `numFrets` (fret zero is available only without a capo), and its
MIDI pitch must equal the corresponding note. Integrate the existing renderers
`lib/features/piano/piano_keyboard.dart` and
`lib/features/fretboard/fretboard.dart` without mutating the user's unrelated
Piano/Fretboard selection state. Validate stored fret positions against the
current tuning/capo/fret count; preserve positions through Piano Roll saves by
note ID and MIDI pitch, reconcile deleted or pitch-changed notes, and preserve
the mapping when a melody pattern is stored in or restored from a canonical
Writer block snapshot.

### New project from Writer

The plus-box action in `lib/features/songwriter/songwriter_header.dart`
currently calls `SongwriterNotifier.newProject()`, which clears the Writer
session for the selected project. It is not project creation. The existing
`ProjectPickerSheet` in `lib/ui/project_picker_sheet.dart` can create a named
Save System project and select it. Writer sessions are project-scoped and
autosaved by `lib/store/songwriter_sessions_store.dart`.

`writerDirtyProvider` in `lib/store/writer_save_binding_store.dart` means the
live Writer differs from its bound named Save (or has content when unbound); it
does not mean the session is not persisted. Its unbound case currently ignores
changes to fields such as project name/config when there are no sections or
drum patterns, so it is not sufficient by itself as the prompt predicate.
Compare the full live session against its named-save baseline or the selected
project's full default snapshot. Keep must flush/retain the outgoing project's
session. Discard restores the active named Writer Save, or clears the session
and binding when no valid Writer Save is bound, while preserving all named
Save entries. Use the same preparation semantics as
`SongwriterNotifier.loadProject(snapshot, saveId)`: preserve the current
project config; run `_forkChangedNamedVersion` against current canonical block
Saves; adopt any forked block entries without overwriting existing Save IDs;
restore the remapped Writer snapshot; and rebaseline the active binding to the
restored materialized content. This is needed when a canonical linked block
changed after the named Writer Save was created. Cancel or failure before
commit must leave the current project and session untouched. Do not use
`newProject()` to implement a separate project.

The current project picker creates and selects a project in one UI action. Add
a Writer-specific creation request/result so the flow can collect the name, an
explicit Piano/Fretboard choice for every new Writer project, and the session
choice before mutation. On Discard, restore the current project's bound active
Writer Save; if none is bound, remove its current Writer session and binding.
Preserve every other named Save entry. Follow the proposed per-project choice
behavior above.
Do not call `SaveSystemNotifier.createProject()` for this route: it mutates and
persists immediately. Instead, prepare an immutable next `SaveSystemState`
containing the new project and its selection, plus the complete next Writer
session and binding maps. Commit these together in one shared Writer journal
transaction.

The current `commitWriterTransaction` publishes memory before its asynchronous
storage writes finish. Add a staged/commit-after-persist transaction path for
this project switch: do not publish the prepared state or select the new
project until the journaled payloads are durably applied. Establish a project
write fence before preparing state: block Writer edits and project/Save
mutations, cancel or absorb pending session/binding debounce timers, drain
already-enqueued writes on the shared journal queue, then capture the complete
prepared payloads. Keep the fence through persistence and in-memory publication
so timer callbacks or other queued listeners cannot append stale session,
binding, or Save System snapshots after the new transaction. Release it only
after publication and resume normal persistence scheduling. If failure occurs
before the journal is accepted, keep all current state untouched and release
the fence. If failure occurs after journal acceptance, replay the complete
idempotent transaction; once replay succeeds publish or rehydrate the exact
prepared in-memory state before releasing the fence. If replay also fails,
retain the recovery lock and surface the failure rather than allowing more
project writes. Cancellation at any prompt creates no project.

`SongwriterNotifier` currently writes the outgoing live state into
`songwriterSessionsProvider` on every project selection change. Add a one-shot
switch disposition for this Writer-created transaction: Keep must persist the
prepared outgoing session; Discard must preserve the prepared restored/removed
state instead of letting the listener overwrite it with stale live state.
Apply the selected project and session only as part of the prepared
transaction, then release the fence. Test by returning to the old project
after the switch and verifying that Keep or Discard produced exactly the
chosen state.

## Proposed files

- `lib/features/songwriter/songwriter_screen_sheet.dart` — validated guitar-only strum
  source dropdown, per-tile event preview, exact melody duration/placement
  label, and melody reuse/create/placement flow.
- `lib/features/songwriter/guitar_strum_pattern_sheet.dart` — detailed editor
  remains; change copy only if needed to connect it to the tile preview.
- `lib/features/songwriter/songwriter_melody_pattern_editor.dart` — retain the
  Piano Roll and preserve Writer performance state when saving edits.
- `lib/features/songwriter/songwriter_melody_performance_editor.dart` (new) —
  choose a pattern's Piano/Fretboard target, inspect notes on that instrument,
  adjust per-note playable position, and explain unavailable notes.
- `lib/features/piano/piano_keyboard.dart` and
  `lib/features/fretboard/fretboard.dart` — add only the controlled note
  overlay/selection hooks needed by the Writer performance view, if reuse is
  feasible without touching global workspace state.
- `lib/models/songwriter.dart` — backward-compatible per-pattern performance
  state, canonical `WriterBlockSnapshot` state, `strumAnchorMigrationVersion`
  on `SongwriterProjectSnapshot`, and JSON serialization; no generic Song
  pattern schema change.
- `lib/schema/rules/songwriter_melody_instrument_rules.dart` (new) — enumerate
  valid MIDI/Piano and string/fret positions and validate stored positions.
- `lib/schema/rules/songwriter_rules.dart`,
  `lib/schema/rules/song_from_writer_rules.dart`, and
  `lib/schema/rules/songwriter_playback_rules.dart` — preserve strum source
  invariants and carry/resolve canonical melody performance state.
- `lib/store/songwriter_playback_store.dart` and
  `lib/store/song_project_store.dart` — pass the effective Harmony default
  into playback, Song import, and Song-from-Writer preview rule calls.
- `lib/store/songwriter_store.dart`,
  `lib/store/songwriter_sessions_store.dart`, and
  `lib/store/writer_save_binding_store.dart` — state operations for validated
  anchors, one-time legacy migration for sessions, named Writer Saves, and
  serialized binding baselines while preserving dirty-state deltas,
  placement bounds/history grouping, performance reconciliation, complete
  dirty detection, the Discard restore equivalent to `loadProject`, and
  pausing/draining debounced writes during the project write fence.
- `lib/store/writer_save_sync_store.dart` and
  `lib/store/save_system_store.dart` — staged journal commit and immutable
  project-creation state, shared-queue drain/fence, and recovery publication so
  the new project and Writer disposition form one recoverable transaction.
- `lib/features/songwriter/songwriter_header.dart` and
  `lib/ui/project_picker_sheet.dart` — expose a clearly labeled Writer project
  creation action, collect the current-session decision, and use the confirmed
  per-project instrument-selection behavior without changing other screens.
- `PRODUCT.md`, `README.md`, `docs/song_writer_guide.md`, `docs/songwriter.md`,
  and `docs/save_system.md` — document the
  shipped strum assignment/previews, melody reuse/duration/position mapping,
  and Writer project creation flow. Update `DESIGN.md` only if this changes a
  shared interaction principle or visual token.

## Verification results

- Focused Flutter suite: 142 tests passed across Writer timeline, Harmony
  sources, performance mapping, project creation, persistence, migrations, and
  Song export. `flutter analyze` reported no issues; formatting and
  `git diff --check` passed.
- Independent backend review found no concrete findings. Independent UI review
  caught an orphan-anchor label regression; it was corrected so resolved,
  unassigned, and unresolved anchors render distinctly. A second fresh-context
  UI review passed.
- On the already-running iPhone 17 Pro simulator, a separate QA Writer project
  was created using Keep, then used to exercise A–B–A–B pattern reuse/creation,
  visible duration and placement, melody performance target selection, and the
  Guitar Strum lane gate. The Strum action disappeared when all Harmony lanes
  were Piano and returned when a Fretboard Harmony lane was restored. The
  compact portrait and wide layouts rendered without framework errors.
- Note entry through the simulator's Piano Roll canvas was not reliable via UI
  automation. Per-note position persistence and compatibility are covered by
  the focused widget, rule, and store tests.

## Approval history

The plan was reviewed by a fresh-context GPT-6 Sol agent and approved by the
user before implementation. After implementation, an independent backend
review passed, the UI review's concrete finding was fixed, and a second fresh
GPT-6 Luna review passed. The user-confirmed Keep/Discard/Cancel and project
restore semantics are reflected above.
