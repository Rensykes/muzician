/// Per-section mixer: volume / pan / mute strip for every mix-owning lane in
/// a section (save lanes follow the primary harmony lane — see
/// [mixGoverningLane] — so they get no strip of their own).
///
/// Pure store UI — controls write through [SongwriterNotifier.setLaneVolume],
/// [SongwriterNotifier.setLanePan] and [SongwriterNotifier.setLaneMuted]; the
/// transport picks the values up on the next play (events and the audio clip
/// schedule are computed at start). Sliders keep the drag value locally and
/// commit to the store on release, so a drag doesn't rebuild the whole
/// songwriter screen per frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import '../_mockup_shell.dart';

/// Pan values closer to center than this snap to exactly 0.0.
const _panSnapThreshold = 0.08;

Future<void> showSongwriterMixerSheet(
  BuildContext context, {
  required String sectionId,
  String title = 'Mixer',
}) {
  return showWidgetSheet(
    context: context,
    title: title,
    child: SongwriterMixerSheet(sectionId: sectionId),
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

    final mixLanes = [
      for (final lane in section.lanes)
        if (mixGoverningLane(section, lane).id == lane.id) lane,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mixLanes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No lanes in this section yet.',
                  style: TextStyle(color: MuzicianTheme.textMuted),
                ),
              )
            else
              for (final lane in mixLanes)
                _MixerStrip(sectionId: sectionId, lane: lane),
          ],
        ),
      ),
    );
  }
}

class _MixerStrip extends ConsumerStatefulWidget {
  const _MixerStrip({required this.sectionId, required this.lane});
  final String sectionId;
  final SongLane lane;

  @override
  ConsumerState<_MixerStrip> createState() => _MixerStripState();
}

class _MixerStripState extends ConsumerState<_MixerStrip> {
  // Live drag values — shown while the finger is down, committed to the
  // store (one write) on release.
  double? _dragVolume;
  double? _dragPan;

  static IconData _kindIcon(SongLaneKind kind) => switch (kind) {
    SongLaneKind.harmony => Icons.piano,
    SongLaneKind.save => Icons.bookmark_outline,
    SongLaneKind.drum => Icons.graphic_eq,
    SongLaneKind.audio => Icons.mic,
  };

  static double _snapPan(double v) => v.abs() < _panSnapThreshold ? 0.0 : v;

  @override
  Widget build(BuildContext context) {
    final lane = widget.lane;
    final sectionId = widget.sectionId;
    final notifier = ref.read(songwriterProvider.notifier);
    final volume = _dragVolume ?? lane.volume;
    final pan = _dragPan ?? lane.pan;
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
                          lane.label ?? laneKindFallbackLabel(lane.kind),
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
              value: volume,
              onChanged: (v) => setState(() => _dragVolume = v),
              onChangeEnd: (v) {
                notifier.setLaneVolume(
                  sectionId: sectionId,
                  laneId: lane.id,
                  volume: v,
                );
                setState(() => _dragVolume = null);
              },
            ),
          ),
          _LabeledSlider(
            label: 'Pan',
            trailing: pan == 0.0
                ? 'C'
                : '${pan < 0 ? 'L' : 'R'}${(pan.abs() * 100).round()}',
            child: Slider(
              key: Key('mixerPan_${lane.id}'),
              min: -1.0,
              max: 1.0,
              value: pan,
              onChanged: (v) => setState(() => _dragPan = _snapPan(v)),
              onChangeEnd: (v) {
                notifier.setLanePan(
                  sectionId: sectionId,
                  laneId: lane.id,
                  pan: _snapPan(v),
                );
                setState(() => _dragPan = null);
              },
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
