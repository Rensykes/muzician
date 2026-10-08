# Spelling, Harmony editing, Save panel, and iPhone playback corrections

Status: revision 2 APPROVED by a fresh GPT-6.1 Sol extra-high reviewer and by
the user on October 7 ("proceed"). State/Harmony and UI implementation reviews
have passed, as has profiling capture readiness. Final integrated source checks,
debug Simulator smoke checks, normal-app restoration, and temporary preview
cleanup are complete. On the latest physical-phone retry, signing and developer
disk-image preparation succeeded, the user authorized the development certificate,
and USB makes the VM profiling service reachable. Initial physical Writer samples
have been captured; the full baseline matrix and playback repair remain pending.

This extends the approved October 4 work, preserved with its tests in the
October 8 checkpoint requested by the user. The October 4 suite passed 1,211
tests, but that verification did not cover
the newly reported cases. Review approval does not yet cover the whole playback
scope. State/handoff and display reviews have passed; the diagnostic reviews and
physical-device limitation are recorded below.

## Confirmed context

- A global persistent Sharps / Flats setting applies to musical labels throughout
  the application. Custom Save names and exact Harmony labels remain literal.
- Project tonic and scale/mode remain canonical and require the existing key-change
  confirmation. Changing spelling changes presentation, not the musical key.
- Old data migration is outside scope; the existing user decision permits a fresh
  start. Do not erase user data to implement or test these fixes.
- Writer playback is slow on an iPhone 16 Pro Max launched through Codex.
  Fretboard and Piano audition work normally. The original phone build mode is
  unverified. A connected phone is discoverable as
  `00008140-001459DE347B001C`; rediscover devices before using this identifier.
- Approved unsupported-wheel UX: open the existing
  root/quality picker directly for pentatonic and other scales unsupported by the
  seven-degree wheel. Keep the project key unchanged. Scale-derived suggestions
  require a different music-theory plan if the user chooses that option.
- A question about plain Harmony versus strum/melody/audio lag and playhead timing
  is pending. Profiling must cover these paths separately regardless of the answer.

## Evidence and success checks

1. Detection uses hardcoded flat formatting in `lib/utils/note_utils.dart`
   (`formatRootChoiceLabel`, `formatScaleLabel`, `formatChordSymbol`), whereas the
   instrument scale dock in `lib/main.dart` and Writer header interpolate canonical
   sharp roots. Success: the same pitch displays D# in Sharps mode and Eb in Flats
   mode everywhere, including notes, scale/chord pickers, instrument canvases,
   project labels, previews, and generated chord symbols. Gb must be included in
   Flats mode. Pitch classes, MIDI, frets, octaves, and custom labels do not change.
2. `lib/features/songwriter/harmony_chord_sheet.dart` receives the correct key.
   `diatonicTriads` in `lib/schema/rules/songwriter_rules.dart` returns no triads
   for pentatonic scales, and `chord_wheel.dart` wrongly calls this a missing key.
   Success: Change chord remains usable with a pentatonic project key and presents
   the appropriate controls without a large empty wheel or false missing-key text.
3. `_ActionChip` in `lib/ui/save_browser_panel.dart` places an expanding `Center`
   inside a `Wrap`. On the simulator, the linked Fretboard Saves panel reproduces
   the user's screenshot: each action occupies its own full-width run. Success:
   compact action widths, natural wrapping at narrow widths/larger text, 44px
   minimum touch targets, accessible folder contents and linked update action.
4. `insertInstrumentSelectionAtBar` in `lib/store/songwriter_store.dart` creates
   a candidate with the new exact Harmony composite, then prefers
   `source?.embedded` while validating it. A changed pitch-class set is rejected.
   The handoff's `while` then repeats after every failed insertion. Reproduced on
   the simulator: Piano D4 replacing the existing D#4 exact Harmony reopens the
   destination picker after confirmation/name submission. Success: replacement
   uses the new native selection, retains placement/local lyrics, completes once,
   and a rejected transfer ends with clear feedback rather than looping.
5. Writer's `songwriter_playback_store.dart` schedules ticks with `TickPacer`.
   Its UI subscribers select status/bar/fraction; a whole-screen rebuild on every
   tick is not established. Sequenced notes in `lib/utils/note_player.dart` lazily
   create players, render duration-specific WAVs, and prepare platform sources at
   onset. The pinned Darwin backend uses AVPlayer item preparation. These are
   candidates, not a measured root cause. Success requires physical-device timing
   and listening checks, not only mocked sinks or simulator debug playback.

## A. Persistent spelling and shared display helpers

Owner: music-theory + state-architect specialist, implemented by a fresh GPT-6
Luna extra-high agent. Read callers and the existing settings tests first.

Modify:

- `lib/utils/note_utils.dart`: one explicit display spelling policy; retain
  `chromaticNotes`, `noteToPC`, normalization, detection, and all canonical outputs.
- `lib/models/save_system.dart`: `AppSettings` field, immutable `copyWith`, JSON
  round-trip; missing/unknown setting defaults to Sharps.
- `lib/store/settings_store.dart`: persistent setter using the existing storage.
- `lib/main.dart`: Settings control and instrument scale dock labels.
- `test/utils/note_utils_test.dart`, `test/models/app_settings_test.dart`,
  `test/store/settings_store_test.dart`: all 12 pitch classes, octave preservation,
  chord quality/slash bass formatting, both preferences, hydrate/default behavior.

Illustrative API; final signatures should extend existing helpers where possible:

