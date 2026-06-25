import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../store/song_audio_recorder_store.dart'
    show SongAudioRecorderStatus;
import '../../store/songwriter_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';

/// Recorder sheet. Pops with the recorded [AudioAsset] (or null on cancel).
class SongwriterAudioRecorderSheet extends ConsumerWidget {
  final int countInMs;
  const SongwriterAudioRecorderSheet({super.key, this.countInMs = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SongwriterAudioRecorderState>(songwriterAudioRecorderProvider, (
      prev,
      next,
    ) {
      if (next.status == SongAudioRecorderStatus.ready &&
          next.pendingAsset != null) {
        final asset = ref
            .read(songwriterAudioRecorderProvider.notifier)
            .consumePendingAsset();
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      }
    });
    final state = ref.watch(songwriterAudioRecorderProvider);
    final n = ref.read(songwriterAudioRecorderProvider.notifier);

    // Handle the already-ready case so a reopened sheet doesn't hang.
    if (state.status == SongAudioRecorderStatus.ready &&
        state.pendingAsset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final asset = ref
            .read(songwriterAudioRecorderProvider.notifier)
            .consumePendingAsset();
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(asset);
        }
      });
    }

    final label = switch (state.status) {
      SongAudioRecorderStatus.idle => 'Ready',
      SongAudioRecorderStatus.countIn => 'Count-in…',
      SongAudioRecorderStatus.recording => 'Recording…',
      SongAudioRecorderStatus.finalising => 'Finalising…',
      SongAudioRecorderStatus.ready => 'Done',
      SongAudioRecorderStatus.error => state.errorMessage ?? 'Error',
    };
    final isRec = state.status == SongAudioRecorderStatus.recording;
    final busy =
        state.status == SongAudioRecorderStatus.finalising ||
        state.status == SongAudioRecorderStatus.ready;
    final isCountIn = state.status == SongAudioRecorderStatus.countIn;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await n.cancel();
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop<AudioAsset?>(null);
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: MuzicianTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              if (busy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      key: const ValueKey('sw-audio-rec-cancel'),
                      onPressed: () async {
                        await n.cancel();
                        if (context.mounted && Navigator.of(context).canPop()) {
                          Navigator.of(context).pop<AudioAsset?>(null);
                        }
                      },
                      child: Text(isRec || isCountIn ? 'Cancel' : 'Close'),
                    ),
                    if (isRec)
                      FilledButton.icon(
                        key: const ValueKey('sw-audio-rec-stop'),
                        onPressed: () => n.stop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    else if (state.status == SongAudioRecorderStatus.idle ||
                        state.status == SongAudioRecorderStatus.error)
                      FilledButton.icon(
                        key: const ValueKey('sw-audio-rec-start'),
                        onPressed: () => n.start(countInMs: countInMs),
                        icon: const Icon(Icons.mic),
                        label: const Text('Record'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
