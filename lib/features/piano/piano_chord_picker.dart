/// PianoChordPicker – root/quality picker with simple piano voicings.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';

/// Qualities shown in the piano chord picker UI (subset of [chordIntervals]).
const _pianoQualities = [
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

/// Symbols for the 9 chord types the piano picker supports.
const _pianoQualitySymbols = [
  '',
  'm',
  '7',
  'maj7',
  'm7',
  'sus2',
  'sus4',
  'dim',
  'aug',
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
({String root, String quality})? _detectFirstChordForPiano(List<String> notes) =>
    detectFirstChord(notes, qualitySymbols: _pianoQualitySymbols);

class PianoChordPicker extends ConsumerStatefulWidget {
  const PianoChordPicker({super.key});

  @override
  ConsumerState<PianoChordPicker> createState() => _PianoChordPickerState();
}

class _PianoChordPickerState extends ConsumerState<PianoChordPicker> {
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

    // Live-sync root/quality from first detected chord while not committed.
    ref.listen(pianoProvider.select((s) => s.selectedNotes), (_, notes) {
      if (_voicingCommitted) return;
      final detected = _detectFirstChordForPiano(notes);
      setState(() {
        _selectedRoot = detected?.root;
        _selectedQuality = detected?.quality ?? '';
        _selectedVoicingIdx = null;
      });
    });

    // When the user manually taps a key, drop the commit and revert to detection.
    ref.listen(pianoManualEditProvider, (_, _) {
      final detected = _detectFirstChordForPiano(
        ref.read(pianoProvider).selectedNotes,
      );
      setState(() {
        _voicingCommitted = false;
        _selectedRoot = detected?.root;
        _selectedQuality = detected?.quality ?? '';
        _selectedVoicingIdx = null;
      });
      ref.read(pianoChordCommittedProvider.notifier).state = false;
    });

    // Sync when the user taps a chord chip in the detection panel.
    final pendingChord = ref.watch(pianoPendingChordProvider);
    if (pendingChord != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _voicingCommitted = true;
          _selectedRoot = pendingChord.root;
          _selectedQuality = pendingChord.quality;
          _selectedVoicingIdx = null;
        });
        ref.read(pianoChordCommittedProvider.notifier).state = true;
        ref.read(pianoPendingChordProvider.notifier).state = null;
      });
    }

    final chordNotes = _selectedRoot != null
        ? getChordNotes(_selectedRoot!, _selectedQuality)
        : <String>[];

    final voicings = <({String label, List<int> midis})>[];
    if (chordNotes.isNotEmpty) {
      for (int inv = 0; inv < 3 && inv < chordNotes.length; inv++) {
        final midis = _buildVoicingMidis(chordNotes, inv, _octaveOffset)
            .where((m) => keyMidis.contains(m))
            .toList();
        if (midis.length >= 3) {
          voicings.add((label: inv == 0 ? 'Root' : '$inv inv', midis: midis));
        }
      }
    }

    final octaveLabel = (4 + _octaveOffset).toString();
    final chordName = _selectedRoot != null
        ? '$_selectedRoot$_selectedQuality'
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with active chord badge
          Row(
            children: [
              const Text(
                'Chord Voicings',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (chordName != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    chordName,
                    style: const TextStyle(
                      color: MuzicianTheme.emerald,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Root pills
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chromaticNotes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final root = chromaticNotes[i];
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                    child: Text(
                      root,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.emerald
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
              itemCount: _pianoQualities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (symbol, label) = _pianoQualities[i];
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? MuzicianTheme.emerald
                            : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
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
                  () => _octaveOffset =
                      math.max(_minOctaveOffset, _octaveOffset - 1),
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
                  () => _octaveOffset =
                      math.min(_maxOctaveOffset, _octaveOffset + 1),
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
                        ref.read(pianoScrollToMidiProvider.notifier).state =
                            v.midis.reduce(math.min);
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
          color: enabled
              ? const Color(0xFFE2E8F0)
              : const Color(0xFF475569),
        ),
      ),
    );
  }
}