```dart
enum NoteSpelling { sharps, flats }

String formatRootChoiceLabel(
  String root, {
  NoteSpelling spelling = NoteSpelling.sharps,
});

Future<void> setNoteSpelling(NoteSpelling spelling) async {
  state = state.copyWith(noteSpelling: spelling);
  await _persist();
}
```

`formatMidiNoteLabel`, `formatChordSymbol`, and `formatScaleLabel` accept the same
policy. Flat rendering maps all five accidentals, including F# to Gb. Do not
perform search/replace on arbitrary strings or mutate snapshots to change labels.
Chord suffixes such as m7b5 retain their meaning; slash bass uses the preference.

The transfer payload must not call a preference-dependent display formatter:
`_WriterTransferPayload.chordSymbol` uses an explicit canonical Sharps formatter
independent of Settings. Only the proposed name/title shown to the user uses the
selected spelling. The same recognized chord created under either preference
must produce identical musical payloads (including canonical slash bass); the
user-approved Save name is a separate literal field.

For already stored recognized chord text, provide a pure metadata-validated
formatter. Accept a symbol for formatting only when its root normalizes to the
stored root PC and its exact quality suffix matches the stored quality. Preserve
and format an optional valid slash-bass pitch class; never reconstruct a symbol
from root + quality alone and silently lose that bass. Invalid/mismatched text is
literal. No-identity exact Harmony, Save names, lyrics, pattern names, and arbitrary
aliases are always literal. Do not infer an identity from an exact label.

```dart
String formatRecognizedChordLabel({
  required String symbol,
  required int rootPc,
  required String quality,
  required NoteSpelling spelling,
}); // verified symbol root/quality, optional bass; otherwise return symbol
```

## B. Apply spelling at every musical display site

Owner: instrument-renderer + music-theory specialist, fresh GPT-6 Luna extra-high.
Depends on A's API. Widget observers read `settingsProvider.select` where practical;
pure painters and helpers receive spelling explicitly and repaint when it changes.
Callbacks continue to use canonical roots or pitch-class indices.

Read and change the following display sites as needed; this inventory defines the
scope and must be checked for additional callers with `rg` before finishing:

- Shared detection/pickers:
  `lib/features/instrument_shared/shared_detection_panel.dart`,
  `shared_scale_picker.dart`, `chord_picker_parts.dart`, `writer_handoff.dart`.
- Native notes and instrument-specific copy:
  `lib/features/fretboard/fretboard.dart`, `chord_voicing_picker.dart`,
  `tuning_selector.dart`, `lib/features/piano/piano_keyboard.dart`,
  `piano_chord_picker.dart` (including voicing note labels supplied to diagrams),
  `lib/features/piano_roll/piano_roll_grid.dart`, `piano_roll_stack_builder.dart`,
  `piano_roll_detection_panel.dart`, `piano_roll_hum_recorder.dart`,
  `piano_roll_save_stack_loader.dart`.
- Project/key UI: `lib/ui/project_config_sheet.dart`, `project_picker_sheet.dart`,
  `core/update_project_key_dialog.dart`,
  `lib/features/songwriter/songwriter_header.dart`.
- Writer/Song theory and note previews:
  `lib/features/songwriter/harmony_chord_sheet.dart`, `chord_wheel.dart`,
  `songwriter_melody_performance_editor.dart`, `songwriter_block_preview.dart`,
  `songwriter_screen_sheet.dart` (recognized chord tiles and Library identity),
  `songwriter_save_panel.dart` (key-difference copy),
  `lib/features/song/song_screen.dart`, `song_note_pattern_editor.dart`.
- Save-derived musical details: `lib/ui/save_card_label.dart`,
  `save_browser_panel.dart`. Render `SaveEntry.name` and user-authored
  `WriterBlockSnapshot.chordSymbol` verbatim. Format recognized/generated identity
  from root/quality metadata, not by interpreting a user name as a chord.
- Conflict copy: `lib/ui/core/project_off_scale_dialog.dart` and
  `scale_conflict_dialog.dart` plus their callers. Supply already formatted note
  and key text or pass spelling explicitly; preserve canonical conflict lists.
- Derived previews/errors: `lib/store/piano_roll_stack_builder_store.dart` and
  the `ThirdAboveSuggestion.label` generated by
  `lib/schema/rules/songwriter_third_above_rules.dart` and consumed by Writer.
  Keep rule/store musical outputs canonical; format these generated labels at
  the display boundary or pass an explicit presentation-only argument. Do not
  rewrite persisted suggestion/Save names when the setting changes.

Tests: existing shared detection and scale picker targets plus focused display
tests covering Eb minor pentatonic across detected chip/dock/Writer key; toggling
Settings updates mounted instruments and painter labels immediately. Check flats
picker taps still produce canonical D# / PC3 rather than breaking comparisons.
Check user label `D# idea` stays literal. Canonical snapshot/key JSON before and
after a spelling change must be identical. Include Roll, Song, project dialogs,
Save detail, slash chords, and Gb coverage rather than testing only Fretboard.
Test recognized D#m/A# becoming Ebm/Bb, quality m7b5 retaining b5, and exact label
`D#m/A#` remaining literal with no identity. Create the same recognized chord in
both settings and compare stored musical payloads, not just toggle old data.

## C. Chord-wheel capability and exact replacement

Owner: state-architect + music-theory specialist, fresh GPT-6 Luna extra-high.
Proceed after the unsupported-scale UX is confirmed. Coordinate ownership of
`writer_handoff.dart` and `harmony_chord_sheet.dart` with B; do not edit them
concurrently.

Modify:

