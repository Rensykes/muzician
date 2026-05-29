import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart';
import '../../store/song_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_audio_clip_body.dart';

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
            if (state.status == SongAudioRecorderStatus.preview &&
                state.pendingAsset != null)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: AudioClipBody(
                  name: 'Preview',
                  durationMs: state.pendingAsset!.durationMs,
                  format: state.pendingAsset!.format,
                  peaks: state.pendingAsset!.peaks,
                  isBroken: false,
                ),
              ),
            const SizedBox(height: 24),
            _ActionRow(
              status: state.status,
              onStart: () => notifier.start(
                trackId: trackId,
                startTick: startTick,
                countInMs: 0,
              ),
              onStop: () => notifier.stop(),
              onConfirm: () {
                final asset = notifier.consumePendingAsset();
                Navigator.of(context).pop<AudioAsset?>(asset);
              },
              onDiscard: () async {
                await notifier.discard();
                if (!context.mounted) return;
                Navigator.of(context).pop<AudioAsset?>(null);
              },
              onRetry: () => notifier.discard(),
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
      SongAudioRecorderStatus.preview => 'Review the take',
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
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;
  final VoidCallback onRetry;

  const _ActionRow({
    required this.status,
    required this.onStart,
    required this.onStop,
    required this.onConfirm,
    required this.onDiscard,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SongAudioRecorderStatus.idle:
      case SongAudioRecorderStatus.error:
        return FilledButton.icon(
          key: const ValueKey('audio-rec-start'),
          onPressed: onStart,
          icon: const Icon(Icons.mic),
          label: const Text('Record'),
        );
      case SongAudioRecorderStatus.countIn:
      case SongAudioRecorderStatus.recording:
      case SongAudioRecorderStatus.finalising:
        return FilledButton.icon(
          key: const ValueKey('audio-rec-stop'),
          onPressed:
              status == SongAudioRecorderStatus.recording ? onStop : null,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        );
      case SongAudioRecorderStatus.preview:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              key: const ValueKey('audio-rec-discard'),
              onPressed: onDiscard,
              child: const Text('Discard'),
            ),
            TextButton(
              key: const ValueKey('audio-rec-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
            FilledButton(
              key: const ValueKey('audio-rec-confirm'),
              onPressed: onConfirm,
              child: const Text('Confirm'),
            ),
          ],
        );
    }
  }
}
