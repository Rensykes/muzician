/// Pure playback flattening for the Songwriter transport.
///
/// Turns a [SongwriterProjectSnapshot] into a sorted, tick-indexed event list
/// the transport can walk: harmony chords and save-block voicings fire as
/// per-bar stabs; drum lane blocks fire their pattern hits at native tick
/// resolution.
library;

import 'dart:math' as math;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';
import 'fretboard_rules.dart';
import 'piano_roll_playback_rules.dart' as timing;
import 'songwriter_rules.dart';

/// Looping bed shape for the audio-clip audition's "with section" mode: the
/// section [loopTicks], its harmony/save voicings ([notesByTick]) and drum-lane
/// hits ([drumByTick]), all indexed from tick 0. Single source of truth shared
/// by [sectionAuditionBed] and the audition transport.
typedef SongwriterAuditionBed = ({
  int loopTicks,
  Map<int, List<int>> notesByTick,
  Map<int, List<DrumLaneId>> drumByTick,
});

/// Same-tick notes bucketed by their lane's (volume, pan) mix settings.
typedef SongwriterNoteGroup = ({
  double volume,
  double pan,
  List<int> midiNotes,
});

/// Same-tick drum hits bucketed by their lane's (volume, pan) mix settings.
typedef SongwriterDrumGroup = ({
  double volume,
  double pan,
  List<DrumLaneId> drumLanes,
});

/// Sequenced notes that need a duration-aware voice instead of a one-shot stab.
typedef SongwriterSequencedNoteGroup = ({
  double volume,
  double pan,
  List<NotePatternNote> notes,
});

/// One audible moment on the flattened songwriter timeline.
class SongwriterPlaybackEvent {
  const SongwriterPlaybackEvent({
    required this.tick,
    this.noteGroups = const [],
    this.drumGroups = const [],
    this.sequencedNoteGroups = const [],
  });

  final int tick;
  final List<SongwriterNoteGroup> noteGroups;
  final List<SongwriterDrumGroup> drumGroups;
  final List<SongwriterSequencedNoteGroup> sequencedNoteGroups;

  /// Flat views across all mix groups, for callers that ignore mixing.
  List<int> get midiNotes => [
    for (final g in noteGroups) ...g.midiNotes,
    for (final g in sequencedNoteGroups)
      for (final note in g.notes) note.midiNote,
  ];
  List<DrumLaneId> get drumLanes => [
    for (final g in drumGroups) ...g.drumLanes,
  ];
}

/// Midi pitches for a harmony block as an ascending stack from octave 4.
///
/// Uses [SongBlock.chordNotes] (pitch-class names, root first) when present;
/// falls back to [SongBlock.chordRootPc] + [SongBlock.chordQuality] intervals.
/// Returns empty for silent / chord-less blocks.
List<int> chordMidiNotes(SongBlock block) {
  if (block.isSilent) return const [];
  if (block.chordNotes.isNotEmpty) {
    final pcs = <int>[];
    for (final name in block.chordNotes) {
      final pc = noteToPC[name];
      if (pc != null) pcs.add(pc);
    }
    if (pcs.isNotEmpty) return _ascendingStack(pcs);
  }
  final rootPc = block.chordRootPc;
  if (rootPc == null) return const [];
  final intervals = chordIntervals[block.chordQuality ?? ''] ?? const [0, 4, 7];
  return [for (final i in intervals) 60 + rootPc + i];
}

/// Stacks pitch classes upward starting at octave 4 (midi 60..71 for the
/// first note); each subsequent note lands at the next pitch above its
/// predecessor.
List<int> _ascendingStack(List<int> pcs) {
  final out = <int>[60 + pcs.first];
  for (var i = 1; i < pcs.length; i++) {
    var midi = 60 + pcs[i];
    while (midi <= out.last) {
      midi += 12;
    }
    out.add(midi);
  }
  return out;
}