- `lib/features/songwriter/harmony_chord_sheet.dart`: separate `_hasKey` from
  wheel availability; show manual picker directly for unsupported scales.
  Keep the project key in manual commit/Roman-numeral computation. Preserve
  existing silent-placeholder, lyrics, library, and seven-degree wheel behavior.
- `lib/features/songwriter/chord_wheel.dart`: remove the false missing-key
  assertion for an unsupported scale. No inferred parent scale or transposition.
- `lib/schema/rules/songwriter_rules.dart`: `diatonicTriads` must require exactly
  seven supported intervals, matching the wheel's fixed wedge count and the
  existing shared diatonic-chord rule. Reject the eight-note diminished scale
  rather than indexing it modulo seven. This is also the sheet capability check;
  do not duplicate a divergent scale whitelist.
- `lib/store/songwriter_store.dart`: validate the candidate's newly captured
  composite first in the replacement path. Clear/scope `lastHarmonyMutationError`
  at the start of each insertion attempt so rejection feedback cannot reuse a
  previous attempt's error; use a neutral fallback when no specific error exists.
- `lib/features/instrument_shared/writer_handoff.dart`: only repeat the target
  picker for the user's explicit Choose another bar action. A failed insertion
  shows accurate feedback and returns. Preserve all stale source/project checks.

Minimal replacement correction (verify surrounding recognized paths):

```dart
final composite = _buildHarmonyChordSnapshot(
  // existing parameters unchanged
  existing: candidate.embedded ?? source?.embedded,
);
```

Tests:

- `test/features/songwriter/harmony_chord_sheet_test.dart`: root PC3 + minor
  pentatonic; manual root/quality visible, no false missing-key text, selection
  commits with the existing project key; seven-note and missing-key cases remain.
- `test/schema/rules/songwriter_rules_test.dart`: unsupported pentatonic, blues,
  whole-tone, diminished and unknown scales return no wheel triads; supported
  seven-degree scales/modes retain seven correct triads. Sheet tests distinguish
  missing key from unsupported five/six/eight-degree keys without clearing key.
- `test/store/songwriter_harmony_composite_store_test.dart`: both Piano and
  valid Chord-mode Fretboard; replace recognized and exact Harmony using different
  notes; same block id/start/span/repeat/local lyrics, new native notes/register,
  no invented chord identity; canonical linked-save transaction and undo restore
  old content. Confirm shared-save replacement does not alter unrelated uses.
- `test/features/instrument_shared/writer_handoff_test.dart`: occupied exact
  replacement completes once; rejected insertion ends without reopening; explicit
  Choose another bar still works; cancel/stale project/selection remain safe.

## D. Save toolbar layout

Owner: save-system/instrument-renderer specialist, fresh GPT-6 Luna extra-high.
Coordinate `save_browser_panel.dart` with B; no shared-file concurrent edits.

Modify only `_ActionChip` in `lib/ui/save_browser_panel.dart` unless inspection
shows another necessary constraint fix. Keep the linked-update banner full width.

```dart
Center(
  widthFactor: 1,
  heightFactor: 1,
  child: /* existing visual chip */,
)
```

Regression: new `test/ui/save_browser_header_layout_test.dart` or a suitable
existing Save Browser layout test. Mount the actual Fretboard/Piano panel with a
linked Harmony Save at 390px and 1180px, normal and enlarged text. Assert each chip
has a compact width, remains at least 44px in each touch dimension, wraps within
content bounds, and does not hide the breadcrumb/folder/save actions. Assert no
layout exception; scroll nested content and activate actions to verify hit areas.

## E. Writer playback: measure, then remove the demonstrated bottleneck

Owner: state-architect/audio specialist, fresh GPT-6 Luna extra-high. This is an
evidence-gated repair, not an assumption that debug mode explains the problem.

Files to inspect/instrument and modify only when implicated:

- `lib/store/songwriter_playback_store.dart`: flatten/prepare durations, scheduled
  event deadline and dispatch time, cancellation while preparing.
- `lib/features/songwriter/songwriter_header.dart`: expose preparation lifecycle
  correctly, with Stop available during preparation and no second active Start.
- `lib/utils/note_player.dart`: render/file lookup, player creation, setSource/
  readiness/resume timing, cold versus warm voice startup and simultaneous voices.
- `lib/store/song_audio_player_sink.dart`: preparation/start timing when recorded
  clips are present.
- `lib/utils/tick_pacer.dart`, `lib/features/songwriter/songwriter_playhead.dart`,
  `lib/store/song_playback_store.dart`: compare only; change if measurements locate
  a defect there, not as unrelated cleanup.
- If per-onset iOS AVPlayer preparation remains the measured bottleneck despite
  preloading, the isolated iOS note backend may require a native scheduling patch
  in `ios/Runner/AppDelegate.swift` and a dedicated Swift file. Before that change,
  the agent must provide measured evidence and a concrete implementation addendum
  for a fresh Sol review; do not add a dependency or replace the audio backend on
  speculation. This is an internal review gate, not a new user approval request.

Measurement/repair sequence:

1. Add development profiling spans/counters using `dart:developer` around the
   critical boundaries. No permanent noisy logging or timing overhead in the
   per-note release path. Record the explicit build mode, device, arrangement,
   tempo, event counts, cold/warm runs, startup time, frame timing, and note launch
   lateness. Distinguish platform-ready/resume timestamps from actual audible onset.
2. Rediscover the physical iPhone; run explicitly in profile mode, preserving user
   projects. Use an isolated QA project with a plain Harmony section, then six-note
   strums, melody, and recorded clips. Compare matching Song content and working
   Fretboard/Piano auditions. Profile the reported scenario in debug too so a
   mode difference is measured rather than asserted.
