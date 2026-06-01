/// PianoChordPicker – root/quality picker with simple piano voicings.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import '../instrument_shared/chord_picker_parts.dart';

/// Qualities shown in the piano chord picker UI (subset of [chordIntervals]).
const _pianoQualities = [
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

/// Symbols for the chord types the piano picker supports.
const _pianoQualitySymbols = [
  '5',
  '',
  'm',
  '7',
  'maj7',
  'm7',
  'sus2',
  'sus4',
  'dim',
  'aug',
  'm7b5',
  'add9',
  'maj9',
  '6',
  'm6',
  'dim7',
  '7sus4',
];

List<int> _buildVoicingMidis(
  List<String> notes,
  int inversion,
  int octaveOffset,
) {
  final rootBase = 60 + octaveOffset * 12;
  final rotated = [...notes.sublist(inversion), ...notes.sublist(0, inversion)];
  final midis = <int>[];
  int prev = rootBase - 1;
  for (int idx = 0; idx < rotated.length; idx++) {
    final pc = noteToPC[rotated[idx]];
    if (pc == null) continue;
    // Start one octave below rootBase so the while-loop lands in the right
    // octave for both positive and negative octave offsets.
    int midi = rootBase - 12 + pc;
    while (midi <= prev) {
      midi += 12;
    }
    midis.add(midi);
    prev = midi;
  }
  return midis;
}

/// Returns the first chord in [_pianoQualities] whose tones exactly match
/// [notes], or null when no chord matches or notes has fewer than 2 members.
({String root, String quality})? _detectFirstChordForPiano(
  List<String> notes,
) => detectFirstChord(notes, qualitySymbols: _pianoQualitySymbols);

class PianoChordPicker extends ConsumerStatefulWidget {
  const PianoChordPicker({super.key});

  @override
  ConsumerState<PianoChordPicker> createState() => _PianoChordPickerState();
}

class _PianoChordPickerState extends ConsumerState<PianoChordPicker>
    with ChordPickerSync {
  String? _selectedRoot;
  String _selectedQuality = '';
  int _octaveOffset = 0;
  int? _selectedVoicingIdx;

  /// True once the user has explicitly tapped a voicing card.
  /// When false the picker mirrors the first detected chord automatically.
  bool _voicingCommitted = false;

  static const _minOctaveOffset = -3;
  static const _maxOctaveOffset = 3;

  @override
  DetectedChord detectFirstChordFromState() =>
      _detectFirstChordForPiano(ref.read(pianoProvider).selectedNotes);

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
  bool get isChordCommitted => _voicingCommitted;

  @override
  void initState() {
    super.initState();
    final notes = ref.read(pianoProvider).selectedNotes;
    final detected = _detectFirstChordForPiano(notes);
    _selectedRoot = detected?.root;
    _selectedQuality = detected?.quality ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(pianoProvider.notifier);
    final keyMidis = notifier.getKeys().map((k) => k.midiNote).toSet();

    installChordSync(pianoBinding);

    final chordNotes = _selectedRoot != null
        ? getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];

    final voicings = <({String label, List<int> midis})>[];
    if (chordNotes.isNotEmpty) {
      for (int inv = 0; inv < 3 && inv < chordNotes.length; inv++) {
        final midis = _buildVoicingMidis(
          chordNotes,
          inv,
          _octaveOffset,
        ).where((m) => keyMidis.contains(m)).toList();
        if (midis.length >= 3) {
          voicings.add((label: inv == 0 ? 'Root' : '$inv inv', midis: midis));
        }
      }
    }

    final octaveLabel = (4 + _octaveOffset).toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with active chord badge
          ChordPickerHeader(
            title: 'Chord Voicings',
            root: _selectedRoot,
            quality: _selectedQuality,
          ),
          const SizedBox(height: 10),
          // Root pills
          RootPillRow(
            selectedRoot: _selectedRoot,
            accent: MuzicianTheme.violet,
            onTap: (root) => setState(() {
              _selectedRoot = _selectedRoot == root ? null : root;
              _selectedVoicingIdx = null;
            }),
          ),
          const SizedBox(height: 10),
          // Quality pills
          QualityPillRow(
            qualities: _pianoQualities,
            selectedQuality: _selectedQuality,
            accent: MuzicianTheme.violet,
            onTap: (symbol) => setState(() {
              _selectedQuality = symbol;
              _selectedVoicingIdx = null;
            }),
          ),
          const SizedBox(height: 10),
          // Octave selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Octave',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(width: 10),
              _OctaveButton(
                icon: Icons.remove,
                enabled: _octaveOffset > _minOctaveOffset,
                onTap: () => setState(
                  () => _octaveOffset = math.max(
                    _minOctaveOffset,
                    _octaveOffset - 1,
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  octaveLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _OctaveButton(
                icon: Icons.add,
                enabled: _octaveOffset < _maxOctaveOffset,
                onTap: () => setState(
                  () => _octaveOffset = math.min(
                    _maxOctaveOffset,
                    _octaveOffset + 1,
                  ),
                ),
              ),
            ],
          ),
          // Voicings
          if (voicings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: voicings.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = voicings[i];
                  final isSelected = _selectedVoicingIdx == i;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _voicingCommitted = true;
                        _selectedVoicingIdx = i;
                      });
                      ref.read(pianoChordCommittedProvider.notifier).state =
                          true;
                      notifier.loadExactMidis(v.midis);
                      if (v.midis.isNotEmpty) {
                        ref.read(pianoScrollToMidiProvider.notifier).state = v
                            .midis
                            .reduce(math.min);
                      }
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 110),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected
                            ? MuzicianTheme.emerald.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: isSelected
                              ? MuzicianTheme.emerald.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.14),
                          width: isSelected ? 1.0 : 0.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.label,
                            style: TextStyle(
                              color: isSelected
                                  ? MuzicianTheme.emerald
                                  : const Color(0xFFE2E8F0),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chordNotes.join(' '),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
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

// ─── Octave Button ────────────────────────────────────────────────────────────

class _OctaveButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _OctaveButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: enabled
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.02),
          border: Border.all(
            color: enabled
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
        ),
      ),
    );
  }
}
