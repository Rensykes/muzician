import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../schema/rules/song_audio_rules.dart';
import '../../schema/rules/song_rules.dart' show songTicksPerMeasure;
import '../../store/song_audio_recorder_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';

/// Recorder bottom sheet.
///
/// Flow: idle → countIn → recording → finalising → ready (auto-pops with the
/// recorded asset).  There is intentionally no review step — the caller
/// commits the clip immediately and the user manages it from the timeline.
class SongAudioRecorderSheet extends ConsumerWidget {
  final String trackId;
  final int startTick;

  const SongAudioRecorderSheet({
    super.key,
    required this.trackId,
    required this.startTick,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-pop with the asset once the recorder finishes finalising the take.
    ref.listen<SongAudioRecorderState>(songAudioRecorderProvider, (prev, next) {
      if (next.status == SongAudioRecorderStatus.ready &&
          next.pendingAsset != null) {
        final asset = ref
            .read(songAudioRecorderProvider.notifier)
            .consumePendingAsset();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      }
    });

    final state = ref.watch(songAudioRecorderProvider);
    final notifier = ref.read(songAudioRecorderProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _StatusLabel(
              status: state.status,
              errorMessage: state.errorMessage,
            ),
            const SizedBox(height: 20),
            _ActionRow(
              status: state.status,
              onStart: () {
                final config = ref.read(songProjectProvider).config;
                final ticksPerMeasure = songTicksPerMeasure(
                  config.timeSignature,
                );
                final countInMs = audioTickToMs(ticksPerMeasure, config);
                notifier.start(
                  trackId: trackId,
                  startTick: startTick,
                  countInMs: countInMs,
                );
              },
              onStop: () => notifier.stop(),
              onCancel: () async {
                await notifier.cancel();
                if (!context.mounted) return;
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop<AudioAsset?>(null);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final String? errorMessage;
  const _StatusLabel({required this.status, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      SongAudioRecorderStatus.idle => 'Ready',
      SongAudioRecorderStatus.countIn => 'Count-in…',
      SongAudioRecorderStatus.recording => 'Recording…',
      SongAudioRecorderStatus.finalising => 'Finalising…',
      SongAudioRecorderStatus.ready => 'Done',
      SongAudioRecorderStatus.error => errorMessage ?? 'Error',
    };
    return Text(
      label,
      style: const TextStyle(
        color: MuzicianTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const _ActionRow({
    required this.status,
    required this.onStart,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SongAudioRecorderStatus.idle:
      case SongAudioRecorderStatus.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-cancel'),
              onPressed: onCancel,
              child: const Text('Close'),
            ),
            FilledButton.icon(
              key: const ValueKey('audio-rec-start'),
              onPressed: onStart,
              icon: const Icon(Icons.mic),
              label: const Text('Record'),
            ),
          ],
        );
      case SongAudioRecorderStatus.countIn:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('audio-rec-stop'),
              onPressed: null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        );
      case SongAudioRecorderStatus.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              key: const ValueKey('audio-rec-stop'),
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        );
      case SongAudioRecorderStatus.finalising:
      case SongAudioRecorderStatus.ready:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        );
    }
  }
}
