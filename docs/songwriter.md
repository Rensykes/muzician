# Songwriter

Writer is Muzician's section, chord, and lyric sketch. A song is a list of
**sections** (verse, chorus, … — free, optional labels); each section stacks
parallel **lanes** for harmony, saved voicings, drums, melody, guitar strum,
and audio. Recoverable block content links to a canonical save in the selected
project's Save System; placement and lyrics stay with the Writer block. If a
save and its fallback content are both unavailable, Writer keeps the block
visible as broken rather than inventing replacement content.
Use Writer to shape the song's sections. **Song is temporarily unavailable in
V2**; its saved arrangements and clip-arranger implementation are retained.

Writer is the first workspace on a new install. After startup it restores the
last available content workspace (Fretboard, Piano, Roll, or Writer); a saved
Song destination falls back to Writer. Opening Settings does not change that
preference.

## Studio workspace

Writer follows the persistent **Studio** or **Studio Muzician** appearance in
Settings. Editable project context and draft status come first. The next row
pairs the Writer title with **Save version** and labelled Undo, Redo, and
Writer versions icons. **Save version** saves through the existing named Save
flow; **Writer versions** opens whole-project versions alongside **Section
blocks**. **Draft** means the active project session is saved automatically.
**Draft changed** means it differs from the bound named Writer version; it is
not a warning that the draft will disappear. The Writer menu retains New
project, Undo/Redo, version browsing, structure editing, and project renaming.

The unframed transport exposes key, BPM, play/stop, and metronome. It wraps at narrow
widths and larger text sizes. Its key and BPM values use a single compact line;
all transport and history controls retain 44-pixel touch targets. The Writer
menu keeps these commands available as well. Project-key changes still require
confirmation.

Sections keep their name, bars, repeat count, Mixer icon, and **Section actions**
menu in a compact row, reflowing when space is limited. **Remove section** lives
in that menu and remains recoverable with Undo. Harmony lane headers identify
the source instrument and keep rename, instrument change, duplicate, and delete controls.
Fretboard Harmony also exposes **Sound: Clean / Distorted**, shared with Fretboard
audition, Writer Harmony and Guitar Strum, and legacy Melody guitar playback on
this device. Explicit Melody lane sounds are independent. This preference changes
the timbre without changing saved notes, lane identity, or project history.
Drums, Sample, Guitar Strum, and Melody headers each have a delete control.
Confirming removes that lane and its placements from every repeat of the
section; saved ideas remain available, and Undo restores the lane. Section
lyrics are unchanged.
Four-bar rows show
chord, degree when known, linked Save name, and the current verse's lyric.
Filled cells start at 64 pixels and empty add slots at 44; a distinct Save name
or a lyric adds the space its text needs. Larger text scales grow the cells.
Exact Harmony labels remain literal and gain no inferred degree. A single
section uses the available width; multiple sections flow into two columns
only at widths of at least 1100 logical pixels.

Tapping a block opens its contextual sheet. Common play, chord-change, and
verse-lyric actions appear first, with every applicable advanced action below:
voicings/library, replacement, native instrument editing, rename, standalone
Save, and removal. This reuses the existing editor flows rather than introducing
a second editor with separate musical state.

Guitar Strum keeps its title, explicitly labelled **Source** selector, and delete
control together, wrapping when space is limited. **Unassigned**
remains visible and silent. Pattern placements use neutral strips with accented
down/up previews; the pattern name, continuation, shared Save menu, and tap to
edit remain available. Narrow single-bar placements stack their content to
keep the controls usable. Its editor follows the canonical project beat grid:
four 16th steps for a quarter-note beat and two for an eighth-note beat. Beat
groups keep their bar/beat label and 44×44 step targets; steps can wrap inside their group on
compact screens. Groups never cross bar boundaries. The sheet scrolls for longer
patterns and short viewports. Down → up → off behavior is unchanged. Shared
drum editors also group steps by beat and scroll on short screens.

Writer's chord, library, mixer, audio, drum, strum, structure, and melody editors
follow live appearance changes. An open melody Piano Roll keeps its isolated
notes, tool, and snap setting; only **Save** commits its edits to Writer.
The mixer uses compact lane rows separated by dividers, with volume, pan,
rename, and mute controls, rather than a bordered card around each lane.

