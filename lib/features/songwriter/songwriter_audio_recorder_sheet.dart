import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song_project.dart' show AudioAsset;
import '../../store/settings_store.dart';
import '../../store/song_audio_recorder_store.dart'
    show SongAudioRecorderStatus;
import '../../store/songwriter_audio_recorder_store.dart';
import '../../theme/muzician_theme.dart';

/// Recorder sheet. Pops with the recorded [AudioAsset] (or null on cancel).
///
/// Optional record-time monitoring: when [monitorTemplate] is non-null the user
/// can toggle Backing / Metronome / Count-in (defaults from settings).
///
/// During recording it also shows a bar-progress indicator. The songwriter
/// recorder runs no playback clock, so progress is driven by a local
/// [Stopwatch] paced against [msPerBar] (derived from the project tempo) toward
/// [targetBars] (the bars available from the clip's start to the section end).
/// Both default to 0, in which case the indicator is hidden.
class SongwriterAudioRecorderSheet extends ConsumerStatefulWidget {
  final SongwriterRecordMonitor? monitorTemplate;
  final int countInBarMs;
  final int countInBeats;
  final int targetBars;
  final double msPerBar;
  const SongwriterAudioRecorderSheet({
    super.key,
    this.monitorTemplate,
    this.countInBarMs = 0,
    this.countInBeats = 4,
    this.targetBars = 0,
    this.msPerBar = 0,
  });

  @override
  ConsumerState<SongwriterAudioRecorderSheet> createState() =>
      _SongwriterAudioRecorderSheetState();
}

class _SongwriterAudioRecorderSheetState
    extends ConsumerState<SongwriterAudioRecorderSheet> {
  // Monitor toggles, seeded from settings.
  late bool _backing;
  late bool _metronome;
  late bool _countIn;

  // Bar-progress: the recorder runs no clock, so a local stopwatch paces it.
  final Stopwatch _sw = Stopwatch();
  Timer? _timer;
  double _elapsedMs = 0;
  bool _autoStopped = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backing = s.recordMonitorBacking;
    _metronome = s.recordMonitorMetronome;
    _countIn = s.recordCountIn;
  }

  bool get _hasProgress => widget.targetBars > 0 && widget.msPerBar > 0;

  void _startTimer() {
    _sw
      ..reset()
      ..start();
    _elapsedMs = 0;
    _autoStopped = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() => _elapsedMs = _sw.elapsedMilliseconds.toDouble());
      // Auto-stop once the take fills the available bars, so a recording can
      // never run past the section it is being placed into.
      if (!_autoStopped &&
          _hasProgress &&
          _elapsedMs >= widget.targetBars * widget.msPerBar) {
        _autoStopped = true;
        ref.read(songwriterAudioRecorderProvider.notifier).stop();
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onRecord() {
    final t = widget.monitorTemplate;
    final useMonitor = t != null && (_backing || _metronome);
    ref
        .read(songwriterAudioRecorderProvider.notifier)
        .start(
          countInMs: _countIn ? widget.countInBarMs : 0,
          countInBeats: widget.countInBeats,
          monitor: useMonitor
              ? t.copyWith(backing: _backing, metronome: _metronome)
              : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SongAudioRecorderStatus>(
      songwriterAudioRecorderProvider.select((s) => s.status),
      (prev, next) {
        if (next == SongAudioRecorderStatus.recording &&
            prev != SongAudioRecorderStatus.recording) {
          _startTimer();
        } else if (prev == SongAudioRecorderStatus.recording &&
            next != SongAudioRecorderStatus.recording) {
          _stopTimer();
        }
      },
    );

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
    final preRecord =
        state.status == SongAudioRecorderStatus.idle ||
        state.status == SongAudioRecorderStatus.error;

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
              if (isRec && _hasProgress) ...[
                const SizedBox(height: 16),
                _BarProgress(
                  elapsedMs: _elapsedMs,
                  msPerBar: widget.msPerBar,
                  targetBars: widget.targetBars,
                ),
              ],
              if (preRecord) ...[
                const SizedBox(height: 12),
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-backing',
                  title: 'Backing',
                  subtitle: 'Loop the section (chords, drums, audio)',
                  value: _backing,
                  enabled: widget.monitorTemplate != null,
                  onChanged: (v) {
                    setState(() => _backing = v);
                    ref
                        .read(settingsProvider.notifier)
                        .setRecordMonitorBacking(v);
                  },
                ),
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-metronome',
                  title: 'Metronome',
                  subtitle: 'Click on every beat',
                  value: _metronome,
                  enabled: widget.monitorTemplate != null,
                  onChanged: (v) {
                    setState(() => _metronome = v);
                    ref
                        .read(settingsProvider.notifier)
                        .setRecordMonitorMetronome(v);
                  },
                ),
                _MonitorToggle(
                  itemKey: 'sw-rec-toggle-countin',
                  title: 'Count-in',
                  subtitle: 'One bar before recording',
                  value: _countIn,
                  enabled: true,
                  onChanged: (v) {
                    setState(() => _countIn = v);
                    ref.read(settingsProvider.notifier).setRecordCountIn(v);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Use headphones — speaker playback bleeds into the mic.',
                    style: TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
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
                    else if (preRecord)
                      FilledButton.icon(
                        key: const ValueKey('sw-audio-rec-start'),
                        onPressed: _onRecord,
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

/// Bar-progress bar shown while recording. Caps the bar at 1.0; the label may
/// read past [targetBars] if the user records longer than the available span.
class _BarProgress extends StatelessWidget {
  const _BarProgress({
    required this.elapsedMs,
    required this.msPerBar,
    required this.targetBars,
  });
  final double elapsedMs;
  final double msPerBar;
  final int targetBars;

  @override
  Widget build(BuildContext context) {
    final barFloat = elapsedMs / msPerBar;
    final progress = (barFloat / targetBars).clamp(0.0, 1.0).toDouble();
    final currentBar = barFloat.floor() + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: const AlwaysStoppedAnimation(MuzicianTheme.sky),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bar $currentBar / $targetBars',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _MonitorToggle extends StatelessWidget {
  final String itemKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _MonitorToggle({
    required this.itemKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: ValueKey(itemKey),
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(
        title,
        style: const TextStyle(
          color: MuzicianTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: MuzicianTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}
