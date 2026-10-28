# Product

Current instrument UX V2 implementation and runtime evidence: [delivery record](docs/instrument-ux-v2/PROGRESS.md).

## Register

product

## Users

Independent songwriters and musicians who primarily write on guitar and piano. They may be holding an instrument, rehearsing, or sketching on a phone or tablet. They want to capture a chord, lyric, melody, or groove quickly, then develop it into a song without losing the original idea.

## Product Purpose

Muzician is a songwriting workspace that connects guitar and piano exploration, music theory, lyrics, arrangement, and demo playback. Success means a musician can move from an initial musical idea to a structured, audible draft and shareable output while staying oriented and keeping their work safe.

The chosen product direction is **Studio** (18 October 2026): a precise, calm songwriting workbench with the musical surface first and contextual tools close to it. This document defines the target and the existing musical contracts; implementation status is tracked in [the Studio ledger](docs/studio-redesign/PROGRESS.md).

Writer Harmony lanes are instrument-bound to Piano or Fretboard. Projects
created through the usual project flow use the app's configured default,
prompting when it has not been set; each new section starts with a primary lane
using that project's default. **New project** in Writer asks for Piano or
Fretboard each time and stores the choice on that project without changing the
app-wide default. An authored chord has one canonical Save containing both
its Writer chord and native instrument realization. Shared-save edits offer an
explicit all-uses update or a standalone Save; replacing a Writer chord is a
separate action that preserves its placement and lyrics.

Harmony also accepts named, exact Piano and Fretboard Chord selections without
chord recognition. These retain native notes and positions, remain reusable in
the project's Harmony Library, and offer Change chord and Replace chord.
Fretboard Free is for exploration and saved ideas; it cannot enter or play in
Writer. Converting Free ideas into melody is outside this workflow.

Fretboard opens with 24 frets, including when loading an older shorter Save.
Full shows every note label in both Chord and Free; Solo labels only selected
positions. Piano uses the same Full/Solo rule while retaining all physical keys.

Guitar audition uses a plucked electric-guitar voice, with Clean and Distorted
tones. The tone is a device preference, shared by Fretboard, Writer Harmony and
Guitar Strum, and legacy Melody guitar playback, rather than part of a saved
chord. Explicit Melody lane sounds are independent. Writer exposes the same
Sound menu on Fretboard Harmony lanes. Fretboard offers explicit down/up
strums of the selected strings, including unrecognized shapes. A strum requires
one selected position per string and preserves tuning, capo and doubled pitches.

The project's tonic and scale/mode are shared by Writer and instrument views.
Fretboard and Piano's automatic **From notes** chord suggestions must keep every
chord tone within the active scale, using the project key when configured or
the instrument's local scale otherwise. Without an active scale, suggestions
remain unrestricted. Explicit **By chord** choices retain out-of-key confirmation.
Setting, changing, or clearing the key from an instrument or Writer asks for
confirmation; loading an instrument Save does not override the project key.

Settings provides one persistent Sharps/Flats preference for musical labels in
instruments, detection, chord tools, project keys, and previews. It changes
spelling only; saved pitches, project keys, custom Save names, and exact Harmony
labels retain their meaning. Writer's chord wheel supports seven-degree scales;
other configured scales open the root/quality picker directly without changing
the key.

Writer supports reusable section-level melody and guitar-strum patterns that
can move into Song as note tracks. Strum patterns use an explicitly selected
Fretboard Harmony lane and preview their down/up events on each tile. Within
a section, each Fretboard Harmony lane can be assigned to only one Guitar
Strum lane; occupied targets are hidden from other strum selectors.
Unassigned lanes reserve no target.
Melody patterns can target Piano or Fretboard, with saved note positions and a
performance view gated when the current instrument cannot play every note.
Melodies are named and their length is derived from the last note in whole
bars, edited with a Bars control in Piano Roll. Melody placements wrap across
numbered bar rows and resize by whole bars within the melody's last-note bar,
with an accessible placement alternative. A placement shorter than its melody
clips; a longer legacy placement keeps its occupied bars and shows a silent
tail without looping. Automatic repeats reserve their visible
bars and cannot be silently displaced by a changed repeat period. Repeat / reuse
creates a linked placement; Make Unique detaches just the selected placement.
Each new Melody lane defaults to Piano and can instead select Clean or Distorted
guitar independently of its pattern's performance target. Unset legacy lanes
retain per-pattern sound and the shared guitar tone until explicitly changed.
Writer's main menu can create a separate Save System project; Keep, Discard,
and Cancel protect the current Writer session. Discard restores its bound
named Save or clears the session and binding while retaining named Saves.
Writer audio lanes remain part of the section sketch and are not included in
that import.
Both Writer and Song provide bounded, project-scoped undo and redo so a draft
can be explored and recovered. Native Song Bundles carry an arrangement and
its referenced audio sources between devices; Web explains that bundle import
and export are unsupported because its audio repository is filesystem-backed.