---

## Data Model (`lib/models/songwriter.dart`)

| Type | Description |
|---|---|
| `SongwriterProjectSnapshot` | `InstrumentSnapshot` subtype (`type: 'songwriter'`) — `config`, ordered `sections`, Writer-specific per-pattern performance state, and the strum-anchor migration marker. |
| `SongwriterConfig` | `tempo`, `beatsPerBar`, `beatUnit`, optional `keyRoot` (pitch class) + `keyScaleName`. |
| `SongSection` | `id`, optional `label`, `lengthBars`, `order`, `repeat`, `lanes`. |
| `SongLane` | `id`, `kind` (`harmony`, `save`, `drum`, `melody`, `guitarStrum`, or `audio`), optional `label`, `order`, `repeat`, `blocks`; Harmony lanes carry a fixed Piano or Fretboard identity, a strum lane stores its selected Fretboard Harmony source, and a Melody lane may carry an explicit `melodySound`. |
| `SongBlock` | `id`, `startBar`, `spanBars` (+ `endBar` getter), canonical `saveId`, and local lyrics/placement; pattern lanes reference their pattern id; legacy content fields and `embedded` snapshot are fallback data. Harmony extras include `chordSymbol`, `chordQuality`, `chordRootPc`, `chordNotes`, and `romanNumeral`. |
| `NotePattern` / `GuitarStrumPattern` | Melody pitches, local ticks, durations, and optional millisecond onset offsets; strum direction events on a 16th-note grid. Writer melody performance state is stored alongside the pattern. |
| `WriterMelodyPerformance` | Per-pattern Piano or Fretboard target; Piano uses each note's MIDI key, while Fretboard positions map note IDs to playable strings and physical frets. |

All types are immutable (`copyWith` / `toJson` / `fromJson`). A block resolves to
its valid same-project `SaveEntry` first, then to retained fallback content if
the save is missing or corrupt. An unrecoverable reference remains visibly
broken.

### Block saves, sharing, and section folders

Each Writer section has a managed folder directly under the selected project;
folder identity follows the section ID, so same-named sections remain separate
and section repeats do not create extra folders. Category folders beneath it
group linked saves by lane kind: Harmony, Voicing, Drum, Audio, Melody, and
Guitar strum. Each recoverable source block has one canonical `SaveEntry` and
one link to its section/category. Repeated renderings of the same source block
reuse that link. The Save browser shows linked entries inside the category
folder while retaining one canonical save record.

The app-wide **Default Harmony instrument for new projects** setting selects
Piano or Fretboard for projects created through the usual project flow. If it
is unset, that flow asks before creating the first project and stores the
choice in Settings and the project's config. **New project** in Writer asks
for Piano or Fretboard on every creation, stores the choice only in that
project's config, and leaves the app-wide setting unchanged. Each new section
starts with one primary Harmony lane using its project's default. Additional
Harmony lanes choose their instrument when created. An empty Harmony lane with
no anchored Save/Voicing lane can change instruments without changing its lane
ID. Existing projects keep their stored default.

Writer's main-menu **New project** creates and selects a separate Save System
project
with an empty Writer session. When the current Writer session differs from the
bound active named Writer Save, or from the full project-default session when
unbound, choose **Keep**, **Discard**, or **Cancel**. **Keep** retains the
outgoing project session. **Discard** restores the bound Save through the same
canonical reconciliation used for loading a named version, keeps the current
project config, and forks changed linked block content when needed. When no
valid Writer Save is bound, Discard clears the current project's Writer
session and binding. Both Discard paths preserve every named Save entry.
**Cancel** leaves the current project untouched and creates no project.

