import 'dart:async';

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
/// Flow: idle → countIn → recording → finalising → ready for review. The take
/// changes the Song arrangement only after the user keeps it.
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
    final state = ref.watch(songAudioRecorderProvider);
    final notifier = ref.read(songAudioRecorderProvider.notifier);

    return PopScope<AudioAsset?>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(notifier.cancel());
      },
      child: Container(
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
                elapsedMs: state.elapsedMs,
                errorMessage: state.errorMessage,
              ),
              const SizedBox(height: 20),
              _ActionRow(
                status: state.status,
                isPreviewing: state.isPreviewing,
                onStart: () {
                  final config = ref.read(songProjectProvider).config;
                  final countInMs = audioTickToMs(
                    songTicksPerMeasure(config.timeSignature),
                    config,
                  );
                  notifier.start(
                    trackId: trackId,
                    startTick: startTick,
                    countInMs: countInMs,
                  );
                },
                onStop: () => notifier.stop(),
                onPreview: () => notifier.previewPendingTake(),
                onStopPreview: () => notifier.stopPreview(),
                onRerecord: () {
                  final config = ref.read(songProjectProvider).config;
                  final countInMs = audioTickToMs(
                    songTicksPerMeasure(config.timeSignature),
                    config,
                  );
                  notifier.rerecord(countInMs: countInMs);
                },
                onAccept: () async {
                  final asset = await notifier.acceptPendingTake();
                  if (!context.mounted || asset == null) return;
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop<AudioAsset?>(asset);
                  }
                },
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
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final int elapsedMs;
  final String? errorMessage;

  const _StatusLabel({
    required this.status,
    required this.elapsedMs,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      SongAudioRecorderStatus.idle => 'Ready',
      SongAudioRecorderStatus.countIn => 'Count-in…',
      SongAudioRecorderStatus.recording => 'Recording…',
      SongAudioRecorderStatus.finalising => 'Finalising…',
      SongAudioRecorderStatus.ready =>
        'Review take · ${_durationLabel(elapsedMs)}',
      SongAudioRecorderStatus.error => errorMessage ?? 'Error',
    };
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (status == SongAudioRecorderStatus.ready &&
            errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: MuzicianTheme.textSecondary),
          ),
        ],
      ],
    );
  }
}

String _durationLabel(int durationMs) {
  final seconds = (durationMs / 1000).floor();
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}

class _ActionRow extends StatelessWidget {
  final SongAudioRecorderStatus status;
  final bool isPreviewing;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPreview;
  final VoidCallback onStopPreview;
  final VoidCallback onRerecord;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  const _ActionRow({
    required this.status,
    required this.isPreviewing,
    required this.onStart,
    required this.onStop,
    required this.onPreview,
    required this.onStopPreview,
    required this.onRerecord,
    required this.onAccept,
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-cancel'),
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        );
      case SongAudioRecorderStatus.ready:
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          runAlignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-discard'),
              onPressed: onCancel,
              child: const Text('Discard'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('audio-rec-audition'),
              onPressed: isPreviewing ? onStopPreview : onPreview,
              icon: Icon(isPreviewing ? Icons.stop : Icons.play_arrow),
              label: Text(isPreviewing ? 'Stop audition' : 'Audition'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('audio-rec-rerecord'),
              onPressed: onRerecord,
              icon: const Icon(Icons.refresh),
              label: const Text('Re-record'),
            ),
            FilledButton.icon(
              key: const ValueKey('audio-rec-accept'),
              onPressed: onAccept,
              icon: const Icon(Icons.check),
              label: const Text('Keep take'),
            ),
          ],
        );
    }
  }
}
