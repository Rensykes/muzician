/// PianoRollToolbar – tempo, measures, time signature, key, pitch window controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../theme/muzician_theme.dart';

const _timeSigOptions = <(int beats, int unit, String label)>[
  (4, 4, '4/4'),
  (3, 4, '3/4'),
  (2, 4, '2/4'),
  (5, 4, '5/4'),
  (6, 8, '6/8'),
];

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

const _snapOptions = <(int ticks, String label)>[
  (1, 'Free'),
  (2, '1/8'),
  (4, '1/4'),
  (8, '1/2'),
];

class PianoRollToolbar extends ConsumerStatefulWidget {
  const PianoRollToolbar({super.key});

  @override
  ConsumerState<PianoRollToolbar> createState() => _PianoRollToolbarState();
}

class _PianoRollToolbarState extends ConsumerState<PianoRollToolbar> {
  String _keyMode = 'major';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    final ts = state.config.timeSignature;
    final activeTimeSig =
        _timeSigOptions
            .where((o) => o.$1 == ts.beatsPerMeasure && o.$2 == ts.beatUnit)
            .firstOrNull
            ?.$3 ??
        '${ts.beatsPerMeasure}/${ts.beatUnit}';

    final totalRollTicks = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );

    void pickKey(String root) {
      final value = '$root $_keyMode';
      notifier.setKey(state.config.key == value ? null : value);
      HapticFeedback.lightImpact();
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
          // ── Tempo + Measures ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Tempo',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _Stepper(
                value: '${state.config.tempo} BPM',
                onDecrement: () => notifier.setTempo(state.config.tempo - 1),
                onIncrement: () => notifier.setTempo(state.config.tempo + 1),
              ),
              const Text(
                'Measures',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _Stepper(
                value: '${state.config.totalMeasures}',
                onDecrement: () =>
                    notifier.setTotalMeasures(state.config.totalMeasures - 1),
                onIncrement: () =>
                    notifier.setTotalMeasures(state.config.totalMeasures + 1),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Info ──
          Wrap(
            spacing: 12,
            children: [
              Text(
                'Tick Grid: 1/16',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Timeline: $totalRollTicks ticks',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Range: ${state.pitchRangeStart} to ${state.pitchRangeEnd}',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Tool ──
          Row(
            children: [
              const Text(
                'Tool',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              _Pill(
                label: 'Draw',
                active: state.activeTool == PianoRollTool.draw,
                onTap: () => notifier.setActiveTool(PianoRollTool.draw),
              ),
              const SizedBox(width: 8),
              _Pill(
                label: '✂ Scissors',
                active: state.activeTool == PianoRollTool.scissors,
                onTap: () {
                  notifier.setActiveTool(PianoRollTool.scissors);
                  HapticFeedback.lightImpact();
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Snap ──
          const Text(
            'Snap',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _snapOptions.map((o) {
              return _Pill(
                label: o.$2,
                active: state.snapTicks == o.$1,
                onTap: () => notifier.setSnapTicks(o.$1),
              );
            }).toList(),
          ),

          const SizedBox(height: 10),

          // ── Time Signature ──
          const Text(
            'Time Signature',
            style: TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _timeSigOptions.map((o) {
              final active = activeTimeSig == o.$3;
              return _Pill(
                label: o.$3,
                active: active,
                onTap: () => notifier.setTimeSignature(
                  TimeSignature(beatsPerMeasure: o.$1, beatUnit: o.$2),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 10),

          // ── Key ──
          Row(
            children: [
              const Text(
                'Key (Optional)',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _ModeBtn(
                label: 'Major',
                active: _keyMode == 'major',
                onTap: () => setState(() => _keyMode = 'major'),
              ),
              const SizedBox(width: 4),
              _ModeBtn(
                label: 'Minor',
                active: _keyMode == 'minor',
                onTap: () => setState(() => _keyMode = 'minor'),
              ),
              const SizedBox(width: 4),
              _ModeBtn(
                label: 'None',
                active: false,
                onTap: () => notifier.setKey(null),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _roots.map((root) {
              final active = state.config.key == '$root $_keyMode';
              return _Pill(
                label: root,
                active: active,
                onTap: () => pickKey(root),
              );
            }).toList(),
          ),

          const SizedBox(height: 10),

          // ── Pitch Window ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Pitch Window',
                style: TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _StepButton(
                label: '-1 Oct',
                onTap: () => notifier.shiftPitchRange(-12),
              ),
              _StepButton(
                label: '+1 Oct',
                onTap: () => notifier.shiftPitchRange(12),
              ),
              _StepButton(
                label: 'Clear Notes',
                danger: true,
                onTap: () => notifier.clearNotes(),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            'Tempo range: ${rules.minTempo}-${rules.maxTempo} BPM',
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable sub-widgets ────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final String value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _Stepper({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _StepButton(label: '-', onTap: onDecrement),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 66),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MuzicianTheme.sky,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      _StepButton(label: '+', onTap: onIncrement),
    ],
  );
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _StepButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: danger
            ? MuzicianTheme.red.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: danger
              ? MuzicianTheme.red.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.16),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? MuzicianTheme.sky.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.18),
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

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? MuzicianTheme.emerald.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: active
              ? MuzicianTheme.emerald.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.16),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFDBEAFE),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
