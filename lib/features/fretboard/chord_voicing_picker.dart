/// ChordVoicingPicker – two-level chord selector (root → quality) that generates
/// guitar voicings and displays mini chord diagrams in a horizontal scroll.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import '../instrument_shared/chord_picker_parts.dart';
import 'chord_diagram.dart';

const _qualities = [
  ('5', '5th'),
  ('', 'maj'),
  ('m', 'min'),
  ('7', 'dom7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('dim', 'dim'),
  ('aug', 'aug'),
  ('m7b5', 'm7♭5'),
  ('add9', 'add9'),
  ('maj9', 'maj9'),
  ('6', '6'),
  ('m6', 'm6'),
  ('dim7', 'dim7'),
  ('7sus4', '7sus4'),
];

// note normalization and chord data provided by lib/utils/note_utils.dart

// ─── Voicing generation ──────────────────────────────────────────────────────

List<ChordVoicing> _generateVoicings(
  List<String> chordNotes,
  List<int> stringMidis, {
  int capo = 0,
  int limit = 24,
}) {
  final noteSet = chordNotes.toSet();
  if (noteSet.isEmpty) return [];

  // Build per-string option lists using PHYSICAL fret numbers starting from capo.
  final stringOptions = stringMidis.map((openMidi) {
    final opts = <int>[];
    // fret 0 (true open nut) is only valid when there is no capo.
    // The capo position itself acts as the new "open" and is a valid option.
    for (int f = capo; f <= 14; f++) {
      if (noteSet.contains(getPitchClassAtFret(openMidi, f))) opts.add(f);
    }
    return opts;
  }).toList();

  final voicings = <ChordVoicing>[];
  final seen = <String>{};

  // Search windows across physical fret positions, starting from capo.
  for (int base = math.max(1, capo); base <= capo + 12; base++) {
    final windowEnd = base + 3;
    final choices = stringOptions.map((opts) {
      final windowFrets = opts
          .where((f) => f >= base && f <= windowEnd)
          .toList();
      // "Open" means: true open (fret 0) when no capo, or capo position (fret == capo)
      // when a capo is present. In both cases it is already in opts if the note matches.
      final hasOpen = capo == 0 && opts.contains(0);
      final hasCapoOpen = capo > 0 && opts.contains(capo);
      final result = <int?>[null];
      if (hasOpen) result.add(0);
      if (hasCapoOpen) result.add(capo);
      result.addAll(windowFrets.where((f) => f > capo));
      return result;
    }).toList();

    void recurse(int si, List<int?> current) {
      if (si == stringMidis.length) {
        final played = current.whereType<int>().toList();
        if (played.length < 3) return;

        final playedNotes = <String>{};
        for (int i = 0; i < current.length; i++) {
          if (current[i] != null) {
            playedNotes.add(getPitchClassAtFret(stringMidis[i], current[i]!));
          }
        }
        if (!chordNotes.every((n) => playedNotes.contains(n))) return;

        final fretted = played.where((f) => f > 0).toList();
        if (fretted.isNotEmpty) {
          final span =
              fretted.reduce((a, b) => a > b ? a : b) -
              fretted.reduce((a, b) => a < b ? a : b);
          if (span > 3) return;
        }

        final firstPlayed = current.indexWhere((f) => f != null);
        final lastPlayed =
            current.length -
            1 -
            current.reversed.toList().indexWhere((f) => f != null);
        for (int i = firstPlayed + 1; i < lastPlayed; i++) {
          if (current[i] == null) return;
        }

        final key = current.join(',');
        if (seen.contains(key)) return;
        seen.add(key);

        final frettedArr = played.where((f) => f > 0).toList();
        final baseFret = frettedArr.isNotEmpty
            ? frettedArr.reduce((a, b) => a < b ? a : b)
            : 0;

        voicings.add(
          ChordVoicing(positions: List.from(current), baseFret: baseFret),
        );
        return;
      }
      for (final opt in choices[si]) {
        current.add(opt);
        recurse(si + 1, current);
        current.removeLast();
      }
    }

    recurse(0, []);
    if (voicings.length >= limit) break;
  }

  return voicings.take(limit).toList();
}

// ─── Helper: chord notes and detection provided by lib/utils/note_utils.dart ─

// ─── Component ───────────────────────────────────────────────────────────────

class ChordVoicingPicker extends ConsumerStatefulWidget {
  const ChordVoicingPicker({super.key});

  @override
  ConsumerState<ChordVoicingPicker> createState() => _ChordVoicingPickerState();
}

class _ChordVoicingPickerState extends ConsumerState<ChordVoicingPicker>
    with ChordPickerSync {
  String? _selectedRoot;
  String _selectedQuality = '';
  int? _selectedVoicingIdx;

  /// True once the user has explicitly tapped a voicing card.
  /// When false, the picker mirrors the first detected chord automatically.
  bool _voicingCommitted = false;

  @override
  DetectedChord detectFirstChordFromState() =>
      detectFirstChord(ref.read(fretboardProvider).selectedNotes);

  @override
  void applyDetectedChord(DetectedChord chord, {required bool committed}) {
    setState(() {
      _voicingCommitted = committed;
      _selectedRoot = chord?.root;
      _selectedQuality = chord?.quality ?? '';
      _selectedVoicingIdx = null;
    });
  }

  @override
  ({String root, String quality})? get currentActiveChord =>
      _selectedRoot != null
          ? (root: _selectedRoot!, quality: _selectedQuality)
          : null;

  @override
  void initState() {
    super.initState();
    // Seed from detection so the picker is populated on first render.
    final notes = ref.read(fretboardProvider).selectedNotes;
    final detected = detectFirstChord(notes);
    _selectedRoot = detected?.root;
    _selectedQuality = detected?.quality ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);

    installChordSync(fretboardBinding, committed: _voicingCommitted);

    // When the capo moves, transpose the committed chord root by the same
    // delta. When not committed, detection re-runs via selectedNotes listener.
    ref.listen(fretboardProvider.select((s) => s.capo), (prev, next) {
      if (!_voicingCommitted || _selectedRoot == null) return;
      final delta = next - (prev ?? next);
      if (delta == 0) return;
      final idx = chromaticNotes.indexOf(_selectedRoot!);
      if (idx < 0) return;
      setState(() {
        _selectedRoot = chromaticNotes[(idx + delta + 12 * 12) % 12];
        _selectedVoicingIdx = null;
      });
    });

    final tuning = tunings[state.currentTuning]!;
    final stringMidis = tuning.strings.map((s) => s.midiNote).toList();
    final openNotes = stringMidis
        .map((midi) => getPitchClassAtFret(midi, 0))
        .toList();
    final chordName = _selectedRoot != null
        ? '$_selectedRoot$_selectedQuality'
        : null;
    final chordNotes = _selectedRoot != null
        ? getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];

    final voicings = chordNotes.isNotEmpty
        ? _generateVoicings(chordNotes, stringMidis, capo: state.capo)
        : <ChordVoicing>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: ChordPickerHeader(
            title: 'CHORD VOICINGS',
            root: chordNotes.isNotEmpty ? _selectedRoot : null,
            quality: _selectedQuality,
          ),
        ),
        // Root pills
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RootPillRow(
            selectedRoot: _selectedRoot,
            accent: MuzicianTheme.violet,
            onTap: (root) => setState(() {
              _selectedRoot = _selectedRoot == root ? null : root;
              _selectedVoicingIdx = null;
            }),
          ),
        ),
        // Quality pills
        if (_selectedRoot != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: QualityPillRow(
              qualities: _qualities,
              selectedQuality: _selectedQuality,
              accent: MuzicianTheme.violet,
              onTap: (symbol) => setState(() {
                _selectedQuality = symbol;
                _selectedVoicingIdx = null;
              }),
            ),
          ),
        ],
        // Voicings carousel
        if (voicings.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text(
              '${voicings.length} voicing${voicings.length != 1 ? 's' : ''} — tap to apply',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 10,
                letterSpacing: 0.3,
              ),
            ),
          ),
          SizedBox(
            height: 108,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: voicings.length,
              itemBuilder: (_, i) => ChordDiagram(
                voicing: voicings[i],
                rootNote: _selectedRoot,
                openNotes: openNotes,
                isSelected: _selectedVoicingIdx == i,
                onPress: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _voicingCommitted = true;
                    _selectedVoicingIdx = i;
                  });
                  ref.read(fretboardChordCommittedProvider.notifier).state =
                      true;
                  notifier.loadVoicing(voicings[i]);
                  final baseFret = voicings[i].baseFret;
                  if (baseFret > 0) {
                    ref.read(scrollToFretProvider.notifier).state = baseFret;
                  }
                },
              ),
            ),
          ),
        ],
        // Empty states
        if (_selectedRoot != null && chordNotes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'No chord found for "$chordName".',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (chordNotes.isNotEmpty && voicings.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'No voicings found in standard positions.',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (_selectedRoot == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'Select a root note to get started.',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}
