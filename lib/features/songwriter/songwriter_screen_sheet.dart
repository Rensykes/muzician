/// Notation-Sheet (lead-sheet inspired) — the sole Writer layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import 'drum_pattern_sheet.dart';
import 'harmony_chord_sheet.dart';
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
        for (var i = 0; i < section.repeat.clamp(1, 32); i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == section.repeat - 1 ? 0 : 18),
            child: _SectionInstance(
              key: Key('sectionInstance_${section.id}_$i'),
              section: section,
              harmonyLane: harmonyLane,
              instanceIndex: i,
              keyRoot: config.keyRoot,
              keyScaleName: config.keyScaleName,
              onEnsureLane: () => notifier.addLane(
                sectionId: sectionId,
                kind: SongLaneKind.harmony,
                label: 'Harmony',
              ),
            ),
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

class _SectionInstance extends ConsumerWidget {
  const _SectionInstance({
    super.key,
    required this.section,
    required this.harmonyLane,
    required this.instanceIndex,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
  });

  final SongSection section;
  final SongLane harmonyLane;
  final int instanceIndex;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.repeat > 1)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '\u2014 ${instanceIndex + 1} of ${section.repeat} \u2014',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        _BarRow(
          section: section,
          lane: harmonyLane,
          instanceIndex: instanceIndex,
          keyRoot: keyRoot,
          keyScaleName: keyScaleName,
          onEnsureLane: onEnsureLane,
        ),
        // Drum lanes (one strip per drum lane on this section).
        for (final lane in section.lanes.where((l) => l.kind == SongLaneKind.drum)) ...[
          const SizedBox(height: 8),
          _DrumLaneRow(
            key: Key('sheetDrumLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
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
                  '\u00d7${section.repeat}',
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
          decoration: const InputDecoration(hintText: 'Verse, Chorus\u2026'),
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
    required this.instanceIndex,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
  });
  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final blockByStart = <int, SongBlock>{};
    final blockSpan = <int, SongBlock>{};
    for (final b in lane.blocks) {
      blockByStart[b.startBar] = b;
      for (var i = b.startBar; i < b.endBar; i++) {
        blockSpan[i] = b;
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
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
                instanceIndex: instanceIndex,
                onTap: () => _editBlock(context, ref, owner),
                onLongPress: () =>
                    _removeBlock(context, notifier, owner),
              ));
              i += span;
            } else if (owner != null) {
              i++;
            } else {
              cells.add(_BarCell(
                flex: 1,
                block: null,
                instanceIndex: instanceIndex,
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
      instanceIndex: instanceIndex,
      currentLyric: '',
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
    if (block.isSilent) {
      ref.read(songwriterProvider.notifier).addSilentBlock(
            sectionId: section.id,
            laneId: laneId,
            startBar: bar,
            spanBars: 1,
            verseCount: section.repeat.clamp(1, 16),
          );
      final newBlockId = ref
          .read(songwriterProvider)
          .sections
          .firstWhere((s) => s.id == section.id)
          .lanes
          .firstWhere((l) => l.id == laneId)
          .blocks
          .lastWhere((b) => b.startBar == bar)
          .id;
      if (block.lyrics.isNotEmpty) {
        ref.read(songwriterProvider.notifier).setBlockLyric(
              sectionId: section.id,
              laneId: laneId,
              blockId: newBlockId,
              verseIndex: instanceIndex,
              text: block.lyrics.first,
            );
      }
    } else {
      ref.read(songwriterProvider.notifier).addHarmonyBlock(
            sectionId: section.id,
            laneId: laneId,
            block: block,
          );
      if (block.lyrics.isNotEmpty) {
        ref.read(songwriterProvider.notifier).setBlockLyric(
              sectionId: section.id,
              laneId: laneId,
              blockId: block.id,
              verseIndex: instanceIndex,
              text: block.lyrics.first,
            );
      }
    }
  }

  Future<void> _editBlock(
    BuildContext context,
    WidgetRef ref,
    SongBlock block,
  ) async {
    final currentLyric = instanceIndex < block.lyrics.length
        ? block.lyrics[instanceIndex]
        : '';
    final next = await showHarmonyChordSheet(
      context,
      startBar: block.startBar,
      spanBars: block.spanBars,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
      existing: block,
      instanceIndex: instanceIndex,
      currentLyric: currentLyric,
    );
    if (next == null) return;
    HapticFeedback.selectionClick();
    // Write the lyric for this instance.
    ref.read(songwriterProvider.notifier).setBlockLyric(
          sectionId: section.id,
          laneId: lane.id,
          blockId: block.id,
          verseIndex: instanceIndex,
          text: next.lyrics.isNotEmpty ? next.lyrics.first : null,
        );
    // If chord state changed (non-silent), replace the block.
    if (!next.isSilent) {
      final n = ref.read(songwriterProvider.notifier);
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
    required this.instanceIndex,
    required this.onTap,
    this.onLongPress,
  });
  final int flex;
  final SongBlock? block;
  final int instanceIndex;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
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
            color: block != null
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (block == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '\u00b7',
                    style: TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 18,
                    ),
                  ),
                )
              else if (block!.isSilent)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    key: Key('silentCell_${block!.id}_$instanceIndex'),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: MuzicianTheme.textMuted,
                    ),
                  ),
                )
              else ...[
                const Spacer(),
                Text(
                  block!.chordSymbol ?? '?',
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
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
              if (block != null) ...[
                const SizedBox(height: 4),
                Text(
                  instanceIndex < block!.lyrics.length
                      ? block!.lyrics[instanceIndex]
                      : '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const Spacer(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DrumLaneRow extends ConsumerWidget {
  const _DrumLaneRow({
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
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final ownerByBar = <int, SongBlock>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        ownerByBar[i] = b;
      }
    }
    final patternsById = {
      for (final p in ref.read(songwriterProvider).drumPatterns) p.id: p,
    };
    return LayoutBuilder(
      builder: (context, _) {
        const perRow = 4;
        final rows = <List<Widget>>[];
        for (var start = 0; start < bars; start += perRow) {
          final end = (start + perRow).clamp(0, bars);
          final cells = <Widget>[];
          var i = start;
          while (i < end) {
            final owner = ownerByBar[i];
            if (owner != null && owner.startBar == i) {
              final span = owner.spanBars.clamp(1, end - i);
              final pattern = owner.patternId == null
                  ? null
                  : patternsById[owner.patternId];
              cells.add(Expanded(
                flex: span,
                child: GestureDetector(
                  key: Key(
                    'sheetDrumTile_${owner.patternId ?? owner.id}',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (owner.patternId == null) return;
                    showSongwriterDrumPatternSheet(
                      context: context,
                      patternId: owner.patternId!,
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MuzicianTheme.orange.withValues(alpha: 0.18),
                      border: Border.all(
                        color: MuzicianTheme.orange.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.graphic_eq,
                          size: 14,
                          color: MuzicianTheme.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            pattern?.name ?? 'pattern?',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MuzicianTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ));
              i += span;
            } else if (owner != null) {
              i++;
            } else {
              cells.add(Expanded(
                flex: 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: MuzicianTheme.glassBorder,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ));
              i++;
            }
          }
          rows.add(cells);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                lane.label ?? 'Beat',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            for (var r = 0; r < rows.length; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r == rows.length - 1 ? 0 : 6),
                child: Row(children: rows[r]),
              ),
          ],
        );
      },
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
            '$label \u00b7 $count',
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