/// Midi pitches for a save-block snapshot, sorted ascending.
///
/// Piano snapshots read [PianoCoordinate.midiNote]; fretboard snapshots map
/// string+fret through the tuning's open-string midi. Other snapshot types
/// (and broken blocks resolved to null) are silent.
List<int> snapshotMidiNotes(InstrumentSnapshot? snapshot) {
  if (snapshot is PianoSnapshot) {
    return [for (final k in snapshot.selectedKeys) k.midiNote]..sort();
  }
  if (snapshot is FretboardSnapshot) {
    final tuning = tunings[snapshot.tuning];
    if (tuning == null) return const [];
    final out = <int>[];
    for (final cell in snapshot.selectedCells) {
      if (cell.stringIndex < 0 || cell.stringIndex >= tuning.strings.length) {
        continue;
      }
      out.add(tuning.strings[cell.stringIndex].midiNote + cell.fret);
    }
    return out..sort();
  }
  return const [];
}

/// Where the playhead sits inside the sheet layout.
class SongwriterActivePosition {
  const SongwriterActivePosition({
    required this.sectionId,
    required this.instanceIndex,
    required this.localBar,
  });

  final String sectionId;
  final int instanceIndex;
  final int localBar;
}

/// Maps a global playback bar to (sectionId, instanceIndex, localBar).
SongwriterActivePosition? activePositionForBar(
  List<SongSection> sections,
  int globalBar,
) {
  final hit = sectionAtGlobalBar(expandSections(sections), globalBar);
  if (hit == null) return null;
  return SongwriterActivePosition(
    sectionId: hit.section.sectionId,
    instanceIndex: hit.section.repeatIndex,
    localBar: hit.localBar,
  );
}

/// Pitches for a harmony or save [block]: the chord voicing for harmony lanes,
/// the resolved snapshot's notes for save lanes.
List<int> _blockPitches(
  SongLane lane,
  SongBlock block,
  List<SaveEntry> saves,
) => lane.kind == SongLaneKind.harmony
    ? chordMidiNotes(block)
    : snapshotMidiNotes(resolveBlockSnapshot(block, saves));

SongLane? _strumHarmonyLane(SongSection section, SongLane lane) {
  for (final candidate in section.lanes) {
    if (candidate.id == lane.anchorLaneId &&
        candidate.kind == SongLaneKind.harmony) {
      return candidate;
    }
  }
  return primaryHarmonyLane(section);
}

List<int> _harmonyAtTick(
  SongLane? harmonyLane,
  SongSection section,
  int sectionTick,
  int measureTicks,
) {
  if (harmonyLane == null || sectionTick < 0) return const [];
  final bar = sectionTick ~/ measureTicks;
  for (final block in tileLaneBlocks(
    harmonyLane,
    sectionLengthBars: section.lengthBars,
  )) {
    if (bar >= block.startBar &&
        bar < math.min(block.endBar, section.lengthBars)) {
      return chordMidiNotes(block);
    }
  }
  return const [];
}

/// Tiles [pattern]'s hits across `[startTick, endTick)` into [drumsAt]
/// (tick → lane-id set), repeating the pattern every [DrumPattern.lengthTicks].
void _tileDrumHits(
  DrumPattern pattern,
  int startTick,
  int endTick,
  Map<int, Set<DrumLaneId>> drumsAt,
) {
  for (
    var origin = 0;
    startTick + origin < endTick;
    origin += pattern.lengthTicks
  ) {
    for (final seq in pattern.lanes) {
      for (final t in seq.activeTicks) {
        final tick = startTick + origin + t;
        if (tick >= endTick) continue;
        (drumsAt[tick] ??= <DrumLaneId>{}).add(seq.laneId);
      }
    }
  }
}