**Add chord** creates one Harmony block and one linked `HarmonyChordSnapshot`
in that section's Harmony folder. The snapshot keeps the Writer chord and its
native Piano/Fretboard realization together. No separate visible Save block is
created for the chord. Harmony library choices must match the lane instrument.
The block action sheet opens its native Piano or Fretboard editor. Exact Piano
or valid Fretboard Chord selections also become Harmony, retaining the chosen
name and native notes even without recognition. They appear in Harmony Library
and offer **Change chord** and **Replace chord**. Root, quality, and Roman
numeral remain absent until the user explicitly chooses a chord; theory and
voicing suggestions require that identity. Exact Harmony playback retains
octaves and instrument positions in Writer, strums, and Song import.
Free Fretboard selections remain savable and loadable for exploration but
cannot be imported into Writer or used in its playback. Chord selections
must have one valid position per string; a mode change does not remove
duplicate-string notes automatically.

Editing a shared Harmony save warns when it is linked in multiple places and
offers **Update all placements** or **Create standalone Save**. Updating all
changes the canonical save. Creating a standalone Save copies the complete
composite to a manual Save in the project root and leaves Writer blocks and
links untouched; use **Replace chord** in Writer to bind it to one placement.
Replacement preserves that block's bar, duration, repeats, and local lyrics.
Both a fresh instrument selection and a reused Harmony Save retain the lane's
position and primary identity, preserving dependent Save and strum targets.
An exact-note replacement validates the newly selected native notes, including
their register, rather than the old realization. A failed handoff ends with
feedback; the destination picker repeats only after **Choose another bar**.
The Harmony block action sheet uses **Create standalone Save**; **Make Unique**
keeps its detach behavior for other Writer block and Save-lane kinds.

Deleting a Harmony lane also deletes its dependent Save/Voicing lanes in the
same undoable change, and the confirmation names that impact. A Save/Voicing
lane with a stale explicit anchor stays visible in its own unresolved row and
offers only compatible Harmony lanes for repair; it never falls back to the
primary lane. Tap a Save block there to edit it in its native instrument when
that editor is available, or choose **Remove save**. If no Harmony lane can
accept the blocks, the row offers **Remove lane**.

A Guitar Strum lane uses one explicitly selected Fretboard Harmony source.
Within a section, each source can be assigned to only one Guitar Strum lane.
Source choices hide lanes occupied by another strum lane and retain the
editing lane's own current source. An unassigned strum lane reserves nothing.
A strum lane can be added only when an unused source exists, and selecting the
primary lane still stores its ID. If its saved
source is removed or changed to Piano, it shows **Unresolved** and stays silent
until repaired; a truly unassigned lane shows **Unassigned** and never follows
the primary lane. A legacy null
anchor is migrated once from the old primary-Harmony rule only when that source
resolves to Fretboard. If it resolves to Piano or is absent, the anchor stays
unassigned; a versioned null anchor stays unassigned when a guitar lane is
added later.

Fretboard and Piano saves made outside Writer stay in the project root as
ideas. **Use in Writer** promotes an eligible native idea to a Harmony Save
under the same ID and folder; all placements share edits until one is made
unique. Existing Save/Voicing links retain that native realization. Writer-created
saves live in a section folder while linked. Removing their last block moves
them to the project root. Manually created saves keep their original folder.
Managed section folders cannot be directly renamed, moved, or deleted in the
instrument Save browser. The Writer Section blocks view and instrument save
browser can rename a linked save; the new name applies to every placement that
uses it. Remove or reposition its Writer block through Writer. Using a saved
Writer-native block restores its pattern or clip data and copies its default
lyrics into the new placement once; later lyric edits remain local.
`WriterBlockSnapshot.defaultLyrics` stores that initial seed, so edits to one
placement do not change what another new placement receives.
Linked Melody and Guitar Strum tiles expose **Rename** and **Make Unique**
alongside their block actions. Melody also offers **Adjust placement**,
**Repeat / reuse**, and **Edit performance** in the same menu.

## Rules (`lib/schema/rules/songwriter_rules.dart`)

The chord wheel requires exactly seven scale degrees. With a pentatonic, blues,
whole-tone, diminished, or unsupported scale, **Change chord** opens the existing
root/quality picker directly while retaining the project key. A configured key
is never presented as missing merely because the wheel cannot represent it.
Wheel chord symbols and Roman numerals follow the device's text-size setting.
Each of the seven degrees exposes a labeled accessibility action that selects
the same chord as its visible wedge.

