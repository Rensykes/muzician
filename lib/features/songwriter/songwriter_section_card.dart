import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../_mockup_shell.dart';
import 'section_lyrics_sheet.dart';
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

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 18),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuzicianTheme.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('sectionLabel_$sectionId'),
                  initialValue: section.label ?? '',
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Section name (optional)',
                    hintStyle: TextStyle(color: MuzicianTheme.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onFieldSubmitted: (v) =>
                      notifier.renameSection(sectionId, v.isEmpty ? null : v),
                ),
              ),
              IconBtn(
                key: Key('removeSection_$sectionId'),
                icon: Icons.close_rounded,
                color: MuzicianTheme.textSecondary,
                onTap: () {
                  final sections = ref.read(songwriterProvider).sections;
                  final index = sections.indexWhere((s) => s.id == sectionId);
                  if (index < 0) return;
                  final removed = sections[index];
                  HapticFeedback.mediumImpact();
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
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
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
                const SizedBox(width: 8),
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
              ],
            ),
          ),
          if (section.lanes.isNotEmpty) ...[
            const SizedBox(height: 16),
            BarRuler(lengthBars: section.lengthBars, gutter: 80),
          ],
          for (final lane in section.lanes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: SongwriterLaneRow(
                      sectionId: sectionId,
                      laneId: lane.id,
                      activeBar: activeLocalBar,
                    ),
                  ),
                  IconBtn(
                    key: Key('removeLane_${lane.id}'),
                    icon: Icons.close_rounded,
                    color: MuzicianTheme.textSecondary,
                    onTap: () {
                      final s = ref
                          .read(songwriterProvider)
                          .sections
                          .firstWhere((x) => x.id == sectionId);
                      final idx = s.lanes.indexWhere((l) => l.id == lane.id);
                      if (idx < 0) return;
                      final removed = s.lanes[idx];
                      HapticFeedback.lightImpact();
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
            ),
          const SizedBox(height: 16),
          _ClassicLyricsRow(sectionId: section.id, lyrics: section.lyrics),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              key: Key('addLane_$sectionId'),
              onTap: () => _showAddLaneSheet(context, notifier, sectionId, section.lengthBars),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: MuzicianTheme.emerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: MuzicianTheme.emerald.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: MuzicianTheme.emerald,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add lane',
                      style: TextStyle(
                        color: MuzicianTheme.emerald,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showAddLaneSheet(
  BuildContext context,
  SongwriterNotifier notifier,
  String sectionId,
  int lengthBars,
) {
  showWidgetSheet(
    context: context,
    title: 'Add lane',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LaneOptionTile(
          icon: Icons.music_note_rounded,
          label: 'Harmony lane',
          onTap: () {
            Navigator.pop(context);
            notifier.addLane(
              sectionId: sectionId,
              kind: SongLaneKind.harmony,
              label: 'Harmony',
            );
          },
        ),
        _LaneOptionTile(
          icon: Icons.save_rounded,
          label: 'Save lane',
          onTap: () {
            Navigator.pop(context);
            notifier.addLane(
              sectionId: sectionId,
              kind: SongLaneKind.save,
              label: null,
            );
          },
        ),
        _LaneOptionTile(
          key: const Key('addDrumLaneActionClassic'),
          icon: Icons.graphic_eq,
          label: 'Drum lane',
          onTap: () {
            Navigator.pop(context);
            final laneId = notifier.addLane(
              sectionId: sectionId,
              kind: SongLaneKind.drum,
              label: 'Beat',
            );
            final patternId = notifier.addDrumPattern(name: 'Pattern');
            notifier.addDrumBlock(
              sectionId: sectionId,
              laneId: laneId,
              patternId: patternId,
              startBar: 0,
              spanBars: lengthBars,
            );
          },
        ),
      ],
    ),
  );
}

class _LaneOptionTile extends StatelessWidget {
  const _LaneOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: MuzicianTheme.glassBorder)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: MuzicianTheme.textSecondary),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: MuzicianTheme.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MuzicianTheme.teal.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.teal,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: MuzicianTheme.teal,
              size: 18,
            ),
          ],
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
    widget.onChanged(_v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MuzicianTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconBtn(
                  key: const Key('stepperMinus'),
                  icon: Icons.remove_rounded,
                  onTap: () => _set(_v - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '$_v',
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconBtn(
                  key: const Key('stepperPlus'),
                  icon: Icons.add_rounded,
                  onTap: () => _set(_v + 1),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassicLyricsRow extends ConsumerWidget {
  const _ClassicLyricsRow({required this.sectionId, required this.lyrics});

  final String sectionId;
  final String? lyrics;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final next = await showSectionLyricsSheet(
      context: context,
      initial: lyrics,
    );
    ref.read(songwriterProvider.notifier).setSectionLyrics(sectionId, next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = lyrics != null && lyrics!.trim().isNotEmpty;
    return InkWell(
      onTap: () => _edit(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lyrics_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                has ? lyrics! : 'Add lyrics…',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: has ? FontStyle.normal : FontStyle.italic,
                  color: has
                      ? MuzicianTheme.textPrimary
                      : MuzicianTheme.textPrimary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