/// Flattens [project] into a sorted, tick-indexed event list.
///
/// Sections expand by repeat (via [expandSections]); lane block patterns tile
/// by lane repeat (via [tileLaneBlocks]). Harmony and save blocks fire their
/// pitches at the block's start bar and every later bar boundary inside the
/// block (clipped to the section); drum blocks fire their referenced
/// [DrumPattern] hits at native tick resolution, tiled across the block span.
/// Events sharing a tick are merged.
List<SongwriterPlaybackEvent> flattenPlaybackEvents(
  SongwriterProjectSnapshot project,
  List<SaveEntry> saves,
) {
  final cfg = project.config;
  final measureTicks = cfg.measureTicks;

  final byId = {for (final s in project.sections) s.id: s};
  final patterns = {for (final p in project.drumPatterns) p.id: p};
  final melodyPatterns = {for (final p in project.melodyPatterns) p.id: p};
  final strumPatterns = {for (final p in project.guitarStrumPatterns) p.id: p};
  // tick → (volume, pan) → accumulated notes / drum hits.
  final notesAt = <int, Map<(double, double), List<int>>>{};
  final drumsAt = <int, Map<(double, double), Set<DrumLaneId>>>{};
  final sequencedAt =
      <int, Map<(double, double, int, int, int), List<NotePatternNote>>>{};

  void addSequencedNote({
    required int tick,
    required int midiNote,
    required int durationTicks,
    required int onsetOffsetMs,
    required int durationOffsetMs,
    required double volume,
    required double pan,
    required String id,
  }) {
    if (durationTicks <= 0) return;
    final key = (volume, pan, durationTicks, onsetOffsetMs, durationOffsetMs);
    ((sequencedAt[tick] ??= {})[key] ??= []).add(
      NotePatternNote(
        id: id,
        midiNote: midiNote,
        startTick: tick,
        durationTicks: durationTicks,
        onsetOffsetMs: onsetOffsetMs,
        durationOffsetMs: durationOffsetMs,
      ),
    );
  }

  int clippedDurationOffsetMs({
    required int durationTicks,
    required int onsetOffsetMs,
    required int availableTicks,
  }) =>
      (availableTicks * timing.millisecondsPerTick(cfg.tempo) -
              onsetOffsetMs -
              durationTicks * timing.millisecondsPerTick(cfg.tempo))
          .floor()
          .clamp(
            -durationTicks * timing.millisecondsPerTick(cfg.tempo).floor() + 1,
            0,
          )
          .toInt();

  for (final exp in expandSections(project.sections)) {
    final section = byId[exp.sectionId];
    if (section == null) continue;
    for (final lane in section.lanes) {
      final mix = mixGoverningLane(section, lane);
      if (mix.muted) continue;
      final mixKey = (mix.volume, mix.pan);
      final blocks = tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      );
      for (final block in blocks) {
        final clippedEnd = math.min(block.endBar, section.lengthBars);
        switch (lane.kind) {
          case SongLaneKind.harmony:
          case SongLaneKind.save:
            final pitches = _blockPitches(lane, block, saves);
            if (pitches.isEmpty) break;
            for (var bar = block.startBar; bar < clippedEnd; bar++) {
              final tick = (exp.globalStartBar + bar) * measureTicks;
              ((notesAt[tick] ??= {})[mixKey] ??= []).addAll(pitches);
            }
          case SongLaneKind.drum:
            final pattern = patterns[block.patternId];
            if (pattern == null || pattern.lengthTicks <= 0) break;
            final startTick =
                (exp.globalStartBar + block.startBar) * measureTicks;
            final endTick = (exp.globalStartBar + clippedEnd) * measureTicks;
            final laneDrums = <int, Set<DrumLaneId>>{};
            _tileDrumHits(pattern, startTick, endTick, laneDrums);
            for (final e in laneDrums.entries) {
              ((drumsAt[e.key] ??= {})[mixKey] ??= <DrumLaneId>{}).addAll(
                e.value,
              );
            }
          case SongLaneKind.melody:
            final pattern = melodyPatterns[block.patternId];
            if (pattern == null || pattern.lengthTicks <= 0) break;
            final startTick =
                (exp.globalStartBar + block.startBar) * measureTicks;
            final endTick = (exp.globalStartBar + clippedEnd) * measureTicks;
            for (
              var loopOffset = 0;
              startTick + loopOffset < endTick;
              loopOffset += pattern.lengthTicks
            ) {
              final loopStart = startTick + loopOffset;
              final loopEnd = math.min(
                endTick,
                loopStart + pattern.lengthTicks,
              );
              for (final note in pattern.notes) {
                if (note.startTick < 0 ||
                    note.startTick >= pattern.lengthTicks) {
                  continue;
                }
                final tick = loopStart + note.startTick;
                if (tick >= loopEnd) continue;
                final duration = math.min(
                  math.max(1, note.durationTicks),
                  loopEnd - tick,
                );
                final onsetOffsetMs = math.max(0, note.onsetOffsetMs);
                addSequencedNote(
                  tick: tick,
                  midiNote: note.midiNote,
                  durationTicks: duration,
                  onsetOffsetMs: onsetOffsetMs,
                  durationOffsetMs: clippedDurationOffsetMs(
                    durationTicks: duration,
                    onsetOffsetMs: onsetOffsetMs,
                    availableTicks: loopEnd - tick,
                  ),
                  volume: mix.volume,
                  pan: mix.pan,
                  id: note.id,
                );
              }
            }
          case SongLaneKind.guitarStrum:
            final pattern = strumPatterns[block.patternId];
            if (pattern == null || pattern.lengthTicks <= 0) break;
            final startTick =
                (exp.globalStartBar + block.startBar) * measureTicks;
            final endTick = (exp.globalStartBar + clippedEnd) * measureTicks;
            final harmonyLane = _strumHarmonyLane(section, lane);
            final gateTicks = math.max(1, cfg.ticksPerBeat ~/ 2);
            for (
              var loopOffset = 0;
              startTick + loopOffset < endTick;
              loopOffset += pattern.lengthTicks
            ) {
              final loopStart = startTick + loopOffset;
              final loopEnd = math.min(
                endTick,
                loopStart + pattern.lengthTicks,
              );
              for (final strumEvent in pattern.events) {
                if (strumEvent.tick < 0 ||
                    strumEvent.tick >= pattern.lengthTicks) {
                  continue;
                }
                final tick = loopStart + strumEvent.tick;
                if (tick >= loopEnd) continue;
                final sectionTick =
                    block.startBar * measureTicks +
                    loopOffset +
                    strumEvent.tick;
                final pitches = _harmonyAtTick(
                  harmonyLane,
                  section,
                  sectionTick,
                  measureTicks,
                );
                if (pitches.isEmpty) continue;
                final orderedPitches =
                    strumEvent.direction == GuitarStrumDirection.down
                    ? pitches
                    : pitches.reversed.toList();
                final duration = math.min(
                  gateTicks,
                  math.min(loopEnd - tick, endTick - tick),
                );
                final availableTicks = math.min(loopEnd - tick, endTick - tick);
                for (var i = 0; i < orderedPitches.length; i++) {
                  final onsetOffsetMs = i * 12;
                  addSequencedNote(
                    tick: tick,
                    midiNote: orderedPitches[i],
                    durationTicks: duration,
                    onsetOffsetMs: onsetOffsetMs,
                    durationOffsetMs: clippedDurationOffsetMs(
                      durationTicks: duration,
                      onsetOffsetMs: onsetOffsetMs,
                      availableTicks: availableTicks,
                    ),
                    volume: mix.volume,
                    pan: mix.pan,
                    id: 'strum_${block.id}_${tick}_$i',
                  );
                }
              }
            }
          case SongLaneKind.audio:
            // Audio clips are scheduled directly by the transport, not emitted
            // as tick-indexed note/drum events here.
            break;
        }
      }
    }
  }

  final ticks = {...notesAt.keys, ...drumsAt.keys, ...sequencedAt.keys}.toList()
    ..sort();
  return [
    for (final tick in ticks)
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
        sequencedNoteGroups: [
          for (final e in (sequencedAt[tick] ?? const {}).entries)
            (volume: e.key.$1, pan: e.key.$2, notes: e.value),
        ],
      ),
  ];
}