3. If WAV synthesis/player/source setup causes late onset, prepare the actual
   arrangement's required tones/voices before starting the transport clock, and
   reuse prepared sources at onset. Preserve volume, pan, duration, note overlap,
   strum offsets, and stop/cancel generation guards. Avoid rendering every possible
   note, unbounded player growth, or a cache entry for every entire arrangement.
   Adding preload requires a safe preparation lifecycle first. At entry acquire
   one generation/owner before any await; repeated Start while preparing/playing
   is idempotent. Set an explicit preparing status (or equivalent owned state),
   with an available Stop. Preparation failure returns to idle with feedback.
   Stop/project switch/disposal invalidates the owner immediately. Shared sink
   prepare/start/stop work must be serialized or generation-owned, so stale
   preparation cannot rebind/pause a new run and a stale async stopAll cannot stop
   its voices/clips. Version checks only after the await are insufficient. Cleanup
   releases only the old owner's resources. Coordinate shared Song sink behavior
   without breaking concurrent audition contracts.

   A preparation sink can keep tests platform-independent:

   ```dart
   await notePreparationSink(requiredVoices, owner: version);
   if (_version != version || _disposed) return;
   // Set playing/start the clock only after preparation completes.
   ```

4. If traces instead show CPU/event preparation or frame work, optimize only that
   demonstrated hotspot and retain the existing sink behavior. If clip preparation
   is the problem, fix that sink and its start/cancel contract separately.
5. Repeat matched cold/warm device runs after the patch, at 120 BPM and the reported
   tempo. Report before/after distribution and worst-case lateness, not just a mean.
   Target sustained audible timing without cumulative slowdown, no dropped notes,
   and no unintended simultaneity replacing intended strum offsets. A human
   listening check on the physical phone is required before claiming audible
   playback fixed; request only that specific validation if remote tools cannot
   capture audio. Simulator behavior and mocked timestamps alone are insufficient.

Reproducible physical-device gate: for each note-only/plain Harmony, dense six-note
strum, melody, and controlled local recorded-clip fixture at 120 BPM and the
reported tempo, measure ten cold and ten warm starts over the first eight bars.
Also run two 60-second continuous plays per fixture/tempo for sustained timing.
Do not repeat an identical tempo when the reported tempo is already 120 BPM.
Cold means a fresh
app process and empty in-memory player/tone caches; do not erase user projects or
audio to force it. Keep fixture MIDI, note counts, polyphony, offsets, clip sizes,
and build mode fixed in the before/after report. Record scheduling dispatch,
platform-ready/resume, and actual audible observations as separate measurements.

Initial profile-mode pass criteria:

| Metric | Gate |
| --- | --- |
| Play to first platform-ready/resume | at most 2 s cold, 1 s warm |
| Event dispatch lateness against monotonic score deadline | p95 <= 10 ms; worst <= 25 ms |
| Platform-ready/resume lateness for prepared note voices | p95 <= 30 ms; worst <= 60 ms |
| Tempo drift over the 60 s score | <= 25 ms of accumulated scheduling error |
| Intended strum stagger at launch | p95 offset error <= 10 ms; worst <= 25 ms; no collapsed ordering |
| Dropped/duplicated intended events or stolen sustained voices | zero |
| UI build/raster frame time | p95 within measured refresh-frame budget; missed budget <= 1%; worst <= 3 budgets |

The profiling agent records a baseline and checks whether these gates correspond
to the measured clocks and platform capabilities. Before choosing the repair, a
fresh Sol reviewer must approve the baseline report and any concretely justified
change to a gate. Do not loosen a gate after a failed patch to declare success.
Audible onset cannot be established by an AudioPlayer resume future; physical
listening remains a separate acceptance requirement. Debug comparisons diagnose
the originally reported environment; profile mode is the performance pass gate.

Tests: `test/store/songwriter_playback_test.dart`,
`songwriter_audio_playback_test.dart`, shared audio/sink tests as implicated, and a
new `test/utils/note_player_test.dart` if a fake audio platform is needed. Verify
prepare finishes before clock start, stop during prepare cannot start late, cached
warm notes avoid render/source setup on onset, concurrent voices retain their own
duration/pan, queued offsets are cancelled on stop, and rapid stop/restart does not
release a new voice. Keep Song/Roll shared backend regression coverage intact.
Add double Start while preparing, preparation failure, Stop then Start while old
prepare/stop futures remain pending, project switch/disposal, and old async sink
completion attempting to rebind/pause/stop newer playback. Assert one preparation
owner and one active clock, and no side effects from stale owners.

## Delegation, review, and final verification

- Fresh GPT-6.1 Sol extra-high reviews this plan; resolve findings and use a fresh
  reviewer each iteration. Then submit the approved plan for the user's approval.
- After approval, delegate A then B; C/D can run independently only with disjoint
  file ownership. E can measure concurrently with spelling/UI work when app-run
  access is coordinated with the root. Every implementation agent is fresh
  GPT-6 Luna extra-high and reads the applicable specialist instructions/skills.
- Run narrow regression targets after each task. Root integrates docs and checks
  all diff boundaries. Do not revert unrelated changes or write into user projects.
- Fresh independent GPT-6 Luna extra-high reviewers audit spelling/state, Harmony/
  Save flows, and playback/performance separately. Fix findings via implementation
  agents, then spawn fresh reviewers until all pass. Include the October 4 changes
  in the final review scope because their independent review remains outstanding.
- Format changed Dart paths, run `flutter analyze`, narrow tests, then the full
  suite once integrated. Verify compact and wide simulator views with linked
  banners, spelling switches, pentatonic Change chord, and occupied replacement.
