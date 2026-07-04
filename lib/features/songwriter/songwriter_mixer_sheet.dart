/// Per-section mixer: volume / pan / mute strip for every lane in a section.
///
/// Pure store UI — controls write through [SongwriterNotifier.setLaneVolume],
/// [SongwriterNotifier.setLanePan] and [SongwriterNotifier.setLaneMuted]; the
/// transport picks the values up on the next play (events and the audio clip
/// schedule are computed at start).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';

/// Pan values closer to center than this snap to exactly 0.0.
const _panSnapThreshold = 0.08;

Future<void> showSongwriterMixerSheet(
  BuildContext context, {
  required String sectionId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.75,
    ),
    builder: (_) => Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: SongwriterMixerSheet(sectionId: sectionId),
    ),
  );
}

/// Rename dialog for a lane. Empty input clears the label back to the kind
/// fallback ("Harmony", "Beat", …). Shared by the mixer strips and the
/// harmony lane headers.
void showLaneRenameDialog(
  BuildContext context,
  WidgetRef ref, {
  required String sectionId,
  required SongLane lane,
}) {
  final controller = TextEditingController(text: lane.label ?? '');
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => MuzicianDialog(
      title: 'Lane name',
      content: TextField(
        key: const Key('laneRenameField'),
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Lead vocal, Guitars…'),
      ),
      actions: [
        MuzicianDialogButton('Cancel', onPressed: () => Navigator.pop(dialogCtx)),
        MuzicianDialogButton(
          'Save',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () {
            ref
                .read(songwriterProvider.notifier)
                .renameLane(
                  sectionId: sectionId,
                  laneId: lane.id,
                  label: controller.text,
                );
            Navigator.pop(dialogCtx);
          },
        ),
      ],
    ),
  );
}

class SongwriterMixerSheet extends ConsumerWidget {
  const SongwriterMixerSheet({super.key, required this.sectionId});
  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(
      songwriterProvider.select(
        (p) => p.sections.firstWhere(
          (s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
        ),
      ),
    );
    if (section.id.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mixer — ${section.label ?? 'Section'}',
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (section.lanes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No lanes in this section yet.',
                  style: TextStyle(color: MuzicianTheme.textMuted),
                ),
              )
            else
              // Save lanes follow the primary harmony lane's mix (their
              // blocks render and sound as part of it), so they get no strip
              // of their own — unless the section has no harmony lane at all.
              for (final lane in section.lanes)
                if (lane.kind != SongLaneKind.save ||
                    !section.lanes.any((l) => l.kind == SongLaneKind.harmony))
                  _MixerStrip(sectionId: sectionId, lane: lane),
          ],
        ),
      ),
    );
  }
}

class _MixerStrip extends ConsumerWidget {
  const _MixerStrip({required this.sectionId, required this.lane});
  final String sectionId;
  final SongLane lane;

  static IconData _kindIcon(SongLaneKind kind) => switch (kind) {
    SongLaneKind.harmony => Icons.piano,
    SongLaneKind.save => Icons.bookmark_outline,
    SongLaneKind.drum => Icons.graphic_eq,
    SongLaneKind.audio => Icons.mic,
  };

  static String _kindFallbackLabel(SongLaneKind kind) => switch (kind) {
    SongLaneKind.harmony => 'Harmony',
    SongLaneKind.save => 'Save',
    SongLaneKind.drum => 'Beat',
    SongLaneKind.audio => 'Sample',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final strip = Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        border: Border.all(color: MuzicianTheme.glassBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _kindIcon(lane.kind),
                size: 15,
                color: MuzicianTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: Key('mixerRename_${lane.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showLaneRenameDialog(
                    context,
                    ref,
                    sectionId: sectionId,
                    lane: lane,
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          lane.label ?? _kindFallbackLabel(lane.kind),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MuzicianTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.edit_outlined,
                        size: 12,
                        color: MuzicianTheme.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: Key('mixerMute_${lane.id}'),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: lane.muted ? 'Unmute' : 'Mute',
                icon: Icon(
                  lane.muted ? Icons.volume_off : Icons.volume_up,
                  color: lane.muted
                      ? MuzicianTheme.sky
                      : MuzicianTheme.textMuted,
                ),
                onPressed: () => notifier.setLaneMuted(
                  sectionId: sectionId,
                  laneId: lane.id,
                  muted: !lane.muted,
                ),
              ),
            ],
          ),
          _LabeledSlider(
            label: 'Vol',
            child: Slider(
              key: Key('mixerVolume_${lane.id}'),
              value: lane.volume,
              onChanged: (v) => notifier.setLaneVolume(
                sectionId: sectionId,
                laneId: lane.id,
                volume: v,
              ),
            ),
          ),
          _LabeledSlider(
            label: 'Pan',
            trailing: lane.pan == 0.0
                ? 'C'
                : '${lane.pan < 0 ? 'L' : 'R'}${(lane.pan.abs() * 100).round()}',
            child: Slider(
              key: Key('mixerPan_${lane.id}'),
              min: -1.0,
              max: 1.0,
              value: lane.pan,
              onChanged: (v) => notifier.setLanePan(
                sectionId: sectionId,
                laneId: lane.id,
                pan: v.abs() < _panSnapThreshold ? 0.0 : v,
              ),
            ),
          ),
        ],
      ),
    );
    return lane.muted ? Opacity(opacity: 0.45, child: strip) : strip;
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.child,
    this.trailing,
  });
  final String label;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: child,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            trailing ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}
