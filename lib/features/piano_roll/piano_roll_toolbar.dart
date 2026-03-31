/// Piano Roll config widgets – Playback, Edit, and Pitch focused cards.
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

const _snapOptions = <(int ticks, String label)>[
  (1, 'Free'),
  (2, '1/8'),
  (4, '1/4'),
  (8, '1/2'),
];

// ── Playback Config ──────────────────────────────────────────────────────────

/// Tempo, measure count, and time signature.
class PianoRollPlaybackConfig extends ConsumerWidget {
  const PianoRollPlaybackConfig({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('PLAYBACK'),
        Row(
          children: [
            Expanded(
              child: _LabeledStepper(
                label: 'Tempo',
                value: '${state.config.tempo} BPM',
                onDecrement: () => notifier.setTempo(state.config.tempo - 1),
                onIncrement: () => notifier.setTempo(state.config.tempo + 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledStepper(
                label: 'Measures',
                value: '${state.config.totalMeasures}',
                onDecrement: () =>
                    notifier.setTotalMeasures(state.config.totalMeasures - 1),
                onIncrement: () =>
                    notifier.setTotalMeasures(state.config.totalMeasures + 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _Label('Time Signature'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _timeSigOptions.map((o) {
            return _Pill(
              label: o.$3,
              active: activeTimeSig == o.$3,
              onTap: () => notifier.setTimeSignature(
                TimeSignature(beatsPerMeasure: o.$1, beatUnit: o.$2),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _InfoText('Tick grid: 1/16'),
            _InfoText('$totalRollTicks ticks total'),
            _InfoText('Tempo: ${rules.minTempo}–${rules.maxTempo} BPM'),
          ],
        ),
      ],
    );
  }
}

// ── Edit Config ───────────────────────────────────────────────────────────────

/// Active tool and snap resolution.
class PianoRollEditConfig extends ConsumerWidget {
  const PianoRollEditConfig({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('EDIT'),
        const _Label('Tool'),
        const SizedBox(height: 6),
        Row(
          children: [
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
        const SizedBox(height: 12),
        const _Label('Snap'),
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
      ],
    );
  }
}

// ── Pitch Config ─────────────────────────────────────────────────────────────

/// Pitch window shift and note clearing.
class PianoRollPitchConfig extends ConsumerWidget {
  const PianoRollPitchConfig({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('PITCH WINDOW'),
        Row(
          children: [
            _StepButton(
              label: '−1 Oct',
              onTap: () => notifier.shiftPitchRange(-12),
            ),
            const SizedBox(width: 8),
            _StepButton(
              label: '+1 Oct',
              onTap: () => notifier.shiftPitchRange(12),
            ),
            const Spacer(),
            Text(
              'MIDI ${state.pitchRangeStart}–${state.pitchRangeEnd}',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _StepButton(
          label: 'Clear All Notes',
          danger: true,
          onTap: () => notifier.clearNotes(),
        ),
      ],
    );
  }
}

// ── Reusable sub-widgets ──────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: MuzicianTheme.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _InfoText extends StatelessWidget {
  final String text;

  const _InfoText(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: MuzicianTheme.textMuted,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _LabeledStepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _LabeledStepper({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Label(label),
      const SizedBox(height: 6),
      _Stepper(
        value: value,
        onDecrement: onDecrement,
        onIncrement: onIncrement,
      ),
    ],
  );
}

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
      _StepButton(label: '−', onTap: onDecrement),
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
