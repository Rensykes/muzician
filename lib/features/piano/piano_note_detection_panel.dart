/// PianoNoteDetectionPanel – detects chords/scales from selected piano keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/scale_conflict_dialog.dart';
import '../../utils/note_utils.dart';

class PianoNoteDetectionPanel extends ConsumerStatefulWidget {
  final VoidCallback? onChordPanelRequested;

  const PianoNoteDetectionPanel({super.key, this.onChordPanelRequested});

  @override
  ConsumerState<PianoNoteDetectionPanel> createState() =>
      _PianoNoteDetectionPanelState();
}

class _PianoNoteDetectionPanelState
    extends ConsumerState<PianoNoteDetectionPanel> {
  String? _activeScaleChip;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);

    ref.listen(pianoProvider.select((s) => s.highlightedNotes), (_, next) {
      if (next.isEmpty && _activeScaleChip != null) {
        setState(() => _activeScaleChip = null);
      }
    });

    final hasNotes = state.selectedNotes.isNotEmpty;
    List<ChordDetectionResult> chordResults = const [];
    List<ScaleDetectionResult> scaleResults = const [];

    if (state.selectedNotes.length >= 2 && state.selectedKeys.isNotEmpty) {
      final exactNotes = state.selectedKeys.map((key) {
        return ExactSelectionNote(
          midiNote: key.midiNote,
          pitchClass: key.noteName,
        );
      }).toList();
      chordResults = detectChordResultsFromExactNotes(exactNotes);
      scaleResults = detectScaleResultsFromExactNotes(exactNotes);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0, -0.12),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: hasNotes
          ? Padding(
              key: const ValueKey(true),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  // Notes chips
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
                                color: MuzicianTheme.sky.withValues(
                                  alpha: 0.65,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              note,
                              style: TextStyle(
                                color: isFocused
                                    ? Colors.white
                                    : MuzicianTheme.sky,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (state.selectedNotes.length < 2)
                    const Text(
                      'Tap at least 2 notes to detect.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else ...[
                    if (chordResults.isNotEmpty) ...[
                      Row(
                        children: [
                          const Text(
                            'Chords',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
                          children: chordResults
                              .map(
                                (result) => GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    ref
                                            .read(
                                              pianoPendingChordProvider
                                                  .notifier,
                                            )
                                            .state =
                                        (
                                          root: result.root,
                                          quality: result.quality,
                                        );
                                    ref
                                            .read(
                                              pianoActiveChordProvider.notifier,
                                            )
                                            .state =
                                        (
                                          root: result.root,
                                          quality: result.quality,
                                        );
                                    widget.onChordPanelRequested?.call();
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      color: MuzicianTheme.emerald.withValues(
                                        alpha: 0.12,
                                      ),
                                      border: Border.all(
                                        color: MuzicianTheme.emerald.withValues(
                                          alpha: 0.45,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      formatChordSymbol(result),
                                      style: const TextStyle(
                                        color: Color(0xFFE2E8F0),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                    if (scaleResults.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text(
                            'Scales',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
                          children: scaleResults.map((result) {
                            final chipKey =
                                '${result.root} ${result.scaleName}';
                            final isActive = _activeScaleChip == chipKey;
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _tryApplyScale(
                                    result.root, result.scaleName);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: isActive
                                      ? MuzicianTheme.emerald
                                      : MuzicianTheme.emerald.withValues(
                                          alpha: 0.12,
                                        ),
                                  border: Border.all(
                                    color: MuzicianTheme.emerald.withValues(
                                      alpha: isActive ? 1.0 : 0.45,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  formatScaleLabel(result),
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
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(key: ValueKey(false)),
    );
  }

  Future<void> _tryApplyScale(String root, String scaleName) async {
    final chipKey = '$root $scaleName';
    if (_activeScaleChip == chipKey) {
      setState(() => _activeScaleChip = null);
      ref.read(pianoProvider.notifier).setHighlightedNotes([]);
      ref.read(pianoActiveScaleProvider.notifier).state = null;
      return;
    }
    final scaleNotes = getScaleNotes(root, scaleName);
    if (scaleNotes.isEmpty) return;
    final conflicts = ref
        .read(pianoProvider)
        .selectedNotes
        .where((n) => !scaleNotes.contains(n))
        .toList();
    if (conflicts.isEmpty) {
      setState(() => _activeScaleChip = chipKey);
      ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);
      ref.read(pianoPendingScaleProvider.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      ref.read(pianoActiveScaleProvider.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScaleConflictDialog(conflictingNotes: conflicts),
    );
    if (confirmed == true) {
      ref.read(pianoProvider.notifier).removeNotesByPitchClass(conflicts);
      setState(() => _activeScaleChip = chipKey);
      ref.read(pianoProvider.notifier).setHighlightedNotes(scaleNotes);
      ref.read(pianoPendingScaleProvider.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
      ref.read(pianoActiveScaleProvider.notifier).state = (
        root: root,
        scaleName: scaleName,
      );
    }
  }
}