- Update `PRODUCT.md`, `DESIGN.md`, `README.md`, and relevant `docs/fretboard.md`,
  `piano.md`, `piano_roll.md`, `save_system.md`, `songwriter.md`,
  `song_writer_guide.md`; update Song/settings guidance where already documented.
  Re-read `AGENTS.md` after the phase; update only if a persistent rule changed.
- Close agent-created preview tabs, stop any serve-sim helper created for this
  task, detach Flutter runs while leaving the app available. No commit/PR is
  requested. Report unresolved device validation honestly.

## Review record

- Revision 1: three fresh GPT-6 Luna extra-high read-only researchers completed.
  Save layout and Piano exact replacement loop reproduced with computer control
  on the running iPhone 17 Pro simulator, using the isolated October 4 QA project.
  Production code has not been changed for this corrective phase.
- Revision 1 review: NOT APPROVED. Required exact-seven-degree capability,
  canonical/display and slash-bass contracts, safe async preparation ownership,
  and measurable device acceptance. Revision 2 addresses all four findings and
  adds per-attempt mutation-error scope, known missing display consumers, and
  fresh-review gates for the measured performance repair. The illustrative
  disposal flag is registered through `ref.onDispose`, compatible with the
  repository's Riverpod 2.6.1; no Riverpod 3 API is required.
- Revision 2 review: APPROVED. Reviewer checked the settings, wheel/sheet,
  handoff, Harmony composite, toolbar, transport, NotePlayer, and clip-sink
  callers; no blocking findings remain. The proposed unsupported-scale UX
  requires user confirmation. The physical baseline and metric interpretation
  require a fresh internal Sol review before choosing the performance repair;
  a native backend change requires the specified reviewed addendum. Additional
  display consumers found by this review were added to B's inventory. This is
  plan approval only, not implementation approval or evidence of a playback fix.
- User approved revision 2 with "proceed", including the manual picker fallback
  presented in the approval question. Fresh GPT-6 Luna extra-high agents began
  spelling core, Harmony/toolbar corrections, and playback instrumentation.
- Implementation review 1 (fresh Luna): state review found one stale replacement
  error field; display review found expanding manual chord chips, flat-root
  metadata lookups, and an octave-bearing tuning label using a pitch-class
  formatter. The short-height Save test also dragged clipped/offscreen labels.
  Fresh implementation agents were assigned these concrete fixes.
- State review 2 (fresh Luna): PASS after the per-attempt error reset and its
  regression. The reviewer independently traced native eligibility, exact
  replacement, Save transactions/history, project keys, and strum uniqueness;
  88 focused tests passed. Legacy unversioned data remains outside the approved
  fresh-start scope.
- Computer verification of the production app: confirmed key changes from Piano
  update Writer/Fretboard with confirmation. Eb minor pentatonic and native flat
  labels agree; Change chord opens manual controls without the false missing-key
  message. Linked Fretboard and Piano Save headers fit compact portrait; the
  Fretboard Save header also fits landscape, but the instrument behind it exposed
  a short-height overflow that is being corrected. Replacing an occupied Piano exact Harmony from Eb4 to Bb4
  completes once, returns to Writer, and reopening its native editor selects
  MIDI 70. No user project was used; these checks use the isolated QA project.
- Display review 2 (fresh Luna): the three spelling/picker findings from review 1
  pass. The production Fretboard screen still overflows in landscape because its
  fixed-height board, header, mode control, and dock exceed the available height.
  A fresh implementation agent owns the shared instrument layout and regression.
- Further computer verification found that replacing a Fretboard Harmony moved
  its lane after a Piano lane. The direct insertion path now retains its index,
  with coverage for primary identity, dependent strum/Save anchors, and undo.
  State review 3 (fresh Luna) found the same ordering defect in the Harmony Save
  reuse route; that route is being corrected before a fresh review.
- State/handoff review 5 (fresh Luna, October 8): PASS. Both insertion routes
  preserve existing lane position, primary identity, anchors, placement/lyrics,
  native exact notes, canonical Save reuse, journal changes, and undo. The final
  instrument-specific eligibility message also passes. The reviewer ran 54
  composite/insert/handoff tests and 18 Writer Save-sync tests successfully.
- Display review 4 (fresh Luna, October 8): scrolling, spelling, Save geometry,
  canonical callbacks, literal names, slash bass, octave labels, and the fixture
  updates pass 139 targeted tests. Existing ModeSegment and shared chord-picker
  tap regions still fall below the documented 44px target. These controls in the
  corrected surfaces are being adjusted before a fresh review.
- Touch/layout follow-up: ModeSegment now provides a full tap area, with its
  total height reflected in the shared scaffold threshold; root and quality
  pills constrain both hit dimensions to at least 44px while preserving compact
  artwork and horizontal scrolling. A compact portrait test at 1.6× text exposed
  a 94px empty-hint overflow. The hint needed 273px but received 179px; the layout
  now accounts for wrapped text height before choosing its scrollable branch.
  Ten real-instrument layout tests cover portrait, narrow widths, landscape,
  enlarged text, threshold constraints, and taps/scrolling.
- Display review 5 (fresh Luna, October 8): 46 focused tests pass. Approval is
  withheld because natural-width diatonic chips and the shared Scale picker
  still have tap dimensions below 44px. Fresh implementation agents own these
  two small follow-ups. Diatonic chips now have an opaque 44px minimum-width
  target and a row height that accommodates enlarged two-line labels; seven
  picker and ten real-instrument layout tests pass. Shared Scale root/scale and
  project-key clear targets are now at least 44px, with seven focused tests for
  edge taps, canonical callbacks, scrolling, enlarged text, and confirmation.
