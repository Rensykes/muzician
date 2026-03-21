/// PianoChordPicker – root/quality picker with simple piano voicings.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';

const _rootNotes = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

const _qualities = [
  ('', 'maj'),
  ('m', 'min'),
  ('7', 'dom7'),
  ('maj7', 'maj7'),
  ('m7', 'm7'),
  ('sus2', 'sus2'),
  ('sus4', 'sus4'),
  ('dim', 'dim'),
  ('aug', 'aug'),
];

const _noteToPc = {
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

const _flatToSharp = {
  'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#',
};

String _toSharp(String n) => _flatToSharp[n] ?? n;

// Chord intervals in semitones
const _chordIntervals = <String, List<int>>{
  '': [0, 4, 7],
  'm': [0, 3, 7],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
};

List<String> _getChordNotes(String root, String quality) {
  final rootIdx = _noteToPc[root];
  if (rootIdx == null) return [];
  final intervals = _chordIntervals[quality];
  if (intervals == null) return [];
  final chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return intervals.map((i) => chromatic[(rootIdx + i) % 12]).toList();
}

List<int> _buildVoicingMidis(List<String> notes, int inversion) {
  const rootBase = 60;
  final rotated = [
    ...notes.sublist(inversion),
    ...notes.sublist(0, inversion),
  ];
  final midis = <int>[];
  int prev = rootBase - 1;
  for (int idx = 0; idx < rotated.length; idx++) {
    final pc = _noteToPc[rotated[idx]];
    if (pc == null) continue;
    int midi = 60 + pc;
    if (idx > 0) {
      while (midi <= prev) midi += 12;
    }
    midis.add(midi);
    prev = midi;
  }
  return midis;
}

class PianoChordPicker extends ConsumerStatefulWidget {
  const PianoChordPicker({super.key});

  @override
  ConsumerState<PianoChordPicker> createState() => _PianoChordPickerState();
}

class _PianoChordPickerState extends ConsumerState<PianoChordPicker> {
  String? _selectedRoot;
  String _selectedQuality = '';

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(pianoProvider.notifier);
    final keys = notifier.getKeys();
    final keyMidis = keys.map((k) => k.midiNote).toSet();

    final chordNotes = _selectedRoot != null
        ? _getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];

    final voicings = <({String label, List<int> midis})>[];
    if (chordNotes.isNotEmpty) {
      for (int inv = 0; inv < 3 && inv < chordNotes.length; inv++) {
        final midis = _buildVoicingMidis(chordNotes, inv)
            .where((m) => keyMidis.contains(m))
            .toList();
        if (midis.length >= 3) {
          voicings.add((
            label: inv == 0 ? 'Root' : '$inv inv',
            midis: midis,
          ));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chord Voicings',
              style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // Root pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _rootNotes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final root = _rootNotes[i];
                final active = _selectedRoot == root;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _selectedRoot = _selectedRoot == root ? null : root;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: active
                          ? MuzicianTheme.emerald.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.emerald.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    child: Text(root,
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.emerald
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Quality pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _qualities.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (symbol, label) = _qualities[i];
                final active = _selectedQuality == symbol;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedQuality = symbol);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: active
                          ? MuzicianTheme.emerald.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: active
                            ? MuzicianTheme.emerald.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.14),
                        width: 0.5,
                      ),
                    ),
                    child: Text(label,
                        style: TextStyle(
                          color: active
                              ? MuzicianTheme.emerald
                              : const Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                );
              },
            ),
          ),
          // Voicings
          if (voicings.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: voicings.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = voicings[i];
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      notifier.loadExactMidis(v.midis);
                      notifier.setHighlightedNotes([]);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 110),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.label,
                              style: const TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(chordNotes.join(' '),
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