/// Per-tick harmony + save voicing stabs for one section, indexed from tick 0.
/// Drum and audio lanes are skipped. Shared by [sectionHarmonyLoop] and
/// [sectionAuditionBed].
Map<int, List<int>> _sectionChordBed(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves,
) {
  final measureTicks = config.measureTicks;
  final notesAt = <int, List<int>>{};
  for (final lane in section.lanes) {
    if (lane.kind == SongLaneKind.drum || lane.kind == SongLaneKind.audio) {
      continue;
    }
    if (mixGoverningLane(section, lane).muted) continue;
    final blocks = tileLaneBlocks(lane, sectionLengthBars: section.lengthBars);
    for (final block in blocks) {
      final clippedEnd = math.min(block.endBar, section.lengthBars);
      final pitches = _blockPitches(lane, block, saves);
      if (pitches.isEmpty) continue;
      for (var bar = block.startBar; bar < clippedEnd; bar++) {
        (notesAt[bar * measureTicks] ??= <int>[]).addAll(pitches);
      }
    }
  }
  return notesAt;
}

/// One looping backing bed for a single section's harmony, for the drum
/// editor's "audition with backing" mode.
///
/// Returns the section's loop length in ticks and a `tick → midi pitches` map
/// of per-bar chord stabs, indexed from tick 0. Harmony lanes use
/// [chordMidiNotes]; save lanes use [snapshotMidiNotes]. Drum lanes are
/// excluded — the backing is the chord bed only. Blocks tile via
/// [tileLaneBlocks] and are clipped to the section.
({int loopTicks, Map<int, List<int>> notesByTick}) sectionHarmonyLoop(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves,
) {
  final measureTicks = config.measureTicks;
  return (
    loopTicks: section.lengthBars * measureTicks,
    notesByTick: _sectionChordBed(section, config, saves),
  );
}