- Display review 6 (fresh Luna, October 8): 212 focused tests and whole analysis
  pass. All earlier spelling, layout, key, Free-mode, Save, and strum findings
  pass. Three remaining accessibility findings withhold approval: the local
  non-project scale-clear action, scale-category tabs, and chord-wheel canvas
  text scaling. A fresh Luna implementation agent owns these narrow corrections
  before another fresh review.
- Display review 7 (fresh Luna, October 8): the three review-6 corrections pass
  14 focused and 161 broader UI tests; scoped analysis is clean. Approval is
  withheld for the wheel's existing single synthesized accessibility action,
  which taps the rejected center hole and lacks per-degree labels. A fresh
  agent is adding explicit accessible actions for the seven displayed degrees.
- Display review 8 (fresh Luna, October 8): PASS for the final wheel correction.
  Seven labeled degree actions have 44px target rectangles and stable order,
  return canonical triads, and update with key, spelling, scale, direction, and
  callback changes. Eight widget tests and scoped analysis pass; physical
  pointer behavior and enlarged text remain covered. Together with the earlier
  passed display batches, this closes the UI review findings. Final integrated
  checks and the separate profiling readiness review remain pending.
- Further production-app verification on October 8: the updated Scale category
  controls expose their selected state and switch categories correctly. Scale
  content fits both compact portrait and short landscape; canceling Clear key
  retains D# minor pentatonic. The QA project and original Sharps preference
  remain in use.
- Integrated suite on October 8: 1,263 passed, three failed. The failures were
  old test harness assumptions: implicit contextual flat spelling and a Harmony
  sheet mounted without ProviderScope after it became a settings consumer. The
  focused harness corrections pass without weakening the musical/lyric checks;
  the complete suite will be rerun after the remaining fixes.
- Integrated checks before the final touch-target follow-ups on October 8:
  `flutter test --no-pub --reporter
  expanded` passes all 1,278 tests; `flutter analyze --no-pub` reports no issues.
  All 121 changed/new Dart paths pass formatting checks and `git diff --check`
  is clean. This verification does not cover the blocked physical-phone matrix.
- Further computer checks on October 8: Fretboard and Piano content scroll above
  the fixed dock in short landscape without RenderFlex errors. Detection and
  Save folders remain reachable by real gestures. Turning Flats off immediately
  restores D# minor pentatonic and sharp note labels in Piano and Writer; the
  original Sharps preference has been restored.
- Production-app replacement check on October 8: Piano exact Harmony changed
  from Bb4/MIDI 70 to D#2/MIDI 39 in occupied bar 1. The handoff completed once,
  returned to Writer, retained the primary Piano lane above Fretboard, and kept
  Verse 1 lyrics. Reopening Edit in Piano selects only MIDI 39.
- Playback evidence review (fresh Sol): scoped diagnostic readiness APPROVED;
  physical baseline and repair selection NOT APPROVED/pending. Xcode cannot sign
  the profile build ("No Accounts", no development provisioning profile).
  A single debug Simulator trace is explicitly insufficient for phone timing,
  production frames, sustained drift, or audible acceptance. The reviewer
  required voice/deadline/outcome correlation, signed drift samples, configurable
  sustained fixtures, and production UI/comparator capture. A fresh Luna agent
  is implementing these measurement amendments without a playback repair.
- Diagnostic implementation review 3 (fresh Luna, October 8): NOT PASS. Event
  IDs were shifted relative to the manifest, the post-loop timestamp was compared
  with a later score-end deadline as if it were drift, and error cleanup could
  overwrite a terminal voice error. A fresh agent corrected the IDs, retained
  actual last-tick drift separately from nominal end-boundary completion, and
  preserved first terminal outcomes. Its 23 focused tests pass; fresh review 4
  is checking the amended instrumentation. Production UI/frame comparisons and
  physical-device baseline/repair selection remain pending.
- Diagnostic review 4 (fresh Luna, October 8): PASS for instrumentation readiness.
  Zero-based manifest correlation, signed final-tick timing, separately named
  nominal end-boundary completion, voice denominators, and terminal error
  preservation are sound; 27 focused tests and scoped analysis pass. This does
  not approve the blocked physical baseline, production frame timing, or audible
  playback. No performance repair has been selected or implemented.
- Production measurement preparation (October 8): a fresh Luna agent is
  extending the isolated harness with the real Writer screen, active-window
  frame capture, and matching production comparators where provider isolation
  permits. This work can proceed while signing is blocked; it must pass a fresh
  review before capture. Simulator captures verify the harness, not phone
  performance, and cannot replace the physical baseline or listening gate.
- Production capture review 1 (fresh Luna, October 8): isolated real Writer/Song
  screens, public instrument surfaces, temporary cache/repository, schedule
  comparison, and frame-fence draining pass 12 tests and scoped analysis.
  Approval is withheld because a rapid resume during a drain can silently skip
  its sample and reuse the previous frame report. A fresh agent owns explicit
  per-attempt capture/report attribution and regression coverage. Frame window
  membership intentionally pairs DateTime system-clock boundaries with
  `FramePhase.rasterFinishWallTime`; Flutter documents that phase for system-clock
  correlation. The review request's proposed Timeline clock was not the approved
  plan's requirement and is corrected here. Frame costs still use Flutter's
  build/raster durations; audio scheduling retains its monotonic deadlines.