KEY, chord tools, and musical previews use the global Sharps/Flats preference.
Custom Save names and exact Harmony labels stay literal; recognized slash chords
preserve their bass note when displayed in either spelling.

| Function | Purpose |
|---|---|
| `romanNumeralFor(chordRootPc, quality, keyRootPc?, keyScaleName?)` | Diatonic Roman numeral for a chord in a key, or `null` (no key / non-diatonic). Cased by quality (`dim` → `vii°`, minor → lowercase). |
| `resolveSnapshotChord(snapshot)` | The chord a save block resolves to, for degree display: prefers the snapshot's explicit `pendingChord`, else detects one from `selectedNotes` via `detectFirstChord`. Returns a `ResolvedChord(rootPc, quality, symbol)` or `null`. |
| `saveBlockRomanNumeral(snapshot, keyRootPc?, keyScaleName?)` | Convenience: `resolveSnapshotChord` + `romanNumeralFor`. The Roman numeral a save block maps to in the key, or `null`. |
| `blocksOverlap(existing, candidate)` | Half-open overlap check within a lane; touching edges and gaps are allowed; self (same id) ignored. |
| `makeSection` / `makeLane` / `makeSaveBlock` / `makeHarmonyBlock` | UUID-stamped factories. |
| `flattenedBarCount(sections)` | Total bars after expanding section repeats (Σ `lengthBars * repeat`). |
| `laneNaturalLength(lane)` | Lane pattern length = max `block.endBar` (0 if empty). |
| `tileLaneBlocks(lane, sectionLengthBars)` | Expands a lane's blocks, tiling the pattern `lane.repeat` times from bar 0, clipped to the section length (a placement starting at/after the section end is dropped; a block spanning past the end is kept). |

### Repeat semantics

