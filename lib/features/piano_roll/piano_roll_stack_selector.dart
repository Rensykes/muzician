/// PianoRollStackSelector – chord root/quality/duration picker to add stacks.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../theme/muzician_theme.dart';

const _roots = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

const _qualities = <(String symbol, String label)>[
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

const _durationOptions = <(String label, int ticks)>[
  ('1/16', 1),
  ('1/8', 2),
  ('1/4', 4),
  ('1/2', 8),
  ('1/1', 16),
];

const _flatToSharp = <String, String>{
  'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#',
};

const _noteToPC = <String, int>{
  'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
  'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11,
};

// Chord intervals for each quality
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

String _toSharp(String note) => _flatToSharp[note] ?? note;

List<String> _chordNotes(String root, String quality) {
  final intervals = _chordIntervals[quality];
  if (intervals == null) return [];
  final rootPc = _noteToPC[root];
  if (rootPc == null) return [];
  return intervals.map((i) {
    final pc = (rootPc + i) % 12;
    return _roots[pc];
  }).toList();
}

int? _bestMidiInRange(String pitchClass, int rangeStart, int rangeEnd, int anchor) {
  final pc = _noteToPC[pitchClass];
  if (pc == null) return null;
  int? best;
  var bestDist = 9999;
  for (var midi = rangeStart; midi <= rangeEnd; midi++) {
    if (((midi % 12) + 12) % 12 != pc) continue;
    final dist = (midi - anchor).abs();
    if (dist < bestDist) {
      best = midi;
      bestDist = dist;
    }
  }
  return best;
}

class PianoRollStackSelector extends ConsumerStatefulWidget {
  const PianoRollStackSelector({super.key});

  @override
  ConsumerState<PianoRollStackSelector> createState() =>
      _PianoRollStackSelectorState();
}

class _PianoRollStackSelectorState
    extends ConsumerState<PianoRollStackSelector> {
  String _root = 'C';
  String _quality = '';
  int _durationTicks = 4;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    final chordSymbol = '$_root$_quality';
    final notes = _chordNotes(_root, _quality);

    void handleAddStack() {
      if (notes.isEmpty) return;
      final maxTicks = rules.totalTicks(
          state.config.timeSignature, state.config.totalMeasures);
      final fallbackStart = min(
        maxTicks - 1,
        state.notes.fold<int>(
            0, (acc, n) => max(acc, n.startTick + n.durationTicks)),
      ).clamp(0, maxTicks - 1);
      final startTick = state.selectedColumnTick ?? fallbackStart;
      final anchor = ((state.pitchRangeStart + state.pitchRangeEnd) / 2).round();
      final midiStack = notes
          .map((pc) => _bestMidiInRange(
              pc, state.pitchRangeStart, state.pitchRangeEnd, anchor))
          .whereType<int>()
          .toList();
      if (midiStack.isEmpty) return;
      notifier.addNoteStack(midiStack, startTick, _durationTicks);
      notifier.selectColumn(startTick);
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
          const Text('Stack Selector',
              style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),

          const SizedBox(height: 10),

          // Root
          const Text('Root',
              style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _roots.map((r) {
                final active = _root == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Pill(
                    label: r,
                    active: active,
                    onTap: () => setState(() => _root = r),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // Quality
          const Text('Quality',
              style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _qualities.map((q) {
                final active = _quality == q.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Pill(
                    label: q.$2,
                    active: active,
                    onTap: () => setState(() => _quality = q.$1),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),

          // Duration
          const Text('Duration',
              style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: _durationOptions.map((d) {
              final active = _durationTicks == d.$2;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: d.$1,
                  active: active,
                  onTap: () => setState(() => _durationTicks = d.$2),
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
                    fontWeight: FontWeight.w600),
              ),
              GestureDetector(
                onTap: handleAddStack,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.emerald.withValues(alpha: 0.18),
                    border: Border.all(
                        color: MuzicianTheme.emerald.withValues(alpha: 0.45),
                        width: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Add Stack',
                      style: TextStyle(
                          color: MuzicianTheme.emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
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

  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
  });

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
            color:
                active ? MuzicianTheme.sky : MuzicianTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
