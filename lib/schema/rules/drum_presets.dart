/// Built-in drum loop + fill library.
///
/// Presets are pure, code-defined templates (no persistence). Each carries a
/// per-voice hit map on a 16-tick (one-bar, sixteenth-grid) pattern. [buildLanes]
/// always materialises all eight [DrumLaneId] voices (empty where unused) so an
/// applied preset fills the full editor grid.
library;

import '../../models/song_project.dart';

class DrumPreset {
  final String name;
  final String category;
  final int lengthTicks;
  final Map<DrumLaneId, List<int>> hits;

  const DrumPreset({
    required this.name,
    required this.category,
    required this.hits,
    this.lengthTicks = 16,
  });

  /// All eight voices in [DrumLaneId] order, empty where the preset has no hits.
  List<DrumLaneSequence> buildLanes() => [
    for (final id in DrumLaneId.values)
      DrumLaneSequence(laneId: id, activeTicks: hits[id] ?? const []),
  ];

  /// A concrete [DrumPattern] with the given [id], adopting this preset's
  /// name, length, and voices.
  DrumPattern toPattern(String id) => DrumPattern(
    id: id,
    name: name,
    lengthTicks: lengthTicks,
    lanes: buildLanes(),
  );
}

// Common hi-hat figures (sixteenth grid).
const List<int> _eighths = [0, 2, 4, 6, 8, 10, 12, 14];
const List<int> _sixteenths = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
const List<int> _backbeat = [4, 12];

/// The built-in library, grouped by category in display order.
const List<DrumPreset> drumPresets = [
  // ── Rock ──
  DrumPreset(
    name: 'Four on the Floor',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Basic Rock',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Half-Time Rock',
    category: 'Rock',
    hits: {
      DrumLaneId.kick: [0, 10],
      DrumLaneId.snare: [8],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  // ── Funk ──
  DrumPreset(
    name: 'Funk Groove',
    category: 'Funk',
    hits: {
      DrumLaneId.kick: [0, 6, 10],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Sixteenth Funk',
    category: 'Funk',
    hits: {
      DrumLaneId.kick: [0, 3, 8, 11],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _sixteenths,
    },
  ),
  // ── Pop ──
  DrumPreset(
    name: 'Pop Backbeat',
    category: 'Pop',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Dance Pop',
    category: 'Pop',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.clap: _backbeat,
      DrumLaneId.closedHiHat: [2, 6, 10, 14],
    },
  ),
  // ── Latin ──
  DrumPreset(
    name: 'Bossa Nova',
    category: 'Latin',
    hits: {
      DrumLaneId.kick: [0, 8],
      DrumLaneId.snare: [3, 6, 10, 13],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Samba',
    category: 'Latin',
    hits: {
      DrumLaneId.kick: [0, 4, 8, 12],
      DrumLaneId.snare: [2, 6, 10, 14],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  // ── Hip-Hop ──
  DrumPreset(
    name: 'Boom Bap',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 10],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Trap',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 6],
      DrumLaneId.snare: [8],
      DrumLaneId.closedHiHat: _eighths,
    },
  ),
  DrumPreset(
    name: 'Lo-Fi',
    category: 'Hip-Hop',
    hits: {
      DrumLaneId.kick: [0, 9],
      DrumLaneId.snare: _backbeat,
      DrumLaneId.closedHiHat: [0, 4, 8, 12],
    },
  ),
  // ── Fills ──
  DrumPreset(
    name: 'Snare Roll',
    category: 'Fills',
    hits: {
      DrumLaneId.snare: [8, 10, 12, 13, 14, 15],
    },
  ),
  DrumPreset(
    name: 'Tom Fill',
    category: 'Fills',
    hits: {
      DrumLaneId.highTom: [8, 9],
      DrumLaneId.lowTom: [10, 11],
      DrumLaneId.snare: [12, 13],
      DrumLaneId.crash: [0],
    },
  ),
  DrumPreset(
    name: 'Crash Accent',
    category: 'Fills',
    hits: {
      DrumLaneId.crash: [0],
      DrumLaneId.kick: [0],
    },
  ),
  DrumPreset(
    name: 'Build Up',
    category: 'Fills',
    hits: {
      DrumLaneId.snare: [8, 9, 10, 11, 12, 13, 14, 15],
    },
  ),
];
