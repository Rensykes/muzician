/// NoteDetectionPanel – displays tapped pitch classes and detects matching
/// chords and scales using music_notes. Includes a "Clear" action.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';

({String root, String quality})? _parseChordString(String chordStr) {
  if (chordStr.isEmpty) return null;
  String root;
  String quality;
  if (chordStr.length > 1 && chordStr[1] == '#') {
    root = chordStr.substring(0, 2);
    quality = chordStr.substring(2);
  } else {
    root = chordStr.substring(0, 1);
    quality = chordStr.substring(1);
  }
  return (root: toSharp(root), quality: quality);
}

({String root, String scaleName})? _parseScaleString(String scaleStr) {
  final parts = scaleStr.split(' ');
  if (parts.length < 2) return null;
  final root = toSharp(parts[0]);
  final scaleName = parts.sublist(1).join(' ');
  return (root: root, scaleName: scaleName);
}

class NoteDetectionPanel extends ConsumerStatefulWidget {
  const NoteDetectionPanel({super.key});

  @override
  ConsumerState<NoteDetectionPanel> createState() =>
      _NoteDetectionPanelState();
}

class _NoteDetectionPanelState extends ConsumerState<NoteDetectionPanel> {
  String? _activeScaleChip;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);

    ref.listen(fretboardProvider.select((s) => s.highlightedNotes), (
      _,
      next,
    ) {
      if (next.isEmpty && _activeScaleChip != null) {
        setState(() => _activeScaleChip = null);
      }
    });

    if (state.selectedNotes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 14,
              color: MuzicianTheme.textDim,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tap notes on the fretboard to detect chords & scales.',
                style: TextStyle(
                  color: MuzicianTheme.textDim,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final detection = detectChordsAndScales(state.selectedNotes);
    final hasResults =
        detection.chords.isNotEmpty || detection.scales.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Text(
                'DETECTION',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => notifier.clearSelectedNotes(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Selected notes chips
          Row(
            children: [
              const Text(
                'Notes',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'tap to focus',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: state.selectedNotes.map((note) {
                final isFocused = state.focusedNotes.contains(note);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    notifier.toggleFocusedNote(note);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: isFocused
                          ? MuzicianTheme.sky
                          : MuzicianTheme.sky.withValues(alpha: 0.15),
                      border: Border.all(
                        color: MuzicianTheme.sky.withValues(alpha: 0.65),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: isFocused ? Colors.white : MuzicianTheme.sky,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          // Results
          if (state.selectedNotes.length < 2)
            const Text(
              'Tap at least 2 notes to detect.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (hasResults) ...[
            if (detection.chords.isNotEmpty) ...[
              Row(
                children: [
                  const Text(
                    'Chords',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'tap to select voicing',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: detection.chords.map((c) {
                    return GestureDetector(
                      onTap: () {
                        final parsed = _parseChordString(c);
                        if (parsed == null) return;
                        HapticFeedback.lightImpact();
                        ref.read(pendingChordProvider.notifier).state = (
                          root: parsed.root,
                          quality: parsed.quality,
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0x1FC084FC),
                          border: Border.all(
                            color: const Color(0x66C084FC),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          c,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            if (detection.scales.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Scales',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'tap to highlight',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: detection.scales.map((s) {
                    final isActive = _activeScaleChip == s;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _tryApplyScale(s);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isActive
                              ? MuzicianTheme.emerald
                              : MuzicianTheme.emerald.withValues(alpha: 0.10),
                          border: Border.all(
                            color: MuzicianTheme.emerald.withValues(
                              alpha: isActive ? 1.0 : 0.35,
                            ),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : const Color(0xFFE2E8F0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ] else
            const Text(
              'No exact match — try adding more notes.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _tryApplyScale(String displayString) async {
    if (_activeScaleChip == displayString) {
      setState(() => _activeScaleChip = null);
      ref.read(fretboardProvider.notifier).setHighlightedNotes([]);
      return;
    }
    final parsed = _parseScaleString(displayString);
    if (parsed == null) return;
    final scaleNotes = getScaleNotes(parsed.root, parsed.scaleName);
    if (scaleNotes.isEmpty) return;
    final conflicts = ref
        .read(fretboardProvider)
        .selectedNotes
        .where((n) => !scaleNotes.contains(n))
        .toList();
    if (conflicts.isEmpty) {
      setState(() => _activeScaleChip = displayString);
      ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
      ref.read(pendingScaleProvider.notifier).state =
          (root: parsed.root, scaleName: parsed.scaleName);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed == true) {
      ref.read(fretboardProvider.notifier).removeNotesByPitchClass(conflicts);
      setState(() => _activeScaleChip = displayString);
      ref.read(fretboardProvider.notifier).setHighlightedNotes(scaleNotes);
      ref.read(pendingScaleProvider.notifier).state =
          (root: parsed.root, scaleName: parsed.scaleName);
    }
  }
}