Playback flattening expands **section** repeats (whole section loops N×) and **lane**
repeats (the lane's block pattern tiles N× from bar 0, clipped to the section).

### Melody and guitar-strum lanes

Melody blocks point to reusable patterns. At an empty bar, choose **Use existing
pattern** to place another block linked to a selected pattern, or **Create new
pattern** to start one in Piano Roll; reuse preserves the shared pattern and its
performance mapping, including A–B–A–B arrangements. Pattern duration is its
actual `lengthTicks`, shown as bars plus any remaining beats and ticks. The
block's `spanBars` is shown separately against the section's total bars. A new
block uses the pattern's full duration in bars when that placement is valid;
it may be shortened to fit or rejected if no valid placement is available, even
when bars appear free, because existing automatic repeat origins must be
preserved. Placement can be shortened or extended subject to the same rules.
Patterns repeat from the block's left edge when the placement is longer, and
notes clip at the block edge when it is shorter. A
later duration edit to a reused pattern does not resize its existing blocks.

The Melody timeline wraps every four bars with numbered rows and continuation
segments. Blocks show a non-interactive miniature piano roll: horizontal notes
follow the placement's loops and clipped edges, with consistent pitch height
across rows, below a separate name strip. Linked previews refresh together;
missing patterns and missing or incompatible canonical Saves show a warning,
not cached notes. The detail row identifies unresolved melody content separately
from an empty pattern. Edit notes in Piano Roll, not in the preview. Drag the
final edge in whole bars to resize; releasing creates one undo step, while
cancelling leaves the placement unchanged. Hold the drag near
the top or bottom of the Writer sheet to scroll to additional rows. The block's action
menu also offers **Adjust placement** to move or resize without a gesture.
Automatic lane repeats are marked as repeats and reserve their occupied bars;
their visible occupancy is clipped at the section edge. Placement changes also
cannot shift or remove existing automatic repeat origins by changing the lane's
natural period; the placement dialog explains repeat conflicts. Adjust the lane
repeat first with the Melody lane's **Repeat** control if needed. **Repeat / reuse** selects an
available starting bar in the same lane and creates a linked placement, shortened
as needed to satisfy placement rules; a free start can still be rejected if no
span preserves existing repeats. Missing patterns and missing
or unresolved canonical Saves cannot be repeated. Reuse shares the pattern and
canonical Save, so shared edits affect both placements; **Make Unique** detaches
only the selected placement. Resizing does not alter the shared pattern. A
separate edit button and block actions remain available on narrow screens.
Missing references stay visible with a recovery action. **Delete placement**
removes an authored placement and its own automatic repeats, but refuses to move
another block's repeat origins. A clipped block can be dragged back inside a
shortened section. Incompatible canonical Saves remain unchanged and cannot be
edited or made unique through the incompatible placement.

Each melody pattern has one Piano or Fretboard performance target. Piano
positions use the note's MIDI key. Fretboard positions store a playable string
and physical fret per note and must match the note's pitch under the current
tuning, capo, and fret count. The target and positions persist with the Writer
session and in canonical Writer block saves, so reopen and reuse preserve them.
The target chooses the physical view and mapping independently of the Melody
lane's **Sound**: Piano, Clean guitar, or Distorted guitar. Newly created Melody
lanes default to Piano. Older lanes without an explicit sound display **Pattern
sounds**: each pattern's performance target chooses piano or guitar, and guitar
uses the shared device tone until a sound is chosen. An explicit choice affects
only that lane, not the global guitar tone or performance mapping, and takes
effect on the next transport start. Positions follow a note through Piano Roll
edits by note ID and MIDI pitch; a removed or pitch-changed note must be mapped
again. The selected instrument
performance view and position editing are blocked if any note is outside the
current Piano range or Fretboard's playable positions; Piano Roll remains
available to correct notes. These Writer-only mappings are kept beside the
shared `NotePattern`, not added to the Song pattern schema.

Guitar-strum placements must stay within the section and not overlap authored
blocks in their lane; Melody's repeat-aware restrictions do not apply. Strum
blocks open a 16th-note grid with down, up, and off steps. Each tile previews
the pattern's ordered down/up events. A strum lane uses its explicitly selected
Fretboard Harmony source; an unassigned or invalid source stays silent until repaired, including when the
primary Harmony lane changes. If the selected source has no chord at a step,
the strum is silent. Chord tones start 12 ms apart and each voice is gated for
half a beat. When a melody or strum voice reaches a pattern, block, or section
edge, its duration is shortened by its onset delay so its release stays inside
the clipped window.

All Writer and Song ticks share one tempo conversion: four ticks per quarter
note, or `60,000 / (tempo × 4)` milliseconds per tick. The time signature sets
the number of ticks in a bar, not the wall-clock duration of a tick. At 120 BPM
a 4/4 bar lasts 2 seconds and a 6/8 bar (12 ticks) lasts 1.5 seconds. Live
playback, Song audio clip placement/seek/length, and WAV note positions use the
same conversion. Sub-tick onset offsets and boundary duration trims are
preserved when importing or editing Song note patterns.

### Playback audio (`lib/schema/rules/songwriter_playback_rules.dart`)

`flattenPlaybackEvents(project, saves)` turns the whole project into a sorted,
tick-indexed event list the transport walks:

- **Harmony blocks** sound their chord as a per-bar stab (block start + every bar
  boundary inside the block, clipped to the section). Named exact Harmony
  uses native MIDI notes or fret positions in their original register.
  Symbolic Harmony uses `chordNotes` stacked ascending from octave 4, falling
  back to `chordRootPc` + `chordQuality` intervals. Silent blocks stay silent.
- **Save blocks** resolve their canonical save first, then retained fallback
  content, and sound the voicing the same way: piano keys use
  `PianoCoordinate.midiNote`, fretboard
  cells map string+fret through the tuning. Broken blocks are silent.
- **Drum lane blocks** fire their referenced `DrumPattern` hits at native tick
  resolution, tiled across the block's bar span.
- **Melody lane blocks** play duration-aware notes, looping their pattern from
  local tick zero and clipping voices at the block/section boundary.
- **Guitar-strum blocks** resolve each down/up step against their explicitly
  selected Fretboard Harmony source and stay silent when it is unassigned or has
  no playable Harmony at that step. Named exact Harmony uses its native
  register and positions here as in ordinary Writer playback and Song import.
- The metronome click is unchanged and still gated by `settingsProvider.metronomeEnabled`.

Sinks are injectable providers (`songwriterNoteSinkProvider`,
`drumPatternPlaybackSinkProvider`, `songwriterMetronomeSinkProvider`) so tests can
capture events. The sheet UI highlights the active bar cell via
`songwriterActivePositionProvider` (global bar → section instance + local bar) and
auto-scrolls the active section into view.

### Drum pattern editor (`lib/features/song/drum_machine_editor.dart`)

Drum-lane blocks open the shared `DrumMachineEditorBody` — a step grid plus a
transport row. Beyond tapping individual steps it offers:

- **Clear all** — a transport button (with a confirm dialog) empties every lane.
- **Per-lane fills** — each lane's menu places hits *every N steps* (with a start
  offset) or by a *Euclidean* (Bjorklund) distribution, plus clear-lane. Pure
  generators live in `lib/schema/rules/drum_fill_rules.dart`.
