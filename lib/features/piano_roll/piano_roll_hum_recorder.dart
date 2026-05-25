import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hum_to_midi.dart';
import '../../store/hum_to_midi_store.dart';
import '../../store/piano_roll_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';
import '../../schema/rules/mono_pitch_rules.dart' as rules;
import '../../schema/rules/mono_pitch_rules.dart' show HumSensitivity;

class PianoRollHumRecorderPanel extends ConsumerStatefulWidget {
  final bool isWeb;
  const PianoRollHumRecorderPanel({super.key, this.isWeb = kIsWeb});

  @override
  ConsumerState<PianoRollHumRecorderPanel> createState() =>
      _PianoRollHumRecorderPanelState();
}

class _PianoRollHumRecorderPanelState
    extends ConsumerState<PianoRollHumRecorderPanel> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWeb) {
      return const PianoRollHumRecorderCard(
        status: HumToMidiStatus.idle,
        liveNoteLabel: 'No pitch',
        statusLabel: 'Hum to MIDI not supported on web',
        elapsedLabel: 'N/A',
        onStart: null,
        onStop: null,
        onJumpToLatest: null,
        sensitivity: HumSensitivity.balanced,
        onSensitivityChanged: null,
      );
    }

    final ref = this.ref;
    final state = ref.watch(humToMidiProvider);
    final latestImportedRange = ref.watch(
      pianoRollProvider.select((state) => state.latestImportedRange),
    );
    if (state.status == HumToMidiStatus.recording && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (state.status != HumToMidiStatus.recording) {
      _ticker?.cancel();
      _ticker = null;
    }

    final elapsed = state.startedAtMs == null
        ? Duration.zero
        : Duration(
            milliseconds:
                DateTime.now().millisecondsSinceEpoch - state.startedAtMs!,
          );
    final elapsedLabel =
        '${elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    final sensitivity = ref.watch(
      settingsProvider.select((s) => s.humSensitivity),
    );
    final canChangeSensitivity =
        state.status != HumToMidiStatus.recording &&
        state.status != HumToMidiStatus.processing;

    return PianoRollHumRecorderCard(
      status: state.status,
      liveNoteLabel: state.liveMidiNote == null
          ? 'No pitch'
          : rules.midiToNoteLabel(state.liveMidiNote!),
      statusLabel: switch (state.status) {
        HumToMidiStatus.recording =>
          state.liveMidiNote == null ? 'No pitch' : 'Stable',
        HumToMidiStatus.processing => 'Processing',
        HumToMidiStatus.error => state.errorMessage ?? 'Error',
        HumToMidiStatus.completed => state.feedbackMessage ?? 'Imported',
        _ => 'Ready',
      },
      elapsedLabel: state.status == HumToMidiStatus.recording
          ? elapsedLabel
          : 'Idle',
      onStart:
          state.status == HumToMidiStatus.idle ||
              state.status == HumToMidiStatus.completed ||
              state.status == HumToMidiStatus.error
          ? () => ref.read(humToMidiProvider.notifier).startRecording()
          : null,
      onStop: state.status == HumToMidiStatus.recording
          ? () => ref.read(humToMidiProvider.notifier).stopRecording()
          : null,
      onJumpToLatest: latestImportedRange == null
          ? null
          : () {
              ref.read(pianoRollScrollToTickProvider.notifier).state =
                  latestImportedRange.startTick;
            },
      sensitivity: sensitivity,
      onSensitivityChanged: canChangeSensitivity
          ? (value) =>
                ref.read(settingsProvider.notifier).setHumSensitivity(value)
          : null,
    );
  }
}

class PianoRollHumRecorderCard extends StatelessWidget {
  final HumToMidiStatus status;
  final String liveNoteLabel;
  final String statusLabel;
  final String elapsedLabel;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onJumpToLatest;
  final HumSensitivity sensitivity;
  final ValueChanged<HumSensitivity>? onSensitivityChanged;

  const PianoRollHumRecorderCard({
    super.key,
    required this.status,
    required this.liveNoteLabel,
    required this.statusLabel,
    required this.elapsedLabel,
    required this.onStart,
    required this.onStop,
    this.onJumpToLatest,
    this.sensitivity = HumSensitivity.balanced,
    this.onSensitivityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isRecording = status == HumToMidiStatus.recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Hum to MIDI',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    liveNoteLabel,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              elapsedLabel,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            if (onStart != null || onStop != null)
              FilledButton(
                onPressed: isRecording ? onStop : onStart,
                child: Text(isRecording ? 'Stop' : 'Record'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _HumSensitivitySelector(
          value: sensitivity,
          onChanged: onSensitivityChanged,
        ),
        if (onJumpToLatest != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onJumpToLatest,
            child: const Text('Jump to latest'),
          ),
        ],
      ],
    );
  }
}

class _HumSensitivitySelector extends StatelessWidget {
  final HumSensitivity value;
  final ValueChanged<HumSensitivity>? onChanged;

  const _HumSensitivitySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pitch sensitivity',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<HumSensitivity>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: HumSensitivity.strict, label: Text('Strict')),
            ButtonSegment(
              value: HumSensitivity.balanced,
              label: Text('Balanced'),
            ),
            ButtonSegment(
              value: HumSensitivity.forgiving,
              label: Text('Forgiving'),
            ),
          ],
          selected: {value},
          onSelectionChanged: onChanged == null
              ? null
              : (set) => onChanged!(set.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
