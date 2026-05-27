library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';

class SongTrackHeader extends ConsumerWidget {
  final SongTrack track;
  final VoidCallback? onTap;

  const SongTrackHeader({super.key, required this.track, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: track.type == SongTrackType.note
                  ? MuzicianTheme.sky.withValues(alpha: 0.15)
                  : MuzicianTheme.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              track.type == SongTrackType.note ? 'NOTE' : 'DRUM',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: track.type == SongTrackType.note
                    ? MuzicianTheme.sky
                    : MuzicianTheme.orange,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Text(
                track.name,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            tooltip: track.isMuted ? 'Unmute' : 'Mute',
            icon: Icon(
              track.isMuted ? Icons.volume_off : Icons.volume_up,
              size: 18,
              color: track.isMuted
                  ? MuzicianTheme.red
                  : MuzicianTheme.textSecondary,
            ),
            onPressed: () =>
                ref.read(songProjectProvider.notifier).toggleMute(track.id),
          ),
          IconButton(
            tooltip: track.isSolo ? 'Unsolo' : 'Solo',
            icon: Icon(
              track.isSolo ? Icons.headphones : Icons.headset_off,
              size: 18,
              color: track.isSolo
                  ? MuzicianTheme.emerald
                  : MuzicianTheme.textMuted,
            ),
            onPressed: () =>
                ref.read(songProjectProvider.notifier).toggleSolo(track.id),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz,
              color: MuzicianTheme.textMuted,
              size: 18,
            ),
            color: MuzicianTheme.surface,
            onSelected: (value) {
              switch (value) {
                case 'rename':
                  _showRenameDialog(context, ref, track);
                  break;
                case 'duplicate':
                  ref
                      .read(songProjectProvider.notifier)
                      .duplicateTrack(track.id);
                  break;
                case 'delete':
                  ref.read(songProjectProvider.notifier).deleteTrack(track.id);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, SongTrack track) {
    final controller = TextEditingController(text: track.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text(
          'Rename Track',
          style: TextStyle(color: MuzicianTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Track name',
            hintStyle: TextStyle(color: MuzicianTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(songProjectProvider.notifier)
                  .renameTrack(track.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