- Capture attribution follow-up (October 8): each attempt retains its own frame
  owner and Writer outcome object. Starts during an earlier drain explicitly
  export unavailable frame evaluation; late reports cannot fill another attempt.
  The Song recorded-clip comparator now uses a real player and an independently
  constructed temporary audio lane with the same controlled WAV. Its manifest
  distinguishes this from Writer audio handoff, which omits clips. Fifteen
  focused tests and scoped analysis pass; fresh capture review 2 and the full
  integrated suite are running.
- Final integrated source checks on October 8, after the wheel and capture
  corrections: all 1,301 tests pass (`flutter test --no-pub --reporter expanded`),
  whole `flutter analyze --no-pub` reports no issues, and all 123 changed/new Dart
  paths pass formatting checks. These checks
  do not establish physical-device or audible playback performance.
- Capture review 2 (fresh Luna, October 8): the per-attempt attribution,
  documented wall-clock pairing, temporary real-player clip fixtures, and
  production view isolation pass 15 tests and scoped analysis. One remaining
  gate issue withholds approval: a valid frame fence could enable budget
  evaluation despite frames with unusable timestamps. A fresh agent owns the
  narrow completeness/gate correction; distributions may remain diagnostic,
  but unknown sample membership must disable performance evaluation.
- Capture review 3 (fresh Luna, October 8): PASS. Sixteen focused tests and
  scoped analysis verify that unusable timestamps disable frame-budget gates
  even when the ordered fence is observed, while valid capture, timeout, resume,
  and attempt-scoped report behavior remain sound. This approves readiness,
  not a physical baseline or playback repair.
- Final source verification after that correction: all 1,302 tests pass,
  whole analysis reports no issues, all 123 changed/new Dart files pass format
  checks, and `git diff --check` is clean.
- Production Writer smoke on the debug iPhone 17 Pro Simulator: eight bars at
  120 BPM complete with a fenced capture of 480 frames. Expected, requested,
  launched, and naturally terminated voices are all 32; dropped, stolen, and
  error counts are zero. The measured display rate is 60Hz. The report is copied
  to `/private/tmp/muzician_oct8_writer_frame_smoke.json`. This single debug run
  validates the harness; it does not establish iPhone profile timing, sustained
  drift, or audible onset.
- Production Song smoke on the same debug Simulator: the controlled-clip
  fixture completes with a fenced capture of 324 frames. The isolated Song
  repository contains the generated QA WAV and uses the real
  `AudioPlayersClipSink`; the MIDI/tick/offset/count comparison matches four
  voices and one event. Song's audio lane is an independent synthetic fixture
  using the same WAV, because the production Writer-to-Song handoff excludes
  audio clips. The frame report and comparison manifest are copied to
  `/private/tmp/muzician_oct8_song_clip_frame_smoke.json` and
  `/private/tmp/muzician_oct8_song_clip_smoke_manifest.json`. No physical profile
  timing or audible acceptance is inferred from this debug smoke.
- Final simulator restoration: the normal `lib/main.dart` app is running in
  portrait on Writer, with `Codex Harmony QA 2026-10-04`, its canonical D# minor
  pentatonic key, primary Piano Harmony, and secondary Fretboard Harmony
  preserved. The original Sharps preference is retained. The Flutter session
  was detached to leave the app running; only the temporary preview tab and
  helper created for these checks were closed. `AGENTS.md` was reviewed after
  the implementation phase; the feature guides and README describe the shipped
  behavior. Physical signing, the phone measurement matrix, fresh Sol approval
  of that baseline, any measured playback repair, and listening acceptance
  remain outstanding.
- Physical-phone retry on October 8 after the user's "prova ora": the modern
  provisioning directory now contains a profile and Xcode selects the development
  identity. The first run using selected Xcode 26.4.1 failed waiting for the device;
  CoreDevice's nested error identifies the phone as locked. Xcode 27.0 is already
  installed and initialized, so subsequent commands select it through
  `DEVELOPER_DIR` for that process. After the user unlocked the phone, DDI build
  27A266a reports usable and compatible. One transient build-settings lookup failed;
  a retry obtains `TARGET_BUILD_DIR`, completes the profile build, and installs
  the isolated harness. No iOS source/signing configuration changes were needed.
  Device Hub's actual screen shows that iOS still requires the user to authorize
  the development certificate before the app can execute. The user has been
  asked to complete that trust action and any required restart. No physical
  playback trace or audible acceptance is claimed yet. Diagnostic log:
  `/private/tmp/muzician_oct8_phone_profile_retry.log`.

- Physical USB capture on October 8: after the user completed certificate trust,
  the wireless VM connection remained unreliable. The user connected USB and
  left the phone unlocked. The profile harness now runs on iPhone 16 Pro Max
  (iOS 27.0.1) with the real Writer screen and an isolated eight-bar Cmaj7 fixture
  at 120 BPM. An earlier auto-start frame/outcome report and two manually started
  raw VM traces are available. Cold run 1 has event dispatch p95/worst 2.142 ms,
  but play API Future completion p95 472.288 ms; warm run 2 still has completion
  p95 279.890 ms. These are API observations, not audible-onset measurements.
  Both runs account for 32 voices with no reported drops or steals. Full matrix,
  sustained runs, comparators, fresh Sol baseline approval, repair, and physical
  listening acceptance remain pending.
- Temporary raw collector/parser completed fresh Luna review R2 PASS. Physical
  traces exposed a missing cross-artifact identity marker in real Writer mode:
  frame events include profile_run_id but omit run_tag, whereas Play markers exist
  only in the minimal wrapper. The parser correctly withholds manifest/frame joins
  for these traces. A fresh Luna implementation is adding explicit tagged frame
  markers and scoped parser support; existing raw artifacts will not be altered
  or retroactively assigned an inferred tag.

