/// Pure playback flattening for the Songwriter transport.
///
/// Turns a [SongwriterProjectSnapshot] into a sorted, tick-indexed event list
/// the transport can walk: harmony chords and save-block voicings fire as
/// per-bar stabs; drum lane blocks fire their pattern hits at native tick
/// resolution.
library;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../utils/note_utils.dart';
import 'fretboard_rules.dart';
import 'songwriter_rules.dart';

/// One audible moment on the flattened songwriter timeline.
class SongwriterPlaybackEvent {
  const SongwriterPlaybackEvent({
    required this.tick,
    this.midiNotes = const [],
    this.drumLanes = const [],
  });

  final int tick;
  final List<int> midiNotes;
  final List<DrumLaneId> drumLanes;
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
  final beatTicks = cfg.ticksPerBeat;
  final measureTicks = beatTicks * cfg.beatsPerBar;

  final byId = {for (final s in project.sections) s.id: s};
  final patterns = {for (final p in project.drumPatterns) p.id: p};
  final notesAt = <int, List<int>>{};
  final drumsAt = <int, Set<DrumLaneId>>{};

  for (final exp in expandSections(project.sections)) {
    final section = byId[exp.sectionId];
    if (section == null) continue;
    for (final lane in section.lanes) {
      final blocks = tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      );
      for (final block in blocks) {
        final clippedEnd = block.endBar > section.lengthBars
            ? section.lengthBars
            : block.endBar;
        switch (lane.kind) {
          case SongLaneKind.harmony:
          case SongLaneKind.save:
            final pitches = lane.kind == SongLaneKind.harmony
                ? chordMidiNotes(block)
                : snapshotMidiNotes(resolveBlockSnapshot(block, saves));
            if (pitches.isEmpty) break;
            for (var bar = block.startBar; bar < clippedEnd; bar++) {
              final tick = (exp.globalStartBar + bar) * measureTicks;
              (notesAt[tick] ??= []).addAll(pitches);
            }
          case SongLaneKind.drum:
            final pattern = patterns[block.patternId];
            if (pattern == null || pattern.lengthTicks <= 0) break;
            final startTick =
                (exp.globalStartBar + block.startBar) * measureTicks;
            final endTick = (exp.globalStartBar + clippedEnd) * measureTicks;
            for (
              var origin = 0;
              startTick + origin < endTick;
              origin += pattern.lengthTicks
            ) {
              for (final seq in pattern.lanes) {
                for (final t in seq.activeTicks) {
                  final tick = startTick + origin + t;
                  if (tick >= endTick) continue;
                  (drumsAt[tick] ??= {}).add(seq.laneId);
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

  final ticks = {...notesAt.keys, ...drumsAt.keys}.toList()..sort();
  return [
    for (final tick in ticks)
      SongwriterPlaybackEvent(
        tick: tick,
        midiNotes: notesAt[tick] ?? const [],
        drumLanes: drumsAt[tick]?.toList() ?? const [],
      ),
  ];
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
  final beatTicks = config.ticksPerBeat;
  final measureTicks = beatTicks * config.beatsPerBar;
  final loopTicks = section.lengthBars * measureTicks;
  final notesAt = <int, List<int>>{};

  for (final lane in section.lanes) {
    if (lane.kind == SongLaneKind.drum) continue;
    final blocks = tileLaneBlocks(lane, sectionLengthBars: section.lengthBars);
    for (final block in blocks) {
      final clippedEnd = block.endBar > section.lengthBars
          ? section.lengthBars
          : block.endBar;
      final pitches = lane.kind == SongLaneKind.harmony
          ? chordMidiNotes(block)
          : snapshotMidiNotes(resolveBlockSnapshot(block, saves));
      if (pitches.isEmpty) continue;
      for (var bar = block.startBar; bar < clippedEnd; bar++) {
        final tick = bar * measureTicks;
        (notesAt[tick] ??= <int>[]).addAll(pitches);
      }
    }
  }

  return (loopTicks: loopTicks, notesByTick: notesAt);
}
