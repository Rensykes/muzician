library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart' show TimeSignature;
import '../../models/song_playback.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/transport_strip.dart' as transport;
import '../_mockup_shell.dart' show showWidgetSheet, showPickerSheet;
import 'song_arranger_timeline.dart';
import 'song_clip_action_bar.dart';
import 'song_import_picker_sheet.dart';
import 'song_save_panel.dart';

class SongScreen extends ConsumerStatefulWidget {
  const SongScreen({super.key});

  @override
  ConsumerState<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends ConsumerState<SongScreen> {
  @override
  void initState() {
    super.initState();
    registerSongImportPicker();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songProjectProvider);
    final playback = ref.watch(songPlaybackProvider);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
          stops: [0, 0.3, 0.7, 1],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Song',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: MuzicianTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          '${project.tracks.length} tracks',
                          style: const TextStyle(
                            fontSize: 14,
                            color: MuzicianTheme.textMuted,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add Track',
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () => _showAddTrackSheet(context),
                  ),
                  IconButton(
                    tooltip: 'Save / Load',
                    icon: const Icon(
                      Icons.save_outlined,
                      color: MuzicianTheme.sky,
                    ),
                    onPressed: () => _showSavePanel(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Shared transport strip
            _SongTransportStrip(project: project, playback: playback),
            const SizedBox(height: 4),
            // Arranger timeline
            Expanded(
              child: project.tracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No tracks yet',
                            style: TextStyle(
                              color: MuzicianTheme.textMuted.withValues(
                                alpha: 0.6,
                              ),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _showAddTrackSheet(context),
                            icon: const Icon(
                              Icons.add,
                              color: MuzicianTheme.sky,
                            ),
                            label: const Text(
                              'Add Track',
                              style: TextStyle(color: MuzicianTheme.sky),
                            ),
                          ),
                        ],
                      ),
                    )
                  : SongArrangerTimeline(
                      measureTicks: song_rules.songTicksPerMeasure(
                        project.config.timeSignature,
                      ),
                      currentPlaybackTick: playback.currentTick,
                    ),
            ),
            const SongClipActionBar(),
          ],
        ),
      ),
    );
  }

  void _showAddTrackSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add Track',
                  style: TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.music_note,
                    color: MuzicianTheme.sky,
                  ),
                  title: const Text(
                    'Note Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Melody, chords, bass',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.note);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.album, color: MuzicianTheme.orange),
                  title: const Text(
                    'Drum Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Step sequencer',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.drum);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: MuzicianTheme.teal),
                  title: const Text(
                    'Audio Track',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    'Record or import audio clips',
                    style: TextStyle(color: MuzicianTheme.textMuted),
                  ),
                  onTap: () {
                    ref
                        .read(songProjectProvider.notifier)
                        .addTrack(SongTrackType.audio);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSavePanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MuzicianTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SongSavePanel(),
      ),
    );
  }
}

class _SongTransportStrip extends ConsumerWidget {
  final SongProject project;
  final SongPlaybackState playback;

  const _SongTransportStrip({required this.project, required this.playback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = playback.status == SongPlaybackStatus.playing;
    final playbackNotifier = ref.read(songPlaybackProvider.notifier);
    final songNotifier = ref.read(songProjectProvider.notifier);
    final bpm = project.config.tempo;
    final timeSig = project.config.timeSignature;
    final barBeat = transport.tickToBarBeatDisplay(
      playback.currentTick,
      timeSig,
    );
    final timeSigLabel = '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}';

    void onRewind() {
      HapticFeedback.selectionClick();
      playbackNotifier.stopPlayback();
    }

    void onStop() {
      HapticFeedback.lightImpact();
      playbackNotifier.stopPlayback();
    }

    void onPlayPause() {
      HapticFeedback.lightImpact();
      if (playing) {
        playbackNotifier.stopPlayback();
      } else {
        playbackNotifier.startPlayback();
      }
    }

    Future<void> onBpmTap() async {
      HapticFeedback.selectionClick();
      await showWidgetSheet(
        context: context,
        title: 'Tempo',
        child: Consumer(
          builder: (_, sheetRef, _) {
            final tempo = sheetRef.watch(
              songProjectProvider.select((s) => s.config.tempo),
            );
            return transport.BpmSheet(
              currentBpm: tempo,
              onChanged: (v) =>
                  sheetRef.read(songProjectProvider.notifier).setTempo(v),
            );
          },
        ),
      );
    }

    Future<void> onSigTap() async {
      HapticFeedback.selectionClick();
      final picked = await showPickerSheet<String>(
        context: context,
        title: 'Time Signature',
        options: transport.kTimeSignatureOptions,
        current: timeSigLabel,
      );
      if (picked == null) return;
      final parts = picked.split('/');
      songNotifier.setTimeSignature(
        TimeSignature(
          beatsPerMeasure: int.parse(parts[0]),
          beatUnit: int.parse(parts[1]),
        ),
      );
    }

    return transport.TransportStrip(
      bpm: bpm,
      barBeat: barBeat,
      timeSig: timeSig,
      playing: playing,
      onRewind: onRewind,
      onStop: onStop,
      onPlayPause: onPlayPause,
      onBpmTap: onBpmTap,
      onSigTap: onSigTap,
      onBpmDelta: (delta) => songNotifier.setTempo(bpm + delta),
    );
  }
}
