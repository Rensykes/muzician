import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart' show laneKindFallbackLabel;
import '../../store/save_system_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/muzician_dialog.dart';

class SongwriterLaneDeleteControl extends ConsumerWidget {
  const SongwriterLaneDeleteControl({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = lane.label ?? laneKindFallbackLabel(lane.kind);
    return IconButton(
      key: Key('deleteWriterLane_${lane.id}_$instanceIndex'),
      tooltip: 'Delete $label lane',
      icon: Icon(
        Icons.delete_outline,
        color: StudioPalette.of(context).textMuted,
      ),
      iconSize: 18,
      onPressed: () {
        final writer = ref.read(songwriterProvider.notifier);
        final container = ProviderScope.containerOf(context, listen: false);
        final projectId = container.read(saveSystemProvider).selectedProjectId;
        showStudioDialog<void>(
          context: context,
          builder: (context) => MuzicianDialog(
            titleWidget: Text(
              'Delete $label lane?',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            content: Text(
              'This lane and its contents will be removed from the section. Saved ideas remain available.',
              style: TextStyle(color: StudioPalette.of(context).textSecondary),
            ),
            actions: [
              MuzicianDialogButton(
                'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              MuzicianDialogButton(
                'Delete',
                key: const Key('confirmDeleteWriterLane'),
                emphasis: MuzicianDialogEmphasis.destructive,
                onPressed: () {
                  Navigator.of(context).pop();
                  if (container.read(saveSystemProvider).selectedProjectId !=
                      projectId) {
                    return;
                  }
                  HapticFeedback.mediumImpact();
                  writer.removeLane(sectionId: section.id, laneId: lane.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
