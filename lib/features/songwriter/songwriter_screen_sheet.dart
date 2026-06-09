/// Variant B — Notation-Sheet (lead-sheet inspired).
///
/// Drops cards entirely. Each section is a typographic chapter with a thin
/// rule. Bars are rendered as lead-sheet cells (`| C | F | G | C |`). Tapping
/// an empty cell opens the chord picker; tapping a filled cell offers
/// replace/delete. Save-lanes are not surfaced in this variant — Sheet mode
/// is harmony-only.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import 'harmony_chord_sheet.dart';
import 'section_lyrics_sheet.dart';
import 'songwriter_header.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_structure_editor.dart';
import 'songwriter_undo.dart';
import '../_mockup_shell.dart';

class SongwriterScreenSheet extends ConsumerWidget {
  const SongwriterScreenSheet({super.key});

  void _openSaveLoad(BuildContext context) {
    showWidgetSheet(
      context: context,
      title: 'Save / Load',
      child: const SongwriterSavePanel(),
    );
  }

  void _openStructure(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SongwriterStructureEditor(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: MuzicianTheme.gradientColors,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SongwriterHeader(
              onOpenSaveLoad: () => _openSaveLoad(context),
              onOpenStructure: () => _openStructure(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
                children: [
                  if (project.sections.isEmpty)
                    const _EmptyState(key: Key('songwriterEmptyHint')),
                  for (final section in project.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: _SectionSheet(sectionId: section.id),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _AddSectionRule(
                      key: const Key('songwriterAddSection'),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        notifier.addSection(label: null, lengthBars: 8);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionSheet extends ConsumerWidget {
  const _SectionSheet({required this.sectionId});
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
    final config = ref.watch(songwriterProvider.select((p) => p.config));

    final harmonyLane = section.lanes.firstWhere(
      (l) => l.kind == SongLaneKind.harmony,
      orElse: () => const SongLane(
        id: '',
        kind: SongLaneKind.harmony,
        order: 0,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(section: section),
        const SizedBox(height: 14),
        _BarRow(
          section: section,
          lane: harmonyLane,
          keyRoot: config.keyRoot,
          keyScaleName: config.keyScaleName,
          onEnsureLane: () => notifier.addLane(
            sectionId: sectionId,
            kind: SongLaneKind.harmony,
            label: 'Harmony',
          ),
        ),
        const SizedBox(height: 10),
        _LyricsBlock(
          sectionId: sectionId,
          lyrics: section.lyrics,
        ),
        if (section.lanes.any((l) => l.kind == SongLaneKind.save)) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final lane
                    in section.lanes.where((l) => l.kind == SongLaneKind.save))
                  _SaveLaneChip(
                    label: lane.label ?? 'Save',
                    count: lane.blocks.length,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends ConsumerWidget {
  const _SectionHeading({required this.section});
  final SongSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final title = (section.label?.isNotEmpty ?? false)
        ? section.label!.toUpperCase()
        : 'SECTION';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _editName(context, notifier),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              key: Key('barsPill_${section.id}'),
              onTap: () => _openStepper(
                context,
                title: 'Bars',
                value: section.lengthBars,
                min: 1,
                onChanged: (v) => notifier.setSectionLength(section.id, v),
              ),
              child: Text(
                '${section.lengthBars} bars',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (section.repeat > 1) ...[
              const SizedBox(width: 10),
              GestureDetector(
                key: Key('repeatPill_${section.id}'),
                onTap: () => _openStepper(
                  context,
                  title: 'Repeat',
                  value: section.repeat,
                  min: 1,
                  onChanged: (v) => notifier.setSectionRepeat(section.id, v),
                ),
                child: Text(
                  '×${section.repeat}',
                  style: const TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ] else
              GestureDetector(
                key: Key('repeatPill_${section.id}'),
                onTap: () => _openStepper(
                  context,
                  title: 'Repeat',
                  value: section.repeat,
                  min: 1,
                  onChanged: (v) => notifier.setSectionRepeat(section.id, v),
                ),
                child: const SizedBox(width: 24, height: 24),
              ),
            IconButton(
              key: Key('removeSection_${section.id}'),
              onPressed: () {
                final sections = ref.read(songwriterProvider).sections;
                final idx = sections.indexWhere((s) => s.id == section.id);
                if (idx < 0) return;
                final removed = sections[idx];
                HapticFeedback.mediumImpact();
                notifier.removeSection(section.id);
                showUndoSnack(
                  context,
                  'Section deleted',
                  () => notifier.insertSection(removed, idx),
                );
              },
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: MuzicianTheme.textMuted,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 1,
          color: MuzicianTheme.glassBorder,
        ),
      ],
    );
  }

  void _editName(BuildContext context, SongwriterNotifier notifier) {
    final controller = TextEditingController(text: section.label ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text(
          'Section name',
          style: TextStyle(color: MuzicianTheme.textPrimary),
        ),
        content: TextField(
          key: Key('sectionLabel_${section.id}'),
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Verse, Chorus…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notifier.renameSection(
                section.id,
                controller.text.isEmpty ? null : controller.text,
              );
              Navigator.pop(dialogCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends ConsumerWidget {
  const _BarRow({
    required this.section,
    required this.lane,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
  });
  final SongSection section;
  final SongLane lane;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final blockByStart = <int, SongBlock>{};
    final blockSpan = <int, SongBlock>{}; // each occupied bar → owning block
    for (final b in lane.blocks) {
      blockByStart[b.startBar] = b;
      for (var i = b.startBar; i < b.endBar; i++) {
        blockSpan[i] = b;
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wrap to 4 cells per row when narrow; up to 8 when wide.
        final perRow = constraints.maxWidth >= 360 ? 4 : 4;
        final rows = <List<Widget>>[];
        for (var start = 0; start < bars; start += perRow) {
          final cells = <Widget>[];
          final end = (start + perRow).clamp(0, bars);
          var i = start;
          while (i < end) {
            final owner = blockSpan[i];
            if (owner != null && owner.startBar == i) {
              final span = owner.spanBars.clamp(1, end - i);
              cells.add(_BarCell(
                flex: span,
                block: owner,
                onTap: () => _editBlock(context, ref, owner),
                onLongPress: () =>
                    _removeBlock(context, notifier, owner),
              ));
              i += span;
            } else if (owner != null) {
              i++; // covered by an earlier owner; skip silently.
            } else {
              cells.add(_BarCell(
                flex: 1,
                block: null,
                onTap: () => _addAt(context, ref, i),
              ));
              i++;
            }
          }
          rows.add(cells);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r == rows.length - 1 ? 0 : 8),
                child: Row(children: rows[r]),
              ),
          ],
        );
      },
    );
  }

  Future<void> _addAt(BuildContext context, WidgetRef ref, int bar) async {
    if (lane.id.isEmpty) {
      onEnsureLane();
    }
    final block = await showHarmonyChordSheet(
      context,
      startBar: bar,
      spanBars: 1,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
    );
    if (block == null) return;
    final laneId = lane.id.isEmpty
        ? ref
            .read(songwriterProvider)
            .sections
            .firstWhere((s) => s.id == section.id)
            .lanes
            .firstWhere((l) => l.kind == SongLaneKind.harmony)
            .id
        : lane.id;
    HapticFeedback.selectionClick();
    ref.read(songwriterProvider.notifier).addHarmonyBlock(
          sectionId: section.id,
          laneId: laneId,
          block: block,
        );
  }

  Future<void> _editBlock(
    BuildContext context,
    WidgetRef ref,
    SongBlock block,
  ) async {
    final next = await showHarmonyChordSheet(
      context,
      startBar: block.startBar,
      spanBars: block.spanBars,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
    );
    if (next == null) return;
    final n = ref.read(songwriterProvider.notifier);
    HapticFeedback.selectionClick();
    n.removeBlock(
      sectionId: section.id,
      laneId: lane.id,
      blockId: block.id,
    );
    n.addHarmonyBlock(
      sectionId: section.id,
      laneId: lane.id,
      block: next,
    );
  }

  void _removeBlock(
    BuildContext context,
    SongwriterNotifier notifier,
    SongBlock block,
  ) {
    HapticFeedback.lightImpact();
    notifier.removeBlock(
      sectionId: section.id,
      laneId: lane.id,
      blockId: block.id,
    );
    showUndoSnack(
      context,
      'Block removed',
      () => notifier.insertBlock(
        sectionId: section.id,
        laneId: lane.id,
        block: block,
      ),
    );
  }
}

class _BarCell extends StatelessWidget {
  const _BarCell({
    required this.flex,
    required this.block,
    required this.onTap,
    this.onLongPress,
  });
  final int flex;
  final SongBlock? block;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final filled = block != null;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 64,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: filled
                ? MuzicianTheme.violet.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: MuzicianTheme.textMuted.withValues(alpha: 0.4),
                width: 1.5,
              ),
              right: BorderSide(
                color: MuzicianTheme.textMuted.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
          ),
          child: filled
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      block!.chordSymbol ?? '?',
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((block!.romanNumeral ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        block!.romanNumeral!,
                        style: const TextStyle(
                          color: MuzicianTheme.violet,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                )
              : Center(
                  child: Text(
                    '·',
                    style: TextStyle(
                      color: MuzicianTheme.textMuted.withValues(alpha: 0.5),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SaveLaneChip extends StatelessWidget {
  const _SaveLaneChip({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MuzicianTheme.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bookmark_outline_rounded,
            size: 12,
            color: MuzicianTheme.teal,
          ),
          const SizedBox(width: 4),
          Text(
            '$label · $count',
            style: const TextStyle(
              color: MuzicianTheme.teal,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddSectionRule extends StatelessWidget {
  const _AddSectionRule({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: MuzicianTheme.glassBorder,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 16,
                    color: MuzicianTheme.sky,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Add section',
                    style: const TextStyle(
                      color: MuzicianTheme.sky,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: MuzicianTheme.glassBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 56,
            color: MuzicianTheme.sky.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'Blank sheet',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a section, then tap a bar to drop a chord.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
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
      backgroundColor: MuzicianTheme.surface,
      title: Text(
        widget.title,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBtn(
            key: const Key('stepperMinus'),
            icon: Icons.remove_rounded,
            onTap: () => _set(_v - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _LyricsBlock extends ConsumerWidget {
  const _LyricsBlock({required this.sectionId, required this.lyrics});

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
    if (!has) {
      return GestureDetector(
        key: const Key('sectionLyricsAdd'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _edit(context, ref),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            '+ lyrics',
            style: TextStyle(
              color: MuzicianTheme.textMuted,
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      key: Key('sectionLyrics_$sectionId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, left: 4, right: 4, bottom: 2),
        child: Text(
          lyrics!,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
