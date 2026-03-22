/// PianoRollDetectionPanel – shows detected chords/scales at selected column tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../theme/muzician_theme.dart';

const _chromatic = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

({List<String> chords, List<String> scales}) _detect(List<String> pitchClasses) {
  if (pitchClasses.length < 2) return (chords: <String>[], scales: <String>[]);
  final noteSet = pitchClasses.toSet();

  final chords = <String>[];
  const qualities = [
    ('', [0, 4, 7]),
    ('m', [0, 3, 7]),
    ('7', [0, 4, 7, 10]),
    ('maj7', [0, 4, 7, 11]),
    ('m7', [0, 3, 7, 10]),
    ('dim', [0, 3, 6]),
    ('aug', [0, 4, 8]),
    ('sus2', [0, 2, 7]),
    ('sus4', [0, 5, 7]),
  ];
  for (final root in _chromatic) {
    final rootIdx = _chromatic.indexOf(root);
    for (final (symbol, intervals) in qualities) {
      final chordTones =
          intervals.map((i) => _chromatic[(rootIdx + i) % 12]).toSet();
      if (noteSet.every(chordTones.contains) &&
          chordTones.every(noteSet.contains)) {
        chords.add('$root${symbol.isEmpty ? '' : symbol}');
      }
    }
  }

  final scales = <String>[];
  const scaleTypes = [
    ('major', [0, 2, 4, 5, 7, 9, 11]),
    ('minor', [0, 2, 3, 5, 7, 8, 10]),
    ('major pentatonic', [0, 2, 4, 7, 9]),
    ('minor pentatonic', [0, 3, 5, 7, 10]),
  ];
  for (final root in _chromatic) {
    final rootIdx = _chromatic.indexOf(root);
    for (final (name, intervals) in scaleTypes) {
      final scaleTones =
          intervals.map((i) => _chromatic[(rootIdx + i) % 12]).toSet();
      if (noteSet.every(scaleTones.contains)) {
        scales.add('$root $name');
      }
    }
  }
  return (chords: chords.take(8).toList(), scales: scales.take(8).toList());
}

class PianoRollDetectionPanel extends ConsumerWidget {
  const PianoRollDetectionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    if (state.selectedColumnTick == null) return const SizedBox.shrink();

    final notesAtTick =
        rules.getNotesAtTick(state.notes, state.selectedColumnTick!);
    if (notesAtTick.isEmpty) return const SizedBox.shrink();

    final uniquePCs = notesAtTick.map((n) => n.pitchClass).toSet().toList();
    final detection = _detect(uniquePCs);

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
              final isSelected = state.selectedNoteId == note.id;
              return GestureDetector(
                onTap: () {
                  notifier.selectNote(isSelected ? null : note.id);
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  padding:
                      const EdgeInsets.only(left: 8, top: 3, bottom: 3, right: 4),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          if (state.selectedNoteId != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                notifier.removeNote(state.selectedNoteId!);
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
