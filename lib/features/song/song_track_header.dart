library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';

class SongTrackHeader extends ConsumerWidget {
  final SongTrack track;
  final VoidCallback? onTap;

  const SongTrackHeader({super.key, required this.track, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = switch (track.type) {
      SongTrackType.note => MuzicianTheme.sky,
      SongTrackType.drum => MuzicianTheme.orange,
      SongTrackType.audio => MuzicianTheme.teal,
    };
    final typeLabel = switch (track.type) {
      SongTrackType.note => 'NOTE',
      SongTrackType.drum => 'DRUM',
      SongTrackType.audio => 'AUDIO',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: Colors.white.withValues(alpha: 0.025),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
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
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _HeaderIconButton(
                  tooltip: track.isMuted ? 'Unmute' : 'Mute',
                  icon: track.isMuted ? Icons.volume_off : Icons.volume_up,
                  color: track.isMuted
                      ? MuzicianTheme.red
                      : MuzicianTheme.textSecondary,
                  onTap: () => ref
                      .read(songProjectProvider.notifier)
                      .toggleMute(track.id),
                ),
                _HeaderIconButton(
                  tooltip: track.isSolo ? 'Unsolo' : 'Solo',
                  icon: track.isSolo ? Icons.headphones : Icons.headset_off,
                  color: track.isSolo
                      ? MuzicianTheme.emerald
                      : MuzicianTheme.textMuted,
                  onTap: () => ref
                      .read(songProjectProvider.notifier)
                      .toggleSolo(track.id),
                ),
                _TrackOverflowMenu(track: track),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 24,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 24),
        splashRadius: 18,
        icon: Icon(icon, color: color),
        onPressed: onTap,
      ),
    );
  }
}

class _TrackOverflowMenu extends ConsumerWidget {
  final SongTrack track;

  const _TrackOverflowMenu({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 32,
      height: 24,
      child: IconButton(
        tooltip: 'Track menu',
        iconSize: 16,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 24),
        splashRadius: 18,
        icon: const Icon(Icons.more_horiz, color: MuzicianTheme.textMuted),
        onPressed: () => _showOverflowMenu(context, ref),
      ),
    );
  }

  Future<void> _showOverflowMenu(BuildContext context, WidgetRef ref) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + button.size.height,
      overlay.size.width - origin.dx - button.size.width,
      0,
    );
    final value = await showMenu<String>(
      context: context,
      position: position,
      color: MuzicianTheme.surface,
      items: const [
        PopupMenuItem(value: 'volume', child: Text('Volume')),
        PopupMenuItem(value: 'moveUp', child: Text('Move up')),
        PopupMenuItem(value: 'moveDown', child: Text('Move down')),
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted || value == null) return;
    switch (value) {
      case 'volume':
        _showVolumeDialog(context, ref, track);
        break;
      case 'moveUp':
        ref.read(songProjectProvider.notifier).moveTrack(track.id, -1);
        break;
      case 'moveDown':
        ref.read(songProjectProvider.notifier).moveTrack(track.id, 1);
        break;
      case 'rename':
        _showRenameDialog(context, ref, track);
        break;
      case 'delete':
        ref.read(songProjectProvider.notifier).deleteTrack(track.id);
        break;
    }
  }

  void _showVolumeDialog(BuildContext context, WidgetRef ref, SongTrack track) {
    showDialog(
      context: context,
      builder: (ctx) => MuzicianDialog(
        title: 'Track Volume',
        content: Consumer(
          builder: (_, dialogRef, _) {
            final volume = dialogRef.watch(
              songProjectProvider.select(
                (p) => p.tracks
                    .firstWhere((t) => t.id == track.id, orElse: () => track)
                    .volume,
              ),
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.volume_down,
                  color: MuzicianTheme.textMuted,
                  size: 18,
                ),
                Expanded(
                  child: Slider(
                    key: Key('trackVolumeSlider_${track.id}'),
                    value: volume,
                    activeColor: MuzicianTheme.sky,
                    onChanged: (v) => dialogRef
                        .read(songProjectProvider.notifier)
                        .setTrackVolume(track.id, v),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(volume * 100).round()}%',
                    style: const TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          MuzicianDialogButton(
            'Done',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, SongTrack track) {
    final controller = TextEditingController(text: track.name);
    showDialog(
      context: context,
      builder: (ctx) => MuzicianDialog(
        title: 'Rename Track',
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
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.pop(ctx),
          ),
          MuzicianDialogButton(
            'Rename',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () {
              ref
                  .read(songProjectProvider.notifier)
                  .renameTrack(track.id, controller.text);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
