/// ChordVoicingPicker – two-level chord selector (root → quality) that generates
/// guitar voicings and displays mini chord diagrams in a horizontal scroll.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import 'chord_diagram.dart';

const _rootNotes = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

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
];

const _flatToSharp = {
  'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#',
};

String _toSharp(String note) => _flatToSharp[note] ?? note;

// ─── Voicing generation ──────────────────────────────────────────────────────

List<ChordVoicing> _generateVoicings(
  List<String> chordNotes,
  List<int> stringMidis, {
  int limit = 24,
}) {
  final noteSet = chordNotes.toSet();
  if (noteSet.isEmpty) return [];

  final stringOptions = stringMidis.map((openMidi) {
    final opts = <int>[];
    for (int f = 0; f <= 14; f++) {
      if (noteSet.contains(getPitchClassAtFret(openMidi, f))) opts.add(f);
    }
    return opts;
  }).toList();

  final voicings = <ChordVoicing>[];
  final seen = <String>{};

  for (int base = 1; base <= 12; base++) {
    final windowEnd = base + 3;
    final choices = stringOptions.map((opts) {
      final windowFrets = opts.where((f) => f >= base && f <= windowEnd).toList();
      final hasOpen = opts.contains(0);
      final result = <int?>[null];
      if (hasOpen) result.add(0);
      result.addAll(windowFrets);
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
          final span = fretted.reduce((a, b) => a > b ? a : b) -
              fretted.reduce((a, b) => a < b ? a : b);
          if (span > 3) return;
        }

        final firstPlayed = current.indexWhere((f) => f != null);
        final lastPlayed =
            current.length - 1 - current.reversed.toList().indexWhere((f) => f != null);
        for (int i = firstPlayed + 1; i < lastPlayed; i++) {
          if (current[i] == null) return;
        }

        final key = current.join(',');
        if (seen.contains(key)) return;
        seen.add(key);

        final frettedArr = played.where((f) => f > 0).toList();
        final baseFret =
            frettedArr.isNotEmpty ? frettedArr.reduce((a, b) => a < b ? a : b) : 0;

        voicings.add(ChordVoicing(positions: List.from(current), baseFret: baseFret));
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

// ─── Helper: get chord notes using semitone intervals ────────────────────────

const _chordIntervals = <String, List<int>>{
  '': [0, 4, 7],
  'm': [0, 3, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
  '5': [0, 7],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'm7b5': [0, 3, 6, 10],
  'add9': [0, 4, 7, 14],
  'maj9': [0, 4, 7, 11, 14],
};

List<String> _getChordNotes(String root, String quality) {
  final intervals = _chordIntervals[quality];
  if (intervals == null) return [];
  final rootIdx = _rootNotes.indexOf(root);
  if (rootIdx < 0) return [];
  return intervals.map((i) => _rootNotes[(rootIdx + i) % 12]).toList();
}

// ─── Component ───────────────────────────────────────────────────────────────

class ChordVoicingPicker extends ConsumerStatefulWidget {
  const ChordVoicingPicker({super.key});

  @override
  ConsumerState<ChordVoicingPicker> createState() => _ChordVoicingPickerState();
}

class _ChordVoicingPickerState extends ConsumerState<ChordVoicingPicker> {
  String? _selectedRoot;
  String _selectedQuality = '';
  int? _selectedVoicingIdx;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final tuning = tunings[state.currentTuning]!;
    final pendingChord = ref.watch(pendingChordProvider);

    // Sync from detection panel
    if (pendingChord != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedRoot = pendingChord.root;
          _selectedQuality = pendingChord.quality;
          _selectedVoicingIdx = null;
        });
        ref.read(pendingChordProvider.notifier).state = null;
      });
    }

    final stringMidis =
        tuning.strings.map((s) => s.midiNote + state.capo).toList();
    final openNotes =
        stringMidis.map((midi) => getPitchClassAtFret(midi, 0)).toList();
    final chordName =
        _selectedRoot != null ? '$_selectedRoot$_selectedQuality' : null;
    final chordNotes = _selectedRoot != null
        ? _getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];
    final voicings = chordNotes.isNotEmpty
        ? _generateVoicings(chordNotes, stringMidis)
        : <ChordVoicing>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              const Text(
                'CHORD VOICINGS',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (chordName != null && chordNotes.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.sky.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    chordName,
                    style: const TextStyle(
                      color: MuzicianTheme.sky,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Root pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _rootNotes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final root = _rootNotes[i];
              final active = _selectedRoot == root;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedRoot = _selectedRoot == root ? null : root;
                    _selectedVoicingIdx = null;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: active
                          ? MuzicianTheme.sky.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    root,
                    style: TextStyle(
                      color: active ? MuzicianTheme.sky : const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Quality pills
        if (_selectedRoot != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _qualities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final (symbol, label) = _qualities[i];
                final active = _selectedQuality == symbol;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedQuality = symbol;
                      _selectedVoicingIdx = null;
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: active
                          ? const Color(0x337C3AED)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? const Color(0x807C3AED)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.violet
                            : const Color(0xFF475569),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
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
                  setState(() => _selectedVoicingIdx = i);
                  notifier.loadVoicing(voicings[i]);
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
