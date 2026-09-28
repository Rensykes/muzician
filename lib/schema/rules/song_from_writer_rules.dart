/// Writer → Song bridge: converts a Songwriter arrangement into a Song
/// project skeleton (tracks, clips, patterns, markers).
library;

import 'dart:math' as math;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../models/piano_roll.dart' show TimeSignature;
import '../../utils/note_utils.dart';
import 'piano_roll_playback_rules.dart' as timing;
import 'songwriter_playback_rules.dart';
import 'songwriter_rules.dart';

/// Builds a [SongProject] from a Songwriter [project]:
///
/// - tempo / time signature / key copied from the Writer config; total
///   measures = the flattened bar count (clamped to the Song's 1..32 range);
/// - one marker per expanded section instance (label = section label);
/// - the harmony lane becomes a note track with per-bar chord-stab patterns
///   (one pattern per block, reused across section repeats);
/// - each drum lane becomes a drum track whose blocks reference the carried
///   over [DrumPattern]s;
/// - each save lane becomes a note track of stacked-chord patterns built from
///   the resolved snapshots ([saves] is the live save list, scoped by
///   [projectId] and [folders]).
/// - melody lanes and guitar-strum lanes become duration-aware note tracks;
///   Writer audio lanes are not transferred.
SongProject songFromSongwriter(
  SongwriterProjectSnapshot project,
  List<SaveEntry> saves, {
  String? projectId,
  List<SaveFolder> folders = const [],
}) {
  final cfg = project.config;
  final beatTicks = cfg.ticksPerBeat;
  final measureTicks = cfg.measureTicks;
  final totalBars = flattenedBarCount(project.sections).clamp(1, 32);
  final tickMs = timing.millisecondsPerTick(cfg.tempo);

  int clippedDurationOffsetMs({
    required int durationTicks,
    required int onsetOffsetMs,
    required int availableTicks,
  }) => (availableTicks * tickMs - onsetOffsetMs - durationTicks * tickMs)
      .floor()
      .clamp(-durationTicks * tickMs.floor() + 1, 0)
      .toInt();

  final expanded = expandSections(project.sections);
  final sectionById = {for (final s in project.sections) s.id: s};

  var idCounter = 0;
  String nextId(String prefix) => '${prefix}_w2s_${idCounter++}';

  // ── Markers ──────────────────────────────────────────────────────────────
  final markers = <SongMarker>[
    for (final exp in expanded)
      SongMarker(
        id: nextId('mk'),
        tick: exp.globalStartBar * measureTicks,
        label: sectionById[exp.sectionId]?.label ?? 'Section',
      ),
  ];

  // ── Tracks / patterns / clips ────────────────────────────────────────────
  final tracks = <SongTrack>[];
  final clips = <SongClipInstance>[];
  final notePatterns = <NotePattern>[];
  final drumPatterns = <DrumPattern>[];

  // One note pattern per harmony/save block id (reused across repeats).
  final patternByBlockId = <String, String>{};
  final strumPatternByPlacement = <(String, String, String, int), String>{};
  final usedDrumPatternIds = <String>{};

  NotePattern stabPattern({
    required String patternId,
    required String name,
    required List<int> midiNotes,
    required int spanBars,
  }) {
    final notes = <NotePatternNote>[];
    for (var bar = 0; bar < spanBars; bar++) {
      for (final midi in midiNotes) {
        notes.add(
          NotePatternNote(
            id: nextId('n'),
            midiNote: midi,
            startTick: bar * measureTicks,
            durationTicks: beatTicks,
          ),
        );
      }
    }
    var minMidi = 48, maxMidi = 84;
    if (midiNotes.isNotEmpty) {
      minMidi = midiNotes.reduce((a, b) => a < b ? a : b) - 5;
      maxMidi = midiNotes.reduce((a, b) => a > b ? a : b) + 5;
    }
    return NotePattern(
      id: patternId,
      name: name,
      lengthTicks: spanBars * measureTicks,
      notes: notes,
      pitchRangeStart: minMidi.clamp(0, 127),
      pitchRangeEnd: maxMidi.clamp(0, 127),
      snapTicks: 1,
      highlightedNotes: const [],
    );
  }

  NotePattern melodyPattern({
    required String patternId,
    required NotePattern source,
    required int blockLengthTicks,
  }) {
    final notes = <NotePatternNote>[];
    if (source.lengthTicks > 0) {
      for (
        var loopOffset = 0;
        loopOffset < blockLengthTicks;
        loopOffset += source.lengthTicks
      ) {
        for (final note in source.notes) {
          if (note.startTick < 0 || note.startTick >= source.lengthTicks) {
            continue;
          }
          final startTick = loopOffset + note.startTick;
          if (startTick >= blockLengthTicks) continue;
          final duration = math.min(
            math.max(1, note.durationTicks),
            math.min(
              source.lengthTicks - note.startTick,
              blockLengthTicks - startTick,
            ),
          );
          final availableTicks = math.min(
            source.lengthTicks - note.startTick,
            blockLengthTicks - startTick,
          );
          final onsetOffsetMs = math.max(0, note.onsetOffsetMs);
          notes.add(
            NotePatternNote(
              id: nextId('n'),
              midiNote: note.midiNote,
              startTick: startTick,
              durationTicks: duration,
              onsetOffsetMs: onsetOffsetMs,
              durationOffsetMs: clippedDurationOffsetMs(
                durationTicks: duration,
                onsetOffsetMs: onsetOffsetMs,
                availableTicks: availableTicks,
              ),
            ),
          );
        }
      }
    }
    return NotePattern(
      id: patternId,
      name: source.name,
      lengthTicks: blockLengthTicks,
      notes: notes,
      pitchRangeStart: source.pitchRangeStart,
      pitchRangeEnd: source.pitchRangeEnd,
      snapTicks: source.snapTicks,
      highlightedNotes: source.highlightedNotes,
    );
  }

  SongLane? strumHarmonyLane(SongSection section, SongLane lane) {
    if (lane.anchorLaneId == null) return primaryHarmonyLane(section);
    for (final candidate in section.lanes) {
      if (candidate.id == lane.anchorLaneId &&
          candidate.kind == SongLaneKind.harmony) {
        return candidate;
      }
    }
    return null;
  }

  List<int> harmonyAtTick(
    SongLane? harmonyLane,
    SongSection section,
    int sectionTick,
  ) {
    if (harmonyLane == null || sectionTick < 0) return const [];
    final bar = sectionTick ~/ measureTicks;
    for (final harmonyBlock in tileLaneBlocks(
      harmonyLane,
      sectionLengthBars: section.lengthBars,
    )) {
      if (bar >= harmonyBlock.startBar &&
          bar < math.min(harmonyBlock.endBar, section.lengthBars)) {
        return chordMidiNotes(harmonyBlock);
      }
    }
    return const [];
  }

  NotePattern guitarStrumPattern({
    required String patternId,
    required SongSection section,
    required SongLane lane,
    required SongBlock block,
    required GuitarStrumPattern source,
    required int blockLengthTicks,
  }) {
    final notes = <NotePatternNote>[];
    final harmonyLane = strumHarmonyLane(section, lane);
    final gateTicks = math.max(1, cfg.ticksPerBeat ~/ 2);
    if (source.lengthTicks > 0) {
      for (
        var loopOffset = 0;
        loopOffset < blockLengthTicks;
        loopOffset += source.lengthTicks
      ) {
        final loopEnd = math.min(
          blockLengthTicks,
          loopOffset + source.lengthTicks,
        );
        for (final event in source.events) {
          if (event.tick < 0 || event.tick >= source.lengthTicks) continue;
          final startTick = loopOffset + event.tick;
          if (startTick >= blockLengthTicks || startTick >= loopEnd) continue;
          final sectionTick = block.startBar * measureTicks + startTick;
          final chord = harmonyAtTick(harmonyLane, section, sectionTick);
          if (chord.isEmpty) continue;
          final pitches = event.direction == GuitarStrumDirection.down
              ? chord
              : chord.reversed.toList();
          final duration = math.min(
            gateTicks,
            math.min(loopEnd - startTick, blockLengthTicks - startTick),
          );
          final availableTicks = math.min(
            loopEnd - startTick,
            blockLengthTicks - startTick,
          );
          for (var i = 0; i < pitches.length; i++) {
            final onsetOffsetMs = i * 12;
            notes.add(
              NotePatternNote(
                id: nextId('n'),
                midiNote: pitches[i],
                startTick: startTick,
                durationTicks: duration,
                onsetOffsetMs: onsetOffsetMs,
                durationOffsetMs: clippedDurationOffsetMs(
                  durationTicks: duration,
                  onsetOffsetMs: onsetOffsetMs,
                  availableTicks: availableTicks,
                ),
              ),
            );
          }
        }
      }
    }
    var minMidi = 48, maxMidi = 84;
    if (notes.isNotEmpty) {
      minMidi = notes.map((note) => note.midiNote).reduce(math.min) - 5;
      maxMidi = notes.map((note) => note.midiNote).reduce(math.max) + 5;
    }
    return NotePattern(
      id: patternId,
      name: source.name,
      lengthTicks: blockLengthTicks,
      notes: notes,
      pitchRangeStart: minMidi.clamp(0, 127),
      pitchRangeEnd: maxMidi.clamp(0, 127),
      snapTicks: 1,
      highlightedNotes: const [],
    );
  }

  // Collect lanes by kind across all sections. A lane belongs to a section,
  // but musically the N-th harmony lane of every section forms one voice —
  // one Song track per harmony-lane index. Track name/volume come from the
  // first section seen with a lane at that index.
  final harmonyTrackByIndex = <int, SongTrack>{};
  final drumTrackIdByLane = <String, String>{};
  final saveTrackIdByLane = <String, String>{};
  final melodyTrackIdByLane = <String, String>{};
  final strumTrackIdByLane = <String, String>{};

  double laneTrackVolume(SongLane lane) => lane.muted ? 0.0 : lane.volume;

  void placeClip({
    required String trackId,
    required String patternId,
    required SongPatternType type,
    required int startTick,
  }) {
    // Skip exact-duplicate placements (overlaps are pre-empted by the
    // Writer's own no-overlap invariant within a lane).
    if (clips.any((c) => c.trackId == trackId && c.startTick == startTick)) {
      return;
    }
    clips.add(
      SongClipInstance(
        id: nextId('sci'),
        trackId: trackId,
        patternId: patternId,
        patternType: type,
        startTick: startTick,
      ),
    );
  }

  for (final exp in expanded) {
    final section = sectionById[exp.sectionId];
    if (section == null) continue;
    final harmonyLanes = section.lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();
    final harmonyIndexByLaneId = {
      for (var i = 0; i < harmonyLanes.length; i++) harmonyLanes[i].id: i,
    };
    for (final lane in section.lanes) {
      final placements = tileLaneBlocks(
        lane,
        sectionLengthBars: section.lengthBars,
      );
      for (final block in placements) {
        // Clamp the block span to its section so repeats never collide.
        final clampedSpan =
            (block.endBar > section.lengthBars
                    ? section.lengthBars - block.startBar
                    : block.spanBars)
                .clamp(1, section.lengthBars);
        final startTick = (exp.globalStartBar + block.startBar) * measureTicks;
        switch (lane.kind) {
          case SongLaneKind.audio:
            // Audio lanes are not exported to the Song arrangement.
            break;
          case SongLaneKind.harmony:
            final midiNotes = chordMidiNotes(block);
            if (midiNotes.isEmpty) break;
            final hIdx = harmonyIndexByLaneId[lane.id]!;
            final track = harmonyTrackByIndex.putIfAbsent(
              hIdx,
              () => SongTrack(
                id: nextId('trk'),
                name: lane.label ?? harmonyLaneFallbackLabel(hIdx),
                type: SongTrackType.note,
                order: 0, // re-numbered below
                volume: laneTrackVolume(lane),
              ),
            );
            final patternId = patternByBlockId.putIfAbsent(block.id, () {
              final id = nextId('np');
              notePatterns.add(
                stabPattern(
                  patternId: id,
                  name: block.chordSymbol ?? 'Chord',
                  midiNotes: midiNotes,
                  spanBars: clampedSpan,
                ),
              );
              return id;
            });
            placeClip(
              trackId: track.id,
              patternId: patternId,
              type: SongPatternType.note,
              startTick: startTick,
            );
          case SongLaneKind.save:
            final midiNotes = snapshotMidiNotes(
              resolveBlockSnapshot(
                block,
                saves,
                projectId: projectId,
                folders: folders,
              ),
            );
            if (midiNotes.isEmpty) break;
            final trackId = saveTrackIdByLane.putIfAbsent(lane.id, () {
              final id = nextId('trk');
              tracks.add(
                SongTrack(
                  id: id,
                  name: lane.label ?? 'Save lane',
                  type: SongTrackType.note,
                  order: 0, // re-numbered below
                  // Save lanes have no mix of their own — they follow the
                  // section's primary harmony lane (see mixGoverningLane).
                  volume: laneTrackVolume(mixGoverningLane(section, lane)),
                ),
              );
              return id;
            });
            final patternId = patternByBlockId.putIfAbsent(block.id, () {
              final id = nextId('np');
              notePatterns.add(
                stabPattern(
                  patternId: id,
                  name: lane.label ?? 'Voicing',
                  midiNotes: midiNotes,
                  spanBars: clampedSpan,
                ),
              );
              return id;
            });
            placeClip(
              trackId: trackId,
              patternId: patternId,
              type: SongPatternType.note,
              startTick: startTick,
            );
          case SongLaneKind.drum:
            final source = project.drumPatterns
                .where((p) => p.id == block.patternId)
                .firstOrNull;
            if (source == null) break;
            final trackId = drumTrackIdByLane.putIfAbsent(lane.id, () {
              final id = nextId('trk');
              tracks.add(
                SongTrack(
                  id: id,
                  name: lane.label ?? 'Drums',
                  type: SongTrackType.drum,
                  order: 0,
                  volume: laneTrackVolume(lane),
                ),
              );
              return id;
            });
            if (usedDrumPatternIds.add(source.id)) {
              drumPatterns.add(source);
            }
            placeClip(
              trackId: trackId,
              patternId: source.id,
              type: SongPatternType.drum,
              startTick: startTick,
            );
          case SongLaneKind.melody:
            final source = project.melodyPatterns
                .where((pattern) => pattern.id == block.patternId)
                .firstOrNull;
            if (source == null) break;
            final trackId = melodyTrackIdByLane.putIfAbsent(lane.id, () {
              final id = nextId('trk');
              tracks.add(
                SongTrack(
                  id: id,
                  name: lane.label ?? 'Melody',
                  type: SongTrackType.note,
                  order: 0,
                  volume: laneTrackVolume(lane),
                ),
              );
              return id;
            });
            final patternId = patternByBlockId.putIfAbsent(block.id, () {
              final id = nextId('np');
              notePatterns.add(
                melodyPattern(
                  patternId: id,
                  source: source,
                  blockLengthTicks: clampedSpan * measureTicks,
                ),
              );
              return id;
            });
            placeClip(
              trackId: trackId,
              patternId: patternId,
              type: SongPatternType.note,
              startTick: startTick,
            );
          case SongLaneKind.guitarStrum:
            final source = project.guitarStrumPatterns
                .where((pattern) => pattern.id == block.patternId)
                .firstOrNull;
            if (source == null) break;
            final trackId = strumTrackIdByLane.putIfAbsent(lane.id, () {
              final id = nextId('trk');
              tracks.add(
                SongTrack(
                  id: id,
                  name: lane.label ?? 'Guitar strum',
                  type: SongTrackType.note,
                  order: 0,
                  volume: laneTrackVolume(lane),
                ),
              );
              return id;
            });
            final patternId = strumPatternByPlacement.putIfAbsent(
              (section.id, lane.id, block.id, block.startBar),
              () {
                final id = nextId('np');
                notePatterns.add(
                  guitarStrumPattern(
                    patternId: id,
                    section: section,
                    lane: lane,
                    block: block,
                    source: source,
                    blockLengthTicks: clampedSpan * measureTicks,
                  ),
                );
                return id;
              },
            );
            placeClip(
              trackId: trackId,
              patternId: patternId,
              type: SongPatternType.note,
              startTick: startTick,
            );
        }
      }
    }
  }

  final harmonyIndexes = harmonyTrackByIndex.keys.toList()..sort();
  tracks.insertAll(0, [
    for (final i in harmonyIndexes) harmonyTrackByIndex[i]!,
  ]);
  final orderedTracks = [
    for (var i = 0; i < tracks.length; i++) tracks[i].copyWith(order: i),
  ];

  return SongProject(
    config: SongProjectConfig(
      tempo: cfg.tempo,
      timeSignature: TimeSignature(
        beatsPerMeasure: cfg.beatsPerBar,
        beatUnit: cfg.beatUnit,
      ),
      totalMeasures: totalBars,
      scaleRoot: cfg.keyRoot == null ? null : chromaticNotes[cfg.keyRoot!],
      scaleName: cfg.keyScaleName,
    ),
    tracks: orderedTracks,
    clips: clips,
    notePatterns: notePatterns,
    drumPatterns: drumPatterns,
    markers: markers,
  );
}