- Real-Writer diagnostic identity correction: fresh Luna R3 withheld approval
  because the parser's manifest join still relied on the minimal Play marker.
  A fresh implementation corrected manifest fallback and unavailable/incomplete
  frame attribution; fresh Luna R4 PASS confirms matching explicit frame
  lifecycle run tags and IDs, 32/32 scheduled voices, and safe withholding for
  untagged, conflicting, duplicate, or incomplete artifacts. The real Writer
  frame marker is identity evidence only; its timestamp is not claimed as a
  Play input timestamp. Ten harness fixture tests and scoped Dart analysis pass.
- Cold-process collection uses the already built profile app with
  `flutter run --use-application-binary=build/ios/iphoneos/Runner.app`. Each run
  starts a new process and creates a new isolated QA directory without changing
  user projects. A direct CoreDevice relaunch plus attach did not yield a
  reachable profiling service, so capture uses the reliable Flutter launcher;
  no source/signing/dependency change was made for that workaround.

## October 8 diagnostic source-boundary addendum (fresh Sol APPROVED)

A fresh GPT-6.1 Sol extra-high methodological review approves this diagnostic
addition and continued baseline collection. It does not approve the incomplete
physical baseline or a repair choice. Earlier captures remain an explicitly
labeled instrumentation subseries without the new source measurement.

- Modify `lib/utils/note_player.dart` only at its preview/sequenced `player.play`
  calls; introduce a small forwarding Source helper in
  `lib/utils/playback_profile_source.dart` if needed for direct contract testing.
  In debug/profile, wrap the selected source and record its `setOnPlayer` begin/end
  with run/event/voice/player IDs. Release continues to pass the original source,
  without creating arguments or a wrapper. Preserve allocation, caches, source
  selection, player position updater, volume/pan/duration/onset and generations.

  ```dart
  class PlaybackProfileSource extends Source {
    PlaybackProfileSource(this.delegate, this.arguments);
    final Source delegate;
    final Map<String, Object?> arguments;
    @override
    String? get mimeType => delegate.mimeType;
    @override
    Future<void> setOnPlayer(AudioPlayer player) async {
      final task = PlaybackProfileTask.begin(
        'note_player.source_binding', arguments: arguments,
      );
      try {
        await delegate.setOnPlayer(player); // exactly once
        task.finish(arguments: {'outcome': 'source_binding_completed'});
      } catch (error) {
        task.finishError(error, stage: 'source_binding');
        rethrow;
      }
    }
  }
  // Retain AudioPlayer.play's desiredState and private resume sequence.
  await player.play(playbackProfilingEnabled ? wrappedSource : source);
  ```

- Add focused tests under `test/utils/` for MIME/source forwarding, exactly-once
  delegation, failure propagation and unchanged `play` order/desired-state checks
  with a fake audio platform. Extend the temporary parser and its regression
  suite to report paired source-binding durations and source-end to play-end
  intervals by matching run/event/voice/player identity; absent stages remain
  unavailable, never zero. The span includes native source setup, prepared wait
  and awaited position update. Its residual is post-source play completion,
  including resume and Dart bookkeeping, not an isolated resume RPC.
- No optional native prepared-event marker is needed for this first split. Native
  readiness alone and actual audible onset remain unmeasured. A later bounded
  preparation proposal needs matched warm evidence that full source binding
  dominates, the complete prescribed matrix, and fresh Sol review. A native
  backend replacement still requires its separate concrete reviewed addendum.
- Frame gates retain the strict 120 Hz stage-cost target (8.333 ms), sampled from
  Display.refreshRate at window start. Exceedance means recorded build/raster
  cost over that target, not measured missed presentation deadlines. Do not
  relax it after a patch. Actual ProMotion cadence is not inferred from frame
  count divided by elapsed time.
- Startup means transport-method entry to first completed play/clip-resume
  Future, not OS input latency. A nominal 60-second score observes its last tick
  at 59.875 s; report first/last signed scheduling error and their difference
  separately from completion versus the nominal end. With eight event samples,
  nearest-rank p95 equals the maximum. API call stagger/order and Future order
  do not establish audible order.

## October 8 commit and performance handoff checkpoint

The user requested a commit of completed work and a handoff for performance,
ending the current measurement phase. Functional fixes and reviewed development
diagnostics are included; the physical baseline and audio repair remain incomplete.

- Final fresh Luna source-diagnostics review PASS: canonical string `voice_id`
  survives sequenced maps, local handle uses `sequenced_voice_id`, Source delegates
  once with MIME/error forwarding, and desired-state cancellation remains intact.
- Tick-horizon review PASS: signed first/last error and first-to-last change stay
  separate from nominal score-end completion.
- Final integrated verification: 1,309 Flutter tests pass, full analysis has no
  issues, format checks 125 changed/new Dart paths with zero edits, diff check clean.
- Five tagged plain-Harmony cold traces are complete. Two tagged warm traces are
  truncated and excluded from complete baseline counts. Latest Source/tick changes
  have not been rebuilt or captured on the phone.
- The temporary source-binding parser extension R2 was interrupted and its current
  regression suite fails. It is preserved as unfinished work outside Git, alongside
  raw QA evidence; do not use its newest results as approved measurements.
- Phone Flutter/collector sessions are stopped; the old QA app remains installed
  but closed. Restore the normal app after the next profiling session.

The copyable prompt, evidence archive location, pending parser repair, measurement
protocol, and remaining approval gates are in
`docs/handoffs/2026-10-08-writer-playback-performance.md`.