- **Backing audition** (Songwriter only) — a **Backing** toggle loops the section's
  harmony chords under the pattern (loops at section length; the pattern tiles).
  Source: `sectionHarmonyLoop` in `songwriter_playback_rules.dart`.
- **Drum library** (Songwriter only) — a **presets** picker (16 built-in loops/fills
  in `lib/schema/rules/drum_presets.dart`) and **My loops** (custom loops saved as
  `DrumLoopSnapshot` through the save system; see `docs/save_system.md`). Applying a
  preset or a loop overwrites the current pattern in place, keeping its id so the
  referencing block stays linked.

The Songwriter drum sheet opts into the library and backing via `enableLibrary` /
`backing` on `DrumMachineEditorBody`; the Song feature embeds the same body without
them, so neither surface appears there.

## Store (`lib/store/songwriter_store.dart`)

Provider: `songwriterProvider` (`NotifierProvider<SongwriterNotifier, SongwriterProjectSnapshot>`).

| Method | Description |
|---|---|
| `newProject()` | Reset the active project's Writer session. Writer's **New project** action creates a separate Save System project and uses the protected project-switch flow described above. |
| `setKey(root, scaleName)` / `setTempo(tempo)` | Config edits; `setKey` recomputes harmony-lane Roman numerals. |
| `addSection` / `addLane` / `addSaveBlock` / `addHarmonyBlock` / `removeBlock` | CRUD; block adds that overlap are ignored. |
| `addMelodyPattern` / `addGuitarStrumPattern`, their block adders and update methods | Create and edit looped note and strum patterns. |
| `setBlockPlacement(...)` | Move or resize while preserving pattern content; Melody validation also protects expanded repeat occupancy and existing repeat origins. |
| `repeatMelodyBlock(...)` / `setMelodyLaneSound(...)` | Create a linked placement at a valid start / set an explicit sound for one Melody lane. |
| `insertInstrumentSelectionAtBar(...)` | Adds a named, saved chord or exact Fretboard/Piano snapshot to a Writer lane after section/bar selection and a name prompt. |
| `makeBlockUnique(...)` | Copy the canonical save and detach the selected placement; one Writer history step. |
| `loadProject(project)` | Replace the active Writer session from a named Song version, materializing its retained block content when shared saves have since changed. |

Writer's **Add chord** action creates a named canonical Harmony save, using the
chord symbol as its default name. Block actions can rename the save, replace a
chord from the compatible Harmony library, or open its native Piano/Fretboard
representation. A shared-save edit offers **Update all placements** or a
standalone Save; the latter does not rebind blocks automatically.

The notifier no longer exposes a public `hydrate()`. Instead, `build()` listens
to `saveSystemProvider.selectedProjectId` changes. When the project changes the
outgoing session is immediately persisted via `songwriterSessionsProvider.put`
when its folder still exists, and the incoming session is loaded via `.get`. If
no session exists for the new project, `_defaultFor(next)` creates one seeded
from the folder's `ProjectConfig`. Deleting a project removes its Writer draft
and named-save binding in the same recoverable transaction as its Save System
tree, so selection changes cannot restore a deleted draft.

### Session auto-save

