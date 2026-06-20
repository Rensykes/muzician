/// Writer → Song bridge: converts a Songwriter arrangement into a Song
/// project skeleton (tracks, clips, patterns, markers).
library;

import '../../models/save_system.dart';
import '../../models/song_project.dart';
import '../../models/songwriter.dart';
import '../../models/piano_roll.dart' show TimeSignature;
import '../../utils/note_utils.dart';
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
///   the resolved snapshots ([saves] is the live save list).
SongProject songFromSongwriter(
  SongwriterProjectSnapshot project,
  List<SaveEntry> saves,
) {
  final cfg = project.config;
  final beatTicks = cfg.ticksPerBeat;
  final measureTicks = beatTicks * cfg.beatsPerBar;
  final totalBars = flattenedBarCount(project.sections).clamp(1, 32);

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

  // Collect lanes by kind across all sections (a lane belongs to a section,
  // but musically the harmony lanes form one voice).
  final harmonyTrackId = nextId('trk');
  var harmonyUsed = false;
  final drumTrackIdByLane = <String, String>{};
  final saveTrackIdByLane = <String, String>{};

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
        final startTick =
            (exp.globalStartBar + block.startBar) * measureTicks;
        switch (lane.kind) {
          case SongLaneKind.harmony:
            final midiNotes = chordMidiNotes(block);
            if (midiNotes.isEmpty) break;
            harmonyUsed = true;
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
              trackId: harmonyTrackId,
              patternId: patternId,
              type: SongPatternType.note,
              startTick: startTick,
            );
          case SongLaneKind.save:
            final midiNotes = snapshotMidiNotes(
              resolveBlockSnapshot(block, saves),
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
        }
      }
    }
  }

  if (harmonyUsed) {
    tracks.insert(
      0,
      SongTrack(
        id: harmonyTrackId,
        name: 'Harmony',
        type: SongTrackType.note,
        order: 0,
      ),
    );
  }
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
