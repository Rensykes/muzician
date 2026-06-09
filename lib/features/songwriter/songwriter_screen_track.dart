/// Variant A — Track-Style (DAW-inspired).
///
/// Drops the per-section card wrapper. Each section is a header strip with
/// a thin left accent bar, full-width bar ruler, and lanes rendered as
/// secondary inset cards. Add-section is a FAB.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/muzician_theme.dart';
import '../_mockup_shell.dart';
import 'harmony_chord_sheet.dart';
import 'section_lyrics_sheet.dart';
import 'songwriter_block_tile.dart';
import 'songwriter_grid.dart';
import 'songwriter_header.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_structure_editor.dart';
import 'songwriter_undo.dart';

class SongwriterScreenTrack extends ConsumerWidget {
  const SongwriterScreenTrack({super.key});

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
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SongwriterHeader(
                  onOpenSaveLoad: () => _openSaveLoad(context),
                  onOpenStructure: () => _openStructure(context),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 96),
                    children: [
                      if (project.sections.isEmpty)
                        const _EmptyState(key: Key('songwriterEmptyHint')),
                      for (var i = 0; i < project.sections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 28),
                          child: _SectionBlock(
                            sectionId: project.sections[i].id,
                            accent: _sectionAccents[i % _sectionAccents.length],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: _AddSectionFab(
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
    );
  }
}

const List<Color> _sectionAccents = [
  MuzicianTheme.sky,
  MuzicianTheme.violet,
  MuzicianTheme.emerald,
  MuzicianTheme.orange,
];

class _SectionBlock extends ConsumerWidget {
  const _SectionBlock({required this.sectionId, required this.accent});
  final String sectionId;
  final Color accent;

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 4,
            bottom: 4,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(section: section, accent: accent),
                const SizedBox(height: 12),
                BarRuler(lengthBars: section.lengthBars, gutter: 0),
                const SizedBox(height: 6),
                for (final lane in section.lanes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LaneCard(
                      sectionId: sectionId,
                      laneId: lane.id,
                      lengthBars: section.lengthBars,
                      activeBar: activeLocalBar,
                      onRemove: () {
                        final s = ref
                            .read(songwriterProvider)
                            .sections
                            .firstWhere((x) => x.id == sectionId);
                        final idx =
                            s.lanes.indexWhere((l) => l.id == lane.id);
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
                  ),
                const SizedBox(height: 4),
                _AddLaneInline(
                  sectionId: sectionId,
                  onAddHarmony: () => notifier.addLane(
                    sectionId: sectionId,
                    kind: SongLaneKind.harmony,
                    label: 'Harmony',
                  ),
                  onAddSave: () => notifier.addLane(
                    sectionId: sectionId,
                    kind: SongLaneKind.save,
                    label: null,
                  ),
                  onAddDrum: () {
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
                      spanBars: section.lengthBars,
                    );
                  },
                ),
                const SizedBox(height: 6),
                _LyricsStrip(sectionId: section.id, lyrics: section.lyrics),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({required this.section, required this.accent});
  final SongSection section;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _editName(context, notifier),
            behavior: HitTestBehavior.opaque,
            child: Text(
              (section.label?.isNotEmpty ?? false)
                  ? section.label!.toUpperCase()
                  : 'SECTION',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _MetaText(
          key: Key('barsPill_${section.id}'),
          text: '${section.lengthBars} bars',
          onTap: () => _editLength(context, notifier, section),
        ),
        const SizedBox(width: 10),
        _MetaText(
          key: Key('repeatPill_${section.id}'),
          text: '${section.repeat}×',
          onTap: () => _editRepeat(context, notifier, section),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: Key('removeSection_${section.id}'),
          onPressed: () {
            final sections = ref.read(songwriterProvider).sections;
            final index = sections.indexWhere((s) => s.id == section.id);
            if (index < 0) return;
            final removed = sections[index];
            HapticFeedback.mediumImpact();
            notifier.removeSection(section.id);
            showUndoSnack(
              context,
              'Section deleted',
              () => notifier.insertSection(removed, index),
            );
          },
          icon: const Icon(
            Icons.close_rounded,
            size: 18,
            color: MuzicianTheme.textMuted,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 18,
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

  void _editLength(
    BuildContext context,
    SongwriterNotifier notifier,
    SongSection s,
  ) => _openStepper(
    context,
    title: 'Bars',
    value: s.lengthBars,
    min: 1,
    onChanged: (v) => notifier.setSectionLength(s.id, v),
  );

  void _editRepeat(
    BuildContext context,
    SongwriterNotifier notifier,
    SongSection s,
  ) => _openStepper(
    context,
    title: 'Repeat',
    value: s.repeat,
    min: 1,
    onChanged: (v) => notifier.setSectionRepeat(s.id, v),
  );
}

class _MetaText extends StatelessWidget {
  const _MetaText({super.key, required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: MuzicianTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LaneCard extends ConsumerWidget {
  const _LaneCard({
    required this.sectionId,
    required this.laneId,
    required this.lengthBars,
    required this.activeBar,
    required this.onRemove,
  });
  final String sectionId;
  final String laneId;
  final int lengthBars;
  final int? activeBar;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lane = ref.watch(
      songwriterProvider.select((p) {
        final s = p.sections.firstWhere(
          (s) => s.id == sectionId,
          orElse: () => const SongSection(id: '', lengthBars: 0, order: 0),
        );
        return s.lanes.firstWhere(
          (l) => l.id == laneId,
          orElse: () =>
              const SongLane(id: '', kind: SongLaneKind.save, order: 0),
        );
      }),
    );
    if (lane.id.isEmpty) return const SizedBox.shrink();
    final accent = switch (lane.kind) {
      SongLaneKind.harmony => MuzicianTheme.violet,
      SongLaneKind.save => MuzicianTheme.teal,
      SongLaneKind.drum => MuzicianTheme.orange,
    };
    final label = lane.label ??
        switch (lane.kind) {
          SongLaneKind.harmony => 'Harmony',
          SongLaneKind.save => 'Save',
          SongLaneKind.drum => 'Beat',
        };
    final bars = lengthBars < 1 ? 1 : lengthBars;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                key: Key('addBlock_$laneId'),
                onPressed: () => _addBlock(context, ref, lane),
                icon: Icon(Icons.add_rounded, size: 20, color: accent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 18,
              ),
              IconButton(
                key: Key('removeLane_$laneId'),
                onPressed: onRemove,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: MuzicianTheme.textMuted,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 14,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: SizedBox(
              height: 64,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth / bars;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BarGridPainter(
                            lengthBars: bars,
                            color: MuzicianTheme.glassBorder,
                          ),
                        ),
                      ),
                      for (final block in lane.blocks)
                        Positioned(
                          left: block.startBar * barWidth,
                          width: block.spanBars * barWidth,
                          top: 0,
                          bottom: 0,
                          child: SongwriterBlockTile(
                            sectionId: sectionId,
                            laneId: laneId,
                            blockId: block.id,
                            barWidth: barWidth,
                            highlighted: activeBar != null &&
                                activeBar! >= block.startBar &&
                                activeBar! < block.endBar,
                          ),
                        ),
                      if (activeBar != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: PlayheadPainter(
                                bar: activeBar!.toDouble(),
                                lengthBars: bars,
                                color: MuzicianTheme.sky.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addBlock(
    BuildContext context,
    WidgetRef ref,
    SongLane lane,
  ) async {
    final startBar = _nextFreeBar(lane, lengthBars);
    if (lane.kind == SongLaneKind.harmony) {
      final config = ref.read(songwriterProvider).config;
      final block = await showHarmonyChordSheet(
        context,
        startBar: startBar,
        spanBars: 2,
        keyRoot: config.keyRoot,
        keyScaleName: config.keyScaleName,
      );
      if (block != null) {
        ref.read(songwriterProvider.notifier).addHarmonyBlock(
              sectionId: sectionId,
              laneId: laneId,
              block: block,
            );
      }
    } else if (lane.kind == SongLaneKind.drum) {
      final notifier = ref.read(songwriterProvider.notifier);
      final patternId = notifier.addDrumPattern(name: 'Pattern');
      notifier.addDrumBlock(
        sectionId: sectionId,
        laneId: laneId,
        patternId: patternId,
        startBar: startBar,
        spanBars: 2,
      );
    }
    // Save-lane add is reachable via the lane row in the structure editor /
    // existing flow; we keep this variant focused on harmony for brevity.
  }

  int _nextFreeBar(SongLane lane, int lengthBars) {
    final occupied = <int>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        occupied.add(i);
      }
    }
    var bar = 0;
    while (bar < lengthBars && occupied.contains(bar)) {
      bar++;
    }
    return bar >= lengthBars ? 0 : bar;
  }
}

class _AddLaneInline extends StatelessWidget {
  const _AddLaneInline({
    required this.sectionId,
    required this.onAddHarmony,
    required this.onAddSave,
    required this.onAddDrum,
  });
  final String sectionId;
  final VoidCallback onAddHarmony;
  final VoidCallback onAddSave;
  final VoidCallback onAddDrum;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AddLaneChip(
          key: Key('addLane_$sectionId'),
          icon: Icons.music_note_rounded,
          label: 'Harmony',
          color: MuzicianTheme.violet,
          onTap: onAddHarmony,
        ),
        const SizedBox(width: 10),
        _AddLaneChip(
          icon: Icons.bookmark_outline_rounded,
          label: 'Save',
          color: MuzicianTheme.teal,
          onTap: onAddSave,
        ),
        const SizedBox(width: 10),
        _AddLaneChip(
          key: const Key('addDrumLaneAction'),
          icon: Icons.graphic_eq,
          label: 'Drum',
          color: MuzicianTheme.orange,
          onTap: onAddDrum,
        ),
      ],
    );
  }
}

class _AddLaneChip extends StatelessWidget {
  const _AddLaneChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSectionFab extends StatelessWidget {
  const _AddSectionFab({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: MuzicianTheme.sky,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: MuzicianTheme.sky.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                size: 20,
                color: MuzicianTheme.surface,
              ),
              SizedBox(width: 6),
              Text(
                'Section',
                style: TextStyle(
                  color: MuzicianTheme.surface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 72),
      child: Column(
        children: [
          Icon(
            Icons.timeline_rounded,
            size: 56,
            color: MuzicianTheme.sky.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'Start a track',
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the Section button to drop your first section. '
            'Add harmony lanes and arrange chord blocks on the bar grid.',
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

class _LyricsStrip extends ConsumerWidget {
  const _LyricsStrip({required this.sectionId, required this.lyrics});

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
    return GestureDetector(
      key: Key('trackLyrics_$sectionId'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          has ? lyrics! : '+ lyrics',
          style: TextStyle(
            color: has
                ? MuzicianTheme.textPrimary
                : MuzicianTheme.textPrimary.withValues(alpha: 0.4),
            fontStyle: has ? FontStyle.normal : FontStyle.italic,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
