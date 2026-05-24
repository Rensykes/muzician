import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/hum_to_midi.dart';
import '../../store/hum_to_midi_store.dart';
import '../../store/piano_roll_store.dart';
import '../../theme/muzician_theme.dart';
import '../../schema/rules/mono_pitch_rules.dart' as rules;

class PianoRollHumRecorderPanel extends ConsumerStatefulWidget {
  const PianoRollHumRecorderPanel({super.key});

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

  const PianoRollHumRecorderCard({
    super.key,
    required this.status,
    required this.liveNoteLabel,
    required this.statusLabel,
    required this.elapsedLabel,
    required this.onStart,
    required this.onStop,
    this.onJumpToLatest,
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
            FilledButton(
              onPressed: isRecording ? onStop : onStart,
              child: Text(isRecording ? 'Stop' : 'Record'),
            ),
          ],
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
