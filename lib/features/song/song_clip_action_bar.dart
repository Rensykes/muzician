/// SongClipActionBar — floating glass strip with clip-level actions.
///
/// Shows up when [songSelectedClipIdProvider] holds a non-null clip id.
/// Provides: Edit pattern · Duplicate · Make unique · Delete · Close (deselect).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_pattern_editor_launcher.dart';

class SongClipActionBar extends ConsumerWidget {
  const SongClipActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(songSelectedClipIdProvider);
    if (selectedId == null) return const SizedBox.shrink();

    final project = ref.watch(songProjectProvider);
    final clip = project.clips.where((c) => c.id == selectedId).firstOrNull;
    if (clip == null) {
      // Defensive: stale selection (e.g. clip was deleted). Clear it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(songSelectedClipIdProvider.notifier).state = null;
        }
      });
      return const SizedBox.shrink();
    }

    final patternRefs = project.clips
        .where((c) => c.patternId == clip.patternId)
        .length;
    final isShared = patternRefs > 1;
    final track = project.tracks.firstWhere((t) => t.id == clip.trackId);
    final accent = switch (track.type) {
      SongTrackType.note => MuzicianTheme.sky,
      SongTrackType.drum => MuzicianTheme.orange,
      SongTrackType.audio => MuzicianTheme.teal,
    };
    final clipTypeLabel = switch (track.type) {
      SongTrackType.note => 'NOTE CLIP',
      SongTrackType.drum => 'DRUM CLIP',
      SongTrackType.audio => 'AUDIO CLIP',
    };

    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 24,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    clipTypeLabel,
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.name,
                          style: const TextStyle(
                            color: MuzicianTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isShared) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.link,
                          size: 12,
                          color: MuzicianTheme.textMuted,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$patternRefs',
                          style: const TextStyle(
                            color: MuzicianTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(children: _buildActions(context, ref, clip, track)),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    SongClipInstance clip,
    SongTrack track,
  ) {
    final project = ref.read(songProjectProvider);
    final patternRefs = project.clips
        .where((c) => c.patternId == clip.patternId)
        .length;
    final isShared = patternRefs > 1;

    void deselect() {
      ref.read(songSelectedClipIdProvider.notifier).state = null;
    }

    return [
            _ActionBtn(
              icon: Icons.edit_outlined,
              tooltip: 'Edit pattern',
              onTap: () {
                HapticFeedback.selectionClick();
                openClipEditor(context, ref, clip);
              },
            ),
            _ActionBtn(
              icon: Icons.copy_outlined,
              tooltip: 'Duplicate',
              onTap: () {
                HapticFeedback.selectionClick();
                final newId = ref
                    .read(songProjectProvider.notifier)
                    .duplicateClip(clip.id);
                ref.read(songSelectedClipIdProvider.notifier).state = newId;
              },
            ),
            _ActionBtn(
              icon: Icons.content_paste_go,
              tooltip: 'Copy for paste',
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(songClipClipboardProvider.notifier).state = (
                  patternId: clip.patternId,
                  patternType: clip.patternType,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Clip copied — long-press a lane to paste'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (track.type == SongTrackType.note) ...[
              _ActionBtn(
                icon: Icons.arrow_downward,
                tooltip: 'Transpose down (long-press: octave)',
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(songProjectProvider.notifier)
                      .transposeClipPattern(clip.id, -1);
                },
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  ref
                      .read(songProjectProvider.notifier)
                      .transposeClipPattern(clip.id, -12);
                },
              ),
              _ActionBtn(
                icon: Icons.arrow_upward,
                tooltip: 'Transpose up (long-press: octave)',
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(songProjectProvider.notifier)
                      .transposeClipPattern(clip.id, 1);
                },
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  ref
                      .read(songProjectProvider.notifier)
                      .transposeClipPattern(clip.id, 12);
                },
              ),
            ],
            if (project.tracks.any(
              (t) => t.id != track.id && t.type == track.type,
            ))
              _ActionBtn(
                icon: Icons.swap_vert,
                tooltip: 'Move to track',
                onTap: () async {
                  HapticFeedback.selectionClick();
                  final targets = project.tracks
                      .where((t) => t.id != track.id && t.type == track.type)
                      .toList();
                  final picked = await showModalBottomSheet<String>(
                    context: context,
                    backgroundColor: MuzicianTheme.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Move to track',
                              style: TextStyle(
                                color: MuzicianTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final t in targets)
                            ListTile(
                              title: Text(
                                t.name,
                                style: const TextStyle(
                                  color: MuzicianTheme.textPrimary,
                                ),
                              ),
                              onTap: () => Navigator.pop(ctx, t.id),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (picked == null || !context.mounted) return;
                  final ok = ref
                      .read(songProjectProvider.notifier)
                      .moveClipToTrack(clip.id, picked);
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Target slot is occupied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            if (isShared)
              _ActionBtn(
                icon: Icons.call_split,
                tooltip: 'Make unique',
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(songProjectProvider.notifier)
                      .makeClipPatternUnique(clip.id);
                },
              ),
            _ActionBtn(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              color: MuzicianTheme.red,
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.read(songProjectProvider.notifier).deleteClip(clip.id);
                deselect();
              },
            ),
            _ActionBtn(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: () {
                HapticFeedback.selectionClick();
                deselect();
              },
            ),
    ];
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const CircleBorder(),
          child: Icon(icon, size: 20, color: color ?? MuzicianTheme.textSecondary),
        ),
      ),
    );
  }
}
