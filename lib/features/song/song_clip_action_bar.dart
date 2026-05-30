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
    final clip = project.clips
        .where((c) => c.id == selectedId)
        .firstOrNull;
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

    void deselect() {
      ref.read(songSelectedClipIdProvider.notifier).state = null;
    }

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
            Expanded(
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
                      Text(
                        track.name,
                        style: const TextStyle(
                          color: MuzicianTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
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
                final newId =
                    ref.read(songProjectProvider.notifier).duplicateClip(clip.id);
                ref.read(songSelectedClipIdProvider.notifier).state = newId;
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
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        splashRadius: 22,
        icon: Icon(icon, color: color ?? MuzicianTheme.textSecondary),
        onPressed: onTap,
      ),
    );
  }
}
