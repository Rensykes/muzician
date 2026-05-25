/// PianoRollDetectionPanel – shows detected chords/scales at selected column tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/harmonic_analysis.dart';
import '../../models/piano_roll.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../utils/note_utils.dart';
import '../../theme/muzician_theme.dart';

({List<String> chords, List<String> scales}) _detect(
  List<PianoRollNote> notes,
) {
  if (notes.length < 2) return (chords: <String>[], scales: <String>[]);

  final exactNotes = notes
      .map(
        (n) =>
            ExactSelectionNote(midiNote: n.midiNote, pitchClass: n.pitchClass),
      )
      .toList();

  final chordResults = detectChordResultsFromExactNotes(exactNotes);
  final scaleResults = detectScaleResultsFromExactNotes(exactNotes);

  return (
    chords: chordResults.take(8).map(formatChordSymbol).toList(),
    scales: scaleResults.take(8).map(formatScaleLabel).toList(),
  );
}

class PianoRollDetectionPanel extends ConsumerWidget {
  const PianoRollDetectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    if (state.selectedColumnTick == null) return const SizedBox.shrink();

    final notesAtTick = rules.getNotesAtTick(
      state.notes,
      state.selectedColumnTick!,
    );
    if (notesAtTick.isEmpty) return const SizedBox.shrink();

    final detection = _detect(notesAtTick);

    return Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        border: Border.all(color: MuzicianTheme.glassBorder, width: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Stack at beat ${state.selectedColumnTick! + 1}',
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${notesAtTick.length} note${notesAtTick.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Note chips – tap to select, ×-button to delete
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: notesAtTick.map((note) {
              final isSelected = state.selectedNoteIds.contains(note.id);
              return GestureDetector(
                onTap: () {
                  notifier.selectNote(isSelected ? null : note.id);
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 8,
                    top: 3,
                    bottom: 3,
                    right: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? MuzicianTheme.sky.withValues(alpha: 0.25)
                        : MuzicianTheme.sky.withValues(alpha: 0.12),
                    border: Border.all(
                      color: isSelected
                          ? MuzicianTheme.sky
                          : MuzicianTheme.sky.withValues(alpha: 0.35),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        note.noteWithOctave,
                        style: TextStyle(
                          color: isSelected
                              ? MuzicianTheme.sky
                              : MuzicianTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          notifier.removeNote(note.id);
                          HapticFeedback.lightImpact();
                        },
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: isSelected
                              ? MuzicianTheme.sky
                              : MuzicianTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // Chords
          if (detection.chords.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Chords',
              style: TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: detection.chords.map((chord) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.emerald.withValues(alpha: 0.15),
                    border: Border.all(
                      color: MuzicianTheme.emerald.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chord,
                    style: const TextStyle(
                      color: MuzicianTheme.emerald,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Scales
          if (detection.scales.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Scales',
              style: TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: detection.scales.map((scale) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.violet.withValues(alpha: 0.15),
                    border: Border.all(
                      color: MuzicianTheme.violet.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    scale,
                    style: const TextStyle(
                      color: MuzicianTheme.violet,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Delete selected note button
          if (state.selectedNoteIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                for (final id in state.selectedNoteIds) {
                  notifier.removeNote(id);
                }
                HapticFeedback.lightImpact();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MuzicianTheme.red.withValues(alpha: 0.15),
                  border: Border.all(
                    color: MuzicianTheme.red.withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Delete Selected Note',
                  style: TextStyle(
                    color: MuzicianTheme.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
