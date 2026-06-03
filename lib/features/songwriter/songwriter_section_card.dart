import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import 'songwriter_grid.dart';
import 'songwriter_lane_row.dart';
import 'songwriter_undo.dart';

class SongwriterSectionCard extends ConsumerWidget {
  const SongwriterSectionCard({super.key, required this.sectionId});
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
    final notifier = ref.read(songwriterProvider.notifier);

    final globalBar = ref.watch(
      songwriterPlaybackProvider.select((s) => s.currentBar),
    );
    int? activeLocalBar;
    if (globalBar != null) {
      final expanded = expandSections(ref.read(songwriterProvider).sections);
      final hit = sectionAtGlobalBar(expanded, globalBar);
      if (hit != null && hit.section.sectionId == sectionId) {
        activeLocalBar = hit.localBar;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('sectionLabel_$sectionId'),
                    initialValue: section.label ?? '',
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Section name (optional)',
                      border: InputBorder.none,
                    ),
                    onFieldSubmitted: (v) =>
                        notifier.renameSection(sectionId, v.isEmpty ? null : v),
                  ),
                ),
                _ValuePill(
                  key: Key('barsPill_$sectionId'),
                  label: '${section.lengthBars} bars',
                  onTap: () => _openStepper(
                    context,
                    title: 'Bars',
                    value: section.lengthBars,
                    min: 1,
                    onChanged: (v) => notifier.setSectionLength(sectionId, v),
                  ),
                ),
                const SizedBox(width: 6),
                _ValuePill(
                  key: Key('repeatPill_$sectionId'),
                  label: '${section.repeat}×',
                  onTap: () => _openStepper(
                    context,
                    title: 'Repeat',
                    value: section.repeat,
                    min: 1,
                    onChanged: (v) => notifier.setSectionRepeat(sectionId, v),
                  ),
                ),
                IconButton(
                  key: Key('removeSection_$sectionId'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    final sections = ref.read(songwriterProvider).sections;
                    final index = sections.indexWhere((s) => s.id == sectionId);
                    if (index < 0) return;
                    final removed = sections[index];
                    notifier.removeSection(sectionId);
                    showUndoSnack(
                      context,
                      'Section deleted',
                      () => notifier.insertSection(removed, index),
                    );
                  },
                ),
              ],
            ),
            if (section.lanes.isNotEmpty)
              BarRuler(lengthBars: section.lengthBars, gutter: 72),
            for (final lane in section.lanes)
              Row(
                children: [
                  Expanded(
                    child: SongwriterLaneRow(
                      sectionId: sectionId,
                      laneId: lane.id,
                      activeBar: activeLocalBar,
                    ),
                  ),
                  IconButton(
                    key: Key('removeLane_${lane.id}'),
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      final s = ref
                          .read(songwriterProvider)
                          .sections
                          .firstWhere((x) => x.id == sectionId);
                      final idx = s.lanes.indexWhere((l) => l.id == lane.id);
                      if (idx < 0) return;
                      final removed = s.lanes[idx];
                      notifier.removeLane(
                        sectionId: sectionId,
                        laneId: lane.id,
                      );
                      showUndoSnack(
                        context,
                        'Lane deleted',
                        () => notifier.insertLane(
                          sectionId: sectionId,
                          lane: removed,
                          index: idx,
                        ),
                      );
                    },
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<SongLaneKind>(
                key: Key('addLane_$sectionId'),
                onSelected: (kind) => notifier.addLane(
                  sectionId: sectionId,
                  kind: kind,
                  label: kind == SongLaneKind.harmony ? 'Harmony' : null,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: SongLaneKind.harmony,
                    child: Text('+ Harmony lane'),
                  ),
                  PopupMenuItem(
                    value: SongLaneKind.save,
                    child: Text('+ Save lane'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('+ lane'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openStepper(
  BuildContext context, {
  required String title,
  required int value,
  required int min,
  required ValueChanged<int> onChanged,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _StepperDialog(
      title: title,
      initial: value,
      min: min,
      onChanged: onChanged,
    ),
  );
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label), const Icon(Icons.arrow_drop_down, size: 16)],
        ),
      ),
    );
  }
}

class _StepperDialog extends StatefulWidget {
  const _StepperDialog({
    required this.title,
    required this.initial,
    required this.min,
    required this.onChanged,
  });
  final String title;
  final int initial;
  final int min;
  final ValueChanged<int> onChanged;
  @override
  State<_StepperDialog> createState() => _StepperDialogState();
}

class _StepperDialogState extends State<_StepperDialog> {
  late int _v = widget.initial;
  void _set(int next) {
    if (next < widget.min) return;
    setState(() => _v = next);
    widget.onChanged(_v); // live-apply
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('stepperMinus'),
            icon: const Icon(Icons.remove),
            onPressed: () => _set(_v - 1),
          ),
          Text('$_v', style: Theme.of(context).textTheme.headlineSmall),
          IconButton(
            key: const Key('stepperPlus'),
            icon: const Icon(Icons.add),
            onPressed: () => _set(_v + 1),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
