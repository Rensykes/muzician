import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import 'songwriter_lane_row.dart';

class SongwriterSectionCard extends ConsumerWidget {
  const SongwriterSectionCard({super.key, required this.sectionId});
  final String sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(songwriterProvider.select(
      (p) => p.sections.firstWhere((s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0)),
    ));
    if (section.id.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(songwriterProvider.notifier);

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
                _Stepper(
                    label: 'bars',
                    value: section.lengthBars,
                    onChanged: (v) => notifier.setSectionLength(sectionId, v)),
                _Stepper(
                    label: '×',
                    value: section.repeat,
                    onChanged: (v) => notifier.setSectionRepeat(sectionId, v)),
                IconButton(
                  key: Key('removeSection_$sectionId'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => notifier.removeSection(sectionId),
                ),
              ],
            ),
            for (final lane in section.lanes)
              SongwriterLaneRow(sectionId: sectionId, laneId: lane.id),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<SongLaneKind>(
                key: Key('addLane_$sectionId'),
                onSelected: (kind) => notifier.addLane(
                    sectionId: sectionId,
                    kind: kind,
                    label: kind == SongLaneKind.harmony ? 'Harmony' : null),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: SongLaneKind.harmony, child: Text('+ Harmony lane')),
                  PopupMenuItem(value: SongLaneKind.save, child: Text('+ Save lane')),
                ],
                child: const Padding(padding: EdgeInsets.all(8), child: Text('+ lane')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: () => onChanged(value - 1)),
        Text('$value$label'),
        IconButton(icon: const Icon(Icons.add, size: 16), onPressed: () => onChanged(value + 1)),
      ],
    );
  }
}