Sessions live in `@muzician/songwriter_sessions/v1` — a per-project map of
`Map<String, SongwriterProjectSnapshot>` keyed by project ID. On project switch
the outgoing session is persisted immediately and the incoming session is
loaded from the map (or seeded via `_defaultFor` when no session exists yet);
leaving the project clears to empty. Startup reconciles Writer blocks with
their section folders and canonical saves before exposing the workspace.
If a linked save and its retained Writer fallback differ during startup,
reconciliation keeps both: the block uses a new section save made from the
fallback, and the prior canonical save remains in its folder or moves to the
project root when it was Writer-owned and has no remaining links. A recovery
banner stays visible until **Review both versions** opens **Section blocks**, where both
versions can be inspected.

## Undo / Redo

Writer's overflow menu contains **Undo** and **Redo**; Studio also exposes
labelled history icons beside **Save version** and the version-browser icon. Both controls have
accessible button labels, can be reached with Tab, and activate with Enter or
Space. The active project keeps up to 50 prior immutable snapshots in memory,
including melody and strum
patterns and audio references. Text dialogs apply once when saved, confirmed
pickers and other dialogs commit once, and canceling discards a text draft;
drag and slider gestures commit once on release. A new edit after Undo clears
Redo. Switching projects, choosing
**New Writer Project**, or loading a named save/snapshot clears both history
branches. Deleted Writer audio blocks leave their source files in the local
repository so undo can restore their references. Delete snackbars call the same
history Undo command and close if a later edit changes the history revision.

## Scale degrees on bar cells

Both bar-cell kinds in the sheet grid (`songwriter_screen_sheet.dart`) show a
Roman numeral under their label when the chord is diatonic to the project key:

- **Harmony cells** render `block.chordSymbol` + `block.romanNumeral` (computed
  at block creation and recomputed when the project key changes).
- **Save cells** resolve their snapshot's chord via `saveBlockRomanNumeral`
  (`pendingChord`, else detected from the saved notes) and render it under the
  save name, keyed `saveRoman_<blockId>_<instance>`.

A named exact Harmony Save intentionally has no chord identity; it does not
fall back to chord detection to invent a Roman numeral. A non-diatonic chord
(or no key) yields `null` and no numeral is shown — only
the symbol/name. Example in C major: a saved F-major voicing shows `IV`.

## Save / Load

The Writer save panel has two views:

- **Writer versions** save and load a whole `SongwriterProjectSnapshot`. Saving
  captures current canonical content for every resolvable block, including
  patterns, clips, and required audio metadata. Loading restores that version's
  recoverable musical content without overwriting shared root saves or changing
  the stored version.
  If a referenced save has changed since the version was captured, Writer
  creates a new Writer-owned save for that older content and keeps blocks that
  shared the same save linked together. A load starts clean against the
  materialized version.
- **Section blocks** browse, rename, and use individual linked block saves.
  A same-project Writer-native save in the project root or a managed section
  folder can be placed with **Use in Writer**, restoring its pattern or clip
  and seeding local lyrics. Reusing a save in another section adds a link to
  the same canonical save. The destination picker asks for a section, one of
  that section's matching lanes, and a bar; when the section has no matching
  lane, Writer creates one. Guitar-strum placements keep the selected lane's
  harmony anchor. An invalid start bar shows an inline error and keeps the
  entered value available for correction. A Writer block save is not offered
  as a whole-project load.

The panel is scoped to the selected project's folder, keeping both views inside
the project subtree. If a Writer version records different tempo, meter, or key,
Writer summarizes the difference before loading and applies the current
project config to the active session. The saved version remains unchanged.
Project config retrofits do not rewrite named Writer versions.

The Writer save sheet keeps its title and tabs fixed while each Save Browser
scrolls its own contents, so saves remain reachable on short screens.
Its top-right Close action has a screen-reader label.

`songwriterCaptureForTest` exposes the current snapshot for widget tests.

## Project Config

Writer uses `SaveSystemState.selectedProjectId` instead of the old
folder-name convention. When a real project is selected (kind `project`),
tempo is edited through the project config sheet. The key chip opens a
project-key picker; setting, changing, or clearing tonic and scale/mode asks
for confirmation before updating the project. Fretboard and Piano use the
same confirmed project-key workflow. Cancel leaves the project unchanged,
and a dialog opened for another project cannot update the current one.
Instrument handoff asks the user to select a real project if
there is no project selected or Dump is active.