## Brand Personality

Creative, clear, musician-first. Muzician should feel encouraging and musically literate, with theory presented as practical help rather than a test. The product should support play and experimentation while keeping the user's own decisions in control.

## Anti-references

- A general-purpose DAW interface that exposes studio complexity before a song idea exists.
- A theory textbook or quiz app that interrupts writing to explain concepts out of context.
- Generic AI songwriting that replaces the user's voice or silently changes their work.
- A productivity dashboard that makes projects, counts, or status more prominent than the music.
- Hidden gestures as the only way to discover important editing actions.

## Design Principles

1. **Start from the idea.** Make it quick to capture or continue a song before asking the user to configure a workspace.
2. **Keep instruments close to composition.** Guitar and piano exploration should feed the current song directly.
3. **Show theory in context.** Chord, scale, key, and voicing information should support a musical decision and remain optional.
4. **Make the draft audible.** Let users hear changes in the section or arrangement they are writing.
5. **Protect creative work.** Keep drafts recoverable with undo and redo, communicate save state clearly, and confirm project replacement before it begins.
6. **Make the next handoff visible.** Instrument → Writer remains available in V2. Song entry and its import actions are temporarily unavailable; retain the underlying import contract: sections become measures and markers; harmony, saved voicings, melody, and guitar strums become note tracks; drum lanes become drum tracks; tempo, meter, and key carry over. Writer audio stays in Writer.

## Accessibility & Inclusion

Design for touch-first use on phones and tablets, with readable text, scalable layouts, accessible labels for controls, keyboard support where available, and reduced reliance on color alone. Important actions should have visible affordances and forgiving recovery. Verify compact and wide layouts, including landscape, when changing user-facing screens.

## Studio redesign scope and success

A musician rehearses or writes in a room with moderate or dim light, moving between a physical instrument and a phone/tablet. Studio uses a dark neutral canvas, readable controls and restrained musical accents so the interface supports sustained writing without competing with the music.

The initial redesign covers Fretboard, Piano, Piano Roll, Writer, their shared dialogs/library, application navigation and the necessary Settings surfaces. **Song is temporarily unavailable in instrument UX V2.** Its navigation entry remains visible and disabled with an explanation. Keep its implementation, saved arrangements and serialization compatible for a later return; normal navigation must not mount it. Writer remains available. Embedded Roll editors must retain their host configuration and capabilities.

The app offers two presentation themes in Settings: **Studio** (default graphite/mint) and **Studio Muzician** (the same layout with Muzician's night/sky/teal/violet palette). The preference is device-local and persisted across launches; it does not belong to a project or named Save. Existing settings without this field select Studio. Switching themes must preserve projects, selections, playback position, edits, history, open panels and scroll state. This is a presentation change, not a project operation.

Fretboard and Piano share a visible project context, full screen title, dominant playable surface, one compact selection disclosure opening note details, Save idea and Add to Writer, and an inspector for Notes, Voicings and Setup. Scale and the full library remain discoverable. Instrument-specific controls remain explicit: compact Free/Chord and Full/Solo menus, tuning and capo for guitar; compact Full/Solo menu, range, octave and inversions for piano. Selection actions have a single home outside the inspector tabs. A closed inspector must not make essential actions unreachable. In V2, scrolling or expanding inspector tools must keep the playable instrument visible. Compact portrait uses a bounded lower inspector; wide and short landscape use a side inspector. Voicings stay in a horizontal carousel. **From notes** requires every captured pitch class and keeps added chord tones within the active scale, when set; **By chord** independently selects root/quality and shows available generated realizations within instrument bounds. Applying a result preserves the query and carousel position. Manual edits refresh the note query; an explicit Use current notes action also refreshes it.

Piano Roll retains all five tools, manual gestures, column detection, Stack Builder and Quick, scale, save/import and Hum Recorder. Mobile keeps snap in the borderless tool row and the pitch range as a gesture-driven transport readout; the inspector is limited to Stack Builder and Selection. Record must identify humming-to-notes, not suggest audio track or MIDI recording. Selection of a time column remains distinct from note selection.

Writer makes project/version actions, transport, section structure, Harmony source, chord/text relationship and contextual editing clearer. All lane types and existing safeguards remain available. Rhythmic step editors group subdivisions by beat with usable touch targets. Save idea, reusable Harmony, current auto-persisted draft and named Writer version have distinct labels. The existing music logic and save/link semantics above remain authoritative.

Success means users can identify the current project/workspace, play/select an idea, inspect a voicing, save it or place it in Writer, and edit/play a section without losing context. Verify empty, populated, long-name, exact-Harmony, out-of-key, shared-save and disabled-action states at compact and wide sizes. The selected concept images govern composition, density, control shapes and visual hierarchy. Compare populated runtime screenshots directly against them; implementation must preserve their character while adapting to real device safe areas, text scaling and actual musical content. Do not implement invented controls from them.