/// Looping bed for the audio-clip audition's "with section" mode: the section's
/// harmony + save voicings ([notesByTick]) and drum-lane hits ([drumByTick]),
/// both indexed from tick 0, plus the section [loopTicks]. Audio lanes are
/// excluded — the audition's recording is the foreground.
SongwriterAuditionBed sectionAuditionBed(
  SongSection section,
  SongwriterConfig config,
  List<SaveEntry> saves, {
  List<DrumPattern> drumPatterns = const [],
}) {
  final measureTicks = config.measureTicks;
  final patterns = {for (final p in drumPatterns) p.id: p};
  final drumsAt = <int, Set<DrumLaneId>>{};

  for (final lane in section.lanes) {
    if (lane.kind != SongLaneKind.drum || lane.muted) continue;
    for (final block in tileLaneBlocks(
      lane,
      sectionLengthBars: section.lengthBars,
    )) {
      final pattern = patterns[block.patternId];
      if (pattern == null || pattern.lengthTicks <= 0) continue;
      final clippedEnd = math.min(block.endBar, section.lengthBars);
      final startTick = block.startBar * measureTicks;
      final endTick = clippedEnd * measureTicks;
      _tileDrumHits(pattern, startTick, endTick, drumsAt);
    }
  }

  return (
    loopTicks: section.lengthBars * measureTicks,
    notesByTick: _sectionChordBed(section, config, saves),
    drumByTick: {for (final e in drumsAt.entries) e.key: e.value.toList()},
  );
}

/// Global transport tick for [localBar] within the [instanceIndex]-th occurrence
/// of [sectionId] on the flattened timeline. [localBar] is clamped to the
/// section's bar range; an out-of-range [instanceIndex] or unknown section falls
/// back to the first occurrence / tick 0. Used by the "Play from here" action.
int sectionBarGlobalTick(
  List<SongSection> sections,
  SongwriterConfig config,
  String sectionId,
  int localBar, {
  int instanceIndex = 0,
}) {
  final measureTicks = config.measureTicks;
  final occurrences = expandSections(
    sections,
  ).where((e) => e.sectionId == sectionId).toList();
  if (occurrences.isEmpty) return 0;
  final occ = (instanceIndex >= 0 && instanceIndex < occurrences.length)
      ? occurrences[instanceIndex]
      : occurrences.first;
  final maxLocal = occ.lengthBars - 1;
  final clamped = localBar < 0
      ? 0
      : (localBar > maxLocal ? maxLocal : localBar);
  return (occ.globalStartBar + clamped) * measureTicks;
}