`projectConfigSyncProvider` (`lib/store/project_config_sync.dart`) pushes the
active project's tempo, meter, and key into the songwriter and Song stores
whenever a project is selected or its config changes. Changed master config
clears stale local undo history; an equal sync keeps current history. Key sync
also recomputes Writer Roman numerals. Project key is authoritative when
loading an instrument Save, including Piano Roll; the Save's embedded scale
does not replace it. Dump and no-project scale choices remain local. A named
Song version load keeps the active project config after showing any differences
from that version. When loading a project that has no session yet,
`_defaultFor` seeds a new `SongwriterProjectSnapshot` from the project folder's
`ProjectConfig` (name, tempo, beatsPerBar, beatUnit, keyRoot, keyScaleName).

Library-match scope is `getSavesInSubtree(folders, saves, selectedProjectId)`.

## Fretboard and Piano handoff

In either instrument's detection panel, choose **Add to Writer**, select a
detected chord or **Add exact notes as Harmony**, then choose a section and bar.
Writer prompts for an editable save name before committing; the chord symbol is
the default for a chord. A detected chord keeps its symbol, root, quality, and
selected pitch names. An exact selection keeps the full instrument snapshot.
Exact Piano and valid Fretboard Chord selections need no recognized chord:
they retain their chosen name, native notes, and nullable symbolic identity,
and appear in the Harmony Library with Change chord and Replace chord.
Free Fretboard selections remain savable and consultable outside Writer.
If the active project changes while the picker is open, Writer cancels the
transfer and explains why. Occupied bars are labeled for assistive technology
and offer replace-with-confirmation, choose-another-bar, or cancel.
Occupied bars include expanded lane repeats. Replacing one of those copies
updates the source block in place, preserving its ID, start, span, and repeat
offsets so every copy receives the new chord or snapshot together.

If no project is selected, the existing project picker opens before placement;
dismissing it leaves the instrument selection and Writer unchanged. If the
project has no Writer section, Writer offers to create its default eight-bar
section. The blank Writer state also has a visible **Start an 8-bar section**
action. A separately saved Fretboard/Piano idea can be linked from the project
root with **Use in Writer**; a fresh instrument selection creates a new save.

Studio section Bars and Repeat use plain text disclosures with chevrons and 44-pixel targets; both open the existing steppers. Save version is also a text action. Mixer keeps its tooltip on compact screens and shows a label on wide screens. Chord-cell boundaries remain visible because they represent musical placement.

Studio Harmony cells in a mixed row share the tallest cell’s height so their top and bottom edges align. Entirely empty rows retain compact 44-pixel slots; scaled text, lyrics and Save names can increase row height.

### Playback correctness and voice lifetime

Harmony plays the saved native Piano register/inversion and Fretboard positions.
Clean/Distorted is the shared device preference exposed on Fretboard Harmony;
explicit Melody lane guitar sounds override it for that lane.
Simultaneous Harmony notes share one PCM source, reducing six-note chord source
bindings from six to one. The Distorted amplifier uses bass filtering, two
saturation stages and cabinet filtering with oversampling.

Generated notes release against their requested onset and duration, including
preparation time. Stop cancels pending starts; old voice cleanup cannot release
a new run's voice. Rapid strums end by the next stroke, short bars bound Harmony
stabs, and the transport completes after the final tick interval. These are
verified with deterministic platform and transport tests; physical iPhone
listening and latency measurements remain separate validation.

The October 2026 simulator check used populated, isolated fixtures with the
production instrument and Writer widgets on iPhone 18 Pro and iPad Pro 11-inch
(M5), running iOS/iPadOS 27. It exercised Full/Solo, Chord/Free, the shared
Clean/Distorted selector, note audition, and Writer Play/Stop. Compact and wide
layouts were inspected at runtime; the 320-pixel layout and enlarged text also
have widget regression coverage. This check does not measure physical-device
audio latency or establish a subjective listening assessment of the guitar tone.
