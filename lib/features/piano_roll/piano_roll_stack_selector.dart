/// PianoRollStackSelector – chord root/quality/duration picker to add stacks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_roll_composer_store.dart';
import '../../utils/note_utils.dart';
import '../../theme/muzician_theme.dart';

const _roots = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

const _qualities = <(String symbol, String label)>[
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

const _durationOptions = <(String label, int ticks)>[
  ('1/16', 1),
  ('1/8', 2),
  ('1/4', 4),
  ('1/2', 8),
  ('1/1', 16),
];

class PianoRollStackSelector extends ConsumerWidget {
  const PianoRollStackSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composerState = ref.watch(pianoRollComposerProvider);
    final composerNotifier = ref.read(pianoRollComposerProvider.notifier);

    final chordSymbol = '${composerState.root}${composerState.quality}';
    final notes = getChordNotes(composerState.root, composerState.quality);

    void handleAddStack() {
      composerNotifier.addStack();
      HapticFeedback.mediumImpact();
    }

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
          const Text(
            'Stack Selector',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 10),

          // Root
          const Text(
            'Root',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _roots.map((r) {
                final active = composerState.root == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Pill(
                    label: r,
                    active: active,
                    onTap: () => composerNotifier.setRoot(r),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // Quality
          const Text(
            'Quality',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _qualities.map((q) {
                final active = composerState.quality == q.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Pill(
                    label: q.$2,
                    active: active,
                    onTap: () => composerNotifier.setQuality(q.$1),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // Duration
          const Text(
            'Duration',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: _durationOptions.map((d) {
              final active = composerState.durationTicks == d.$2;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: d.$1,
                  active: active,
                  onTap: () => composerNotifier.setDuration(d.$2),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 10),

          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$chordSymbol: ${notes.join(' ').isEmpty ? 'no notes' : notes.join(' ')}',
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              GestureDetector(
                onTap: handleAddStack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.emerald.withValues(alpha: 0.18),
                    border: Border.all(
                      color: MuzicianTheme.emerald.withValues(alpha: 0.45),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Add Stack',
                    style: TextStyle(
                      color: MuzicianTheme.emerald,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: active
                ? MuzicianTheme.sky.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.16),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.sky : MuzicianTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
