library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_playback.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_arranger_timeline.dart';
import 'song_save_panel.dart';

class SongScreen extends ConsumerStatefulWidget {
  const SongScreen({super.key});

  @override
  ConsumerState<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends ConsumerState<SongScreen> {
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
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
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
            const SizedBox(height: 12),
            // Transport bar
            _SongTransportBar(
              project: project,
              playback: playback,
              onTogglePlayback: _togglePlayback,
              onRewind: _rewind,
              onAddTrack: () => _showAddTrackSheet(context),
            ),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }

  void _togglePlayback() {
    final notifier = ref.read(songPlaybackProvider.notifier);
    if (ref.read(songPlaybackProvider).status == SongPlaybackStatus.playing) {
      notifier.stopPlayback();
    } else {
      notifier.startPlayback();
    }
  }

  void _rewind() {
    ref.read(songPlaybackProvider.notifier).stopPlayback();
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

class _SongTransportBar extends StatelessWidget {
  final SongProject project;
  final SongPlaybackState playback;
  final VoidCallback onTogglePlayback;
  final VoidCallback onRewind;
  final VoidCallback onAddTrack;

  const _SongTransportBar({
    required this.project,
    required this.playback,
    required this.onTogglePlayback,
    required this.onRewind,
    required this.onAddTrack,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = playback.status == SongPlaybackStatus.playing;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Rewind',
            icon: const Icon(
              Icons.skip_previous,
              color: MuzicianTheme.textSecondary,
              size: 22,
            ),
            onPressed: onRewind,
          ),
          IconButton(
            tooltip: isPlaying ? 'Pause' : 'Play',
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: MuzicianTheme.sky,
              size: 28,
            ),
            onPressed: onTogglePlayback,
          ),
          const SizedBox(width: 8),
          Text(
            '${project.config.tempo} BPM',
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${project.config.timeSignature.beatsPerMeasure}/${project.config.timeSignature.beatUnit}',
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${project.config.totalMeasures} bars',
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAddTrack,
            icon: const Icon(Icons.add, size: 16, color: MuzicianTheme.sky),
            label: const Text(
              'Add Track',
              style: TextStyle(color: MuzicianTheme.sky, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
