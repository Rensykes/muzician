/// Notation-Sheet (lead-sheet inspired) — the sole Writer layout.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../models/harmony_lane_instrument.dart';
import '../../schema/rules/save_system_rules.dart' show resolveSaveInProject;
import '../../schema/rules/songwriter_library_match_rules.dart';
import '../../schema/rules/songwriter_playback_rules.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../models/save_system.dart';
import '../../store/save_system_store.dart';
import '../../store/writer_save_binding_store.dart';
import '../../ui/save_card_label.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_stretch_controller.dart';
import 'writer_save_choice_dialog.dart';
import '../../store/songwriter_store.dart';
import '../../store/settings_store.dart';
import '../../ui/core/coach_overlay.dart';
import '../../ui/glass_snackbar.dart';
import '../../utils/note_utils.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'songwriter_block_preview.dart';
import 'songwriter_coach_steps.dart';
import 'songwriter_playhead.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import 'drum_pattern_sheet.dart';
import 'guitar_strum_pattern_sheet.dart';
import 'harmony_chord_sheet.dart';
import 'songwriter_header.dart';
import 'songwriter_mixer_sheet.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_structure_editor.dart';
import 'songwriter_undo.dart';
import '../_mockup_shell.dart';
import 'songwriter_audio_lane_row.dart';
import 'songwriter_section_ruler.dart';
import 'songwriter_melody_pattern_editor.dart';

class SongwriterScreenSheet extends ConsumerStatefulWidget {
  const SongwriterScreenSheet({
    super.key,
    this.onEditInstrumentSave,
    this.onEditMelodyPerformance,
  });

  final ValueChanged<SaveEntry>? onEditInstrumentSave;
  final ValueChanged<String>? onEditMelodyPerformance;

  @override
  ConsumerState<SongwriterScreenSheet> createState() =>
      _SongwriterScreenSheetState();
}

class _SongwriterScreenSheetState extends ConsumerState<SongwriterScreenSheet> {
  final _coachKeys = WriterCoachKeys();

  void _openSaveLoad(BuildContext context, {int initialTabIndex = 0}) {
    showWidgetSheet(
      context: context,
      title: 'Browse saves',
      scrollBody: false,
      child: SongwriterSavePanel(initialTabIndex: initialTabIndex),
    );
  }

  Future<void> _saveProject(BuildContext ctx) async {
    final projectId = ref.read(saveSystemProvider).selectedProjectId;
    if (projectId == null) return;
    final binding = ref.read(writerSaveBindingProvider)[projectId];
    final id = binding?.activeSaveId;
    SaveEntry? entry;
    if (id != null) {
      for (final s in ref.read(saveSystemProvider).saves) {
        if (s.id == id) {
          entry = s;
          break;
        }
      }
    }
    if (entry == null) {
      _openSaveLoad(ctx);
      return;
    }
    if (binding!.alwaysOverwrite) {
      await _overwrite(entry);
      return;
    }
    final choice = await showWriterSaveChoiceDialog(ctx, saveName: entry.name);
    if (!mounted) return;
    if (choice == null) return;
    if (choice.action == WriterSaveAction.saveAsNew) {
      // ignore: use_build_context_synchronously
      _openSaveLoad(context);
      return;
    }
    if (choice.dontAskAgain) {
      ref
          .read(writerSaveBindingProvider.notifier)
          .setAlwaysOverwrite(projectId, true);
    }
    await _overwrite(entry);
  }

  Future<void> _overwrite(SaveEntry entry) async {
    final saved = await ref
        .read(songwriterProvider.notifier)
        .overwriteNamedSave(entry.id);
    if (!mounted) return;
    if (!saved) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not save this Song version.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
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
  Widget build(BuildContext context) {
    ref.watch(songwriterStretchTempoWatcherProvider);
    final project = ref.watch(songwriterProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    final selectedProjectId = ref.watch(
      saveSystemProvider.select((saveState) => saveState.selectedProjectId),
    );
    final reconciliationConflicts = ref
        .watch(writerReconciliationConflictsProvider)
        .where((conflict) => conflict.projectId == selectedProjectId)
        .toList();
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
            KeyedSubtree(
              key: _coachKeys.header,
              child: SongwriterHeader(
                onOpenSaveLoad: () => _openSaveLoad(context),
                onOpenStructure: () => _openStructure(context),
                onStartTour: () =>
                    startCoachTour(context, writerCoachSteps(_coachKeys)),
                onSave: () => _saveProject(context),
              ),
            ),
            if (reconciliationConflicts.isNotEmpty && selectedProjectId != null)
              MaterialBanner(
                key: const Key('writerReconciliationConflictBanner'),
                backgroundColor: MuzicianTheme.orange.withValues(alpha: 0.10),
                forceActionsBelow: true,
                content: Text(
                  reconciliationConflicts.length == 1
                      ? 'A Writer block had two saved versions. Both were kept, and the arrangement uses the recovered version.'
                      : '${reconciliationConflicts.length} Writer blocks had two saved versions. Both were kept, and the arrangement uses the recovered versions.',
                  style: const TextStyle(color: MuzicianTheme.textPrimary),
                ),
                actions: [
                  TextButton(
                    key: const Key('writerReconciliationReviewSaves'),
                    onPressed: () async {
                      await notifier.acknowledgeWriterReconciliationConflicts(
                        selectedProjectId,
                      );
                      if (!context.mounted) return;
                      _openSaveLoad(context, initialTabIndex: 1);
                    },
                    child: const Text('Review both versions'),
                  ),
                ],
              ),
            Expanded(
              child: KeyedSubtree(
                key: _coachKeys.body,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 700;
                    final columnWidth = twoColumns
                        ? (constraints.maxWidth - 28 * 2 - 24) / 2
                        : null;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 80),
                      children: [
                        if (project.sections.isEmpty)
                          _EmptyState(
                            key: const Key('songwriterEmptyHint'),
                            onAddSection: () =>
                                notifier.addSection(label: null, lengthBars: 8),
                          ),
                        if (twoColumns)
                          // Wide layout: sections flow in two columns.
                          Wrap(
                            spacing: 24,
                            runSpacing: 36,
                            children: [
                              for (final section in project.sections)
                                SizedBox(
                                  width: columnWidth,
                                  child: _SectionSheet(
                                    sectionId: section.id,
                                    onEditInstrumentSave:
                                        widget.onEditInstrumentSave,
                                    onEditMelodyPerformance:
                                        widget.onEditMelodyPerformance,
                                  ),
                                ),
                            ],
                          )
                        else
                          for (final section in project.sections)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 36),
                              child: _SectionSheet(
                                sectionId: section.id,
                                onEditInstrumentSave:
                                    widget.onEditInstrumentSave,
                                onEditMelodyPerformance:
                                    widget.onEditMelodyPerformance,
                              ),
                            ),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: KeyedSubtree(
                            key: _coachKeys.addSection,
                            child: _AddSectionRule(
                              key: const Key('songwriterAddSection'),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                notifier.addSection(label: null, lengthBars: 8);
                              },
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
      ),
    );
  }
}

class _SectionSheet extends ConsumerWidget {
  const _SectionSheet({
    required this.sectionId,
    this.onEditInstrumentSave,
    this.onEditMelodyPerformance,
  });
  final String sectionId;
  final ValueChanged<SaveEntry>? onEditInstrumentSave;
  final ValueChanged<String>? onEditMelodyPerformance;

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

    var harmonyLanes = section.lanes
        .where((l) => l.kind == SongLaneKind.harmony)
        .toList();
    if (harmonyLanes.isEmpty) {
      // Placeholder so the empty bar grid still renders; the first chord tap
      // creates the real lane via onEnsureLane.
      harmonyLanes = const [
        SongLane(id: '', kind: SongLaneKind.harmony, order: 0),
      ];
    }

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
              onEditInstrumentSave: onEditInstrumentSave,
              onEditMelodyPerformance: onEditMelodyPerformance,
              harmonyLanes: harmonyLanes,
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
        // Save-lane blocks are rendered inline on the bar grid (badge over a
        // chord, or a standalone save cell), so no separate lane summary here.
      ],
    );
  }
}

class _SectionInstance extends ConsumerWidget {
  const _SectionInstance({
    super.key,
    required this.section,
    this.onEditInstrumentSave,
    this.onEditMelodyPerformance,
    required this.harmonyLanes,
    required this.instanceIndex,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
  });

  final SongSection section;
  final ValueChanged<SaveEntry>? onEditInstrumentSave;
  final ValueChanged<String>? onEditMelodyPerformance;
  final List<SongLane> harmonyLanes;
  final int instanceIndex;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(
      songwriterActivePositionProvider.select(
        (p) =>
            p != null &&
            p.sectionId == section.id &&
            p.instanceIndex == instanceIndex,
      ),
      (prev, next) {
        if (next && !(prev ?? false)) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.2,
          );
        }
      },
    );
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
        SongwriterSectionRuler(section: section, instanceIndex: instanceIndex),
        const SizedBox(height: 6),
        for (var li = 0; li < harmonyLanes.length; li++) ...[
          _HarmonyLaneHeader(
            section: section,
            lane: harmonyLanes[li],
            laneIndex: li,
          ),
          Padding(
            padding: EdgeInsets.only(
              bottom: li == harmonyLanes.length - 1 ? 0 : 8,
            ),
            child: _BarRow(
              section: section,
              onEditInstrumentSave: onEditInstrumentSave,
              lane: harmonyLanes[li],
              instanceIndex: instanceIndex,
              keyRoot: keyRoot,
              keyScaleName: keyScaleName,
              onEnsureLane: onEnsureLane,
              isPrimary: li == 0,
            ),
          ),
        ],
        for (final lane in section.lanes.where(
          (candidate) =>
              candidate.kind == SongLaneKind.save &&
              candidate.anchorLaneId != null &&
              saveAnchorLane(section, candidate) == null,
        )) ...[
          const SizedBox(height: 8),
          _UnresolvedSaveLaneRow(
            key: Key('unresolvedSaveLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
            onEditInstrumentSave: onEditInstrumentSave,
          ),
        ],
        // Drum lanes (one strip per drum lane on this section).
        for (final lane in section.lanes.where(
          (l) => l.kind == SongLaneKind.drum,
        )) ...[
          const SizedBox(height: 8),
          _DrumLaneRow(
            key: Key('sheetDrumLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
          ),
        ],
        for (final lane in section.lanes.where(
          (l) => l.kind == SongLaneKind.melody,
        )) ...[
          const SizedBox(height: 8),
          _PatternLaneRow(
            key: Key('sheetMelodyLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
            isMelody: true,
            onEditMelodyPerformance: onEditMelodyPerformance,
          ),
        ],
        for (final lane in section.lanes.where(
          (l) => l.kind == SongLaneKind.guitarStrum,
        )) ...[
          const SizedBox(height: 8),
          _PatternLaneRow(
            key: Key('sheetGuitarStrumLane_${lane.id}_$instanceIndex'),
            section: section,
            lane: lane,
            instanceIndex: instanceIndex,
            isMelody: false,
          ),
        ],
        // Audio lanes (one strip per audio lane on this section).
        for (final lane in section.lanes.where(
          (l) => l.kind == SongLaneKind.audio,
        ))
          Padding(
            key: Key('sheetAudioLane_${lane.id}_$instanceIndex'),
            padding: const EdgeInsets.only(top: 8),
            child: SongwriterAudioLaneRow(
              section: section,
              lane: lane,
              instanceIndex: instanceIndex,
              clipsById: {
                for (final c in ref.watch(
                  songwriterProvider.select((p) => p.audioClips),
                ))
                  c.id: c,
              },
              assetsById: {
                for (final a in ref.watch(
                  songwriterProvider.select((p) => p.audioAssets),
                ))
                  a.id: a,
              },
            ),
          ),
        // Free-text lyrics for this verse — decoupled from bars.
        const SizedBox(height: 8),
        _SectionLyrics(section: section, instanceIndex: instanceIndex),
      ],
    );
  }
}

class _UnresolvedSaveLaneRow extends ConsumerWidget {
  const _UnresolvedSaveLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    this.onEditInstrumentSave,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final ValueChanged<SaveEntry>? onEditInstrumentSave;

  void _showSaveBlockActions(
    BuildContext context,
    WidgetRef ref,
    SongBlock block,
  ) {
    final entry = writerSaveEntryForBlock(ref.read(saveSystemProvider), block);
    final canEditInstrumentSave =
        entry != null &&
        onEditInstrumentSave != null &&
        (entry.snapshot is FretboardSnapshot ||
            entry.snapshot is PianoSnapshot);
    showBarActionSheet(
      context: context,
      title: entry?.name ?? 'Missing Save',
      actions: [
        if (canEditInstrumentSave)
          BarAction(
            key: Key('unresolvedSaveEdit_${block.id}'),
            label: entry.snapshot is PianoSnapshot
                ? 'Edit in Piano'
                : 'Edit in Fretboard',
            icon: Icons.open_in_new,
            onTap: () => onEditInstrumentSave!(entry),
          ),
        BarAction(
          key: Key('unresolvedSaveRemove_${block.id}'),
          label: 'Remove save',
          icon: Icons.bookmark_remove,
          destructive: true,
          onTap: () => _removeSaveBlock(context, ref, block),
        ),
      ],
    );
  }

  void _removeSaveBlock(BuildContext context, WidgetRef ref, SongBlock block) {
    final notifier = ref.read(songwriterProvider.notifier);
    HapticFeedback.lightImpact();
    notifier.removeBlock(
      sectionId: section.id,
      laneId: lane.id,
      blockId: block.id,
    );
    final revision = notifier.historyRevision;
    showUndoSnack(
      context,
      'Save removed',
      historyRevision: notifier.historyRevisionListenable,
      expectedRevision: revision,
      onUndo: () => notifier.undo(ifRevision: revision),
    );
  }

  void _confirmRemoveLane(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Remove Save / Voicing lane?',
        content: const Text(
          'This removes the lane and its placements. The saved ideas remain in the project.',
          style: TextStyle(color: MuzicianTheme.textSecondary),
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          MuzicianDialogButton(
            'Remove lane',
            key: Key('confirmRemoveUnresolvedSaveLane_${lane.id}'),
            emphasis: MuzicianDialogEmphasis.destructive,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              HapticFeedback.mediumImpact();
              ref
                  .read(songwriterProvider.notifier)
                  .removeLane(sectionId: section.id, laneId: lane.id);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final saveState = ref.watch(saveSystemProvider);
    final allHarmonyLanes = section.lanes
        .where((candidate) => candidate.kind == SongLaneKind.harmony)
        .toList();
    final compatibleHarmonyLanes = allHarmonyLanes
        .where(
          (candidate) => notifier.canSetSaveLaneAnchorLane(
            sectionId: section.id,
            laneId: lane.id,
            harmonyLaneId: candidate.id,
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: MuzicianTheme.orange.withValues(alpha: 0.07),
        border: Border.all(color: MuzicianTheme.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.link_off, size: 13, color: MuzicianTheme.orange),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${lane.label ?? 'Save / Voicing'} · Unresolved Harmony anchor',
                  key: Key('unresolvedSaveLaneLabel_${lane.id}_$instanceIndex'),
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (compatibleHarmonyLanes.isNotEmpty)
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: Key('repairSaveAnchor_${lane.id}_$instanceIndex'),
                    value: null,
                    hint: const Text('Reanchor'),
                    isDense: true,
                    iconSize: 16,
                    dropdownColor: MuzicianTheme.surface,
                    style: const TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 10,
                    ),
                    items: [
                      for (
                        var index = 0;
                        index < allHarmonyLanes.length;
                        index++
                      )
                        if (compatibleHarmonyLanes.contains(
                          allHarmonyLanes[index],
                        ))
                          DropdownMenuItem(
                            key: Key(
                              'repairSaveAnchorOption_${lane.id}_${allHarmonyLanes[index].id}_$instanceIndex',
                            ),
                            value: allHarmonyLanes[index].id,
                            child: Text(
                              allHarmonyLanes[index].label ??
                                  harmonyLaneFallbackLabel(index),
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final primaryId = primaryHarmonyLane(section)?.id;
                      notifier.setLaneAnchorLane(
                        sectionId: section.id,
                        laneId: lane.id,
                        harmonyLaneId: value == primaryId ? null : value,
                      );
                    },
                  ),
                ),
            ],
          ),
          if (compatibleHarmonyLanes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No compatible Harmony lane',
                      style: TextStyle(
                        color: MuzicianTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: Key(
                      'removeUnresolvedSaveLane_${lane.id}_$instanceIndex',
                    ),
                    onPressed: () => _confirmRemoveLane(context, ref),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Remove lane'),
                    style: TextButton.styleFrom(
                      foregroundColor: MuzicianTheme.red,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          if (lane.blocks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 18, top: 4),
              child: Text(
                'No Save blocks',
                style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 10),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 18, top: 4),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final block in lane.blocks)
                    ActionChip(
                      key: Key(
                        'unresolvedSaveBlock_${block.id}_$instanceIndex',
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _showSaveBlockActions(context, ref, block),
                      label: Text(
                        'Bar ${block.startBar + 1} · ${writerSaveEntryForBlock(saveState, block)?.name ?? 'Missing Save'}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Free-text lyrics block for one verse (repeat instance) of a section.
/// Tapping opens a multi-line editor; the text is stored on the section, not
/// on any bar.
class _SectionLyrics extends ConsumerWidget {
  const _SectionLyrics({required this.section, required this.instanceIndex});

  final SongSection section;
  final int instanceIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = instanceIndex < section.lyrics.length
        ? section.lyrics[instanceIndex]
        : '';
    return GestureDetector(
      key: Key('sectionLyrics_${section.id}_$instanceIndex'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _edit(context, ref, text),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(left: 4, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: MuzicianTheme.sky.withValues(alpha: 0.10),
          border: Border.all(color: MuzicianTheme.sky.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1, right: 8),
              child: Icon(
                Icons.lyrics_outlined,
                size: 14,
                color: MuzicianTheme.textMuted,
              ),
            ),
            Expanded(
              child: Text(
                text.isEmpty ? 'Add lyrics…' : text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: text.isEmpty
                      ? MuzicianTheme.textMuted
                      : MuzicianTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, String current) {
    showDialog<void>(
      context: context,
      builder: (_) => _SectionLyricsDialog(
        initialText: current,
        onSave: (text) => ref
            .read(songwriterProvider.notifier)
            .setSectionLyric(
              sectionId: section.id,
              verseIndex: instanceIndex,
              text: text,
            ),
      ),
    );
  }
}

class _SectionLyricsDialog extends StatefulWidget {
  const _SectionLyricsDialog({required this.initialText, required this.onSave});
  final String initialText;
  final ValueChanged<String> onSave;

  @override
  State<_SectionLyricsDialog> createState() => _SectionLyricsDialogState();
}

class _SectionLyricsDialogState extends State<_SectionLyricsDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: 'Lyrics',
      content: TextField(
        key: const Key('sectionLyricsField'),
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 3,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Type the lyrics…'),
      ),
      actions: [
        MuzicianDialogButton('Cancel', onPressed: () => Navigator.pop(context)),
        MuzicianDialogButton(
          'Save',
          buttonKey: const Key('sectionLyricsSave'),
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _VerseLyricDialog extends StatefulWidget {
  const _VerseLyricDialog({
    required this.verseNumber,
    required this.initialText,
    required this.onSave,
  });
  final int verseNumber;
  final String initialText;
  final ValueChanged<String> onSave;

  @override
  State<_VerseLyricDialog> createState() => _VerseLyricDialogState();
}

class _VerseLyricDialogState extends State<_VerseLyricDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: 'Lyrics — Verse ${widget.verseNumber}',
      content: TextField(
        key: const Key('verseLyricField'),
        controller: _controller,
        autofocus: true,
        maxLines: null,
        minLines: 2,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Words for this verse…'),
      ),
      actions: [
        MuzicianDialogButton('Cancel', onPressed: () => Navigator.pop(context)),
        MuzicianDialogButton(
          'Save',
          buttonKey: const Key('verseLyricSave'),
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () {
            widget.onSave(_controller.text);
            Navigator.pop(context);
          },
        ),
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
    final canAddGuitarStrumLane = notifier.canAddGuitarStrumLane(section.id);
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
            const SizedBox(width: 10),
            // Always-visible repeat control: \u00d7N tiles the section into N verses.
            // Muted at \u00d71 so it stays discoverable; accented once repeated.
            GestureDetector(
              key: Key('repeatPill_${section.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _openStepper(
                context,
                title: 'Verses',
                value: section.repeat,
                min: 1,
                onChanged: (v) => notifier.setSectionRepeat(section.id, v),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Text(
                  '\u00d7${section.repeat}',
                  style: TextStyle(
                    color: section.repeat > 1
                        ? MuzicianTheme.sky
                        : MuzicianTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              key: Key('sectionMixer_${section.id}'),
              tooltip: 'Mixer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.tune,
                size: 18,
                color: MuzicianTheme.textPrimary,
              ),
              onPressed: () => showSongwriterMixerSheet(
                context,
                sectionId: section.id,
                title: 'Mixer — ${section.label ?? 'Section'}',
              ),
            ),
            PopupMenuButton<String>(
              key: Key('sheetSectionMenu_${section.id}'),
              icon: const Icon(
                Icons.more_vert,
                color: MuzicianTheme.textPrimary,
              ),
              onSelected: (value) async {
                if (value == 'addHarmonyLane') {
                  final instrument = await _promptHarmonyLaneInstrument(
                    context,
                  );
                  if (instrument == null || !context.mounted) return;
                  final harmonyCount = ref
                      .read(songwriterProvider)
                      .sections
                      .firstWhere((s) => s.id == section.id)
                      .lanes
                      .where((l) => l.kind == SongLaneKind.harmony)
                      .length;
                  ref
                      .read(songwriterProvider.notifier)
                      .addHarmonyLane(
                        sectionId: section.id,
                        harmonyInstrument: instrument,
                        label: harmonyLaneFallbackLabel(harmonyCount),
                      );
                }
                if (value == 'addDrumLane') {
                  final notifier = ref.read(songwriterProvider.notifier);
                  notifier.runHistoryGroup(() {
                    notifier.addLane(
                      sectionId: section.id,
                      kind: SongLaneKind.drum,
                      label: 'Beat',
                    );
                    final laneId = ref
                        .read(songwriterProvider)
                        .sections
                        .firstWhere((s) => s.id == section.id)
                        .lanes
                        .lastWhere((l) => l.kind == SongLaneKind.drum)
                        .id;
                    final patternId = notifier.addDrumPattern(name: 'Pattern');
                    notifier.addDrumBlock(
                      sectionId: section.id,
                      laneId: laneId,
                      patternId: patternId,
                      startBar: 0,
                      spanBars: section.lengthBars,
                    );
                  });
                }
                if (value == 'addAudioLane') {
                  ref
                      .read(songwriterProvider.notifier)
                      .addLane(
                        sectionId: section.id,
                        kind: SongLaneKind.audio,
                        label: 'Sample',
                      );
                }
                if (value == 'addMelodyLane') {
                  final notifier = ref.read(songwriterProvider.notifier);
                  notifier.runHistoryGroup(() {
                    final laneId = notifier.addLane(
                      sectionId: section.id,
                      kind: SongLaneKind.melody,
                      label: 'Melody',
                    );
                    final patternId = notifier.addMelodyPattern(
                      name: 'Melody',
                      lengthTicks: ref
                          .read(songwriterProvider)
                          .config
                          .measureTicks,
                    );
                    notifier.addMelodyBlock(
                      sectionId: section.id,
                      laneId: laneId,
                      patternId: patternId,
                      startBar: 0,
                      spanBars: section.lengthBars,
                    );
                  });
                }
                if (value == 'addGuitarStrumLane') {
                  final notifier = ref.read(songwriterProvider.notifier);
                  notifier.runHistoryGroup(() {
                    final laneId = notifier.addLane(
                      sectionId: section.id,
                      kind: SongLaneKind.guitarStrum,
                      label: 'Guitar Strum',
                    );
                    if (laneId.isEmpty) return;
                    final patternId = notifier.addGuitarStrumPattern(
                      name: 'Strum',
                      lengthTicks: ref
                          .read(songwriterProvider)
                          .config
                          .measureTicks,
                    );
                    notifier.addGuitarStrumBlock(
                      sectionId: section.id,
                      laneId: laneId,
                      patternId: patternId,
                      startBar: 0,
                      spanBars: section.lengthBars,
                    );
                  });
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  key: Key('addHarmonyLaneSheetAction'),
                  value: 'addHarmonyLane',
                  child: ListTile(
                    leading: Icon(Icons.piano),
                    title: Text('Add harmony lane'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  key: Key('addDrumLaneSheetAction'),
                  value: 'addDrumLane',
                  child: ListTile(
                    leading: Icon(Icons.graphic_eq),
                    title: Text('Add drum lane'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  key: Key('addAudioLaneSheetAction'),
                  value: 'addAudioLane',
                  child: ListTile(
                    leading: Icon(Icons.mic),
                    title: Text('Add audio lane'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  key: Key('addMelodyLaneSheetAction'),
                  value: 'addMelodyLane',
                  child: ListTile(
                    leading: Icon(Icons.music_note),
                    title: Text('Add melody lane'),
                    dense: true,
                  ),
                ),
                if (canAddGuitarStrumLane)
                  const PopupMenuItem(
                    key: Key('addGuitarStrumLaneSheetAction'),
                    value: 'addGuitarStrumLane',
                    child: ListTile(
                      leading: Icon(Icons.music_note_outlined),
                      title: Text('Add guitar strum lane'),
                      dense: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              key: Key('removeSection_${section.id}'),
              onPressed: () {
                final sections = ref.read(songwriterProvider).sections;
                final idx = sections.indexWhere((s) => s.id == section.id);
                if (idx < 0) return;
                HapticFeedback.mediumImpact();
                notifier.removeSection(section.id);
                final revision = notifier.historyRevision;
                showUndoSnack(
                  context,
                  'Section deleted',
                  historyRevision: notifier.historyRevisionListenable,
                  expectedRevision: revision,
                  onUndo: () => notifier.undo(ifRevision: revision),
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
        Container(height: 1, color: MuzicianTheme.glassBorder),
      ],
    );
  }

  void _editName(BuildContext context, SongwriterNotifier notifier) {
    final controller = TextEditingController(text: section.label ?? '');
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => MuzicianDialog(
        title: 'Section name',
        content: TextField(
          key: Key('sectionLabel_${section.id}'),
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Verse, Chorus\u2026'),
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          MuzicianDialogButton(
            'Save',
            emphasis: MuzicianDialogEmphasis.primary,
            onPressed: () {
              notifier.renameSection(
                section.id,
                controller.text.isEmpty ? null : controller.text,
              );
              Navigator.pop(dialogCtx);
            },
          ),
        ],
      ),
    );
  }
}

/// One row in the unified bar action sheet. [onTap] runs after the sheet has
/// closed.
class BarAction {
  const BarAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.key,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Key? key;
  final bool destructive;
}

/// Single, non-destructive entrypoint for a bar: a bottom sheet listing
/// [actions]. Tapping a row closes the sheet, then invokes its callback.
Future<void> showBarActionSheet({
  required BuildContext context,
  required String title,
  required List<BarAction> actions,
}) {
  return showWidgetSheet(
    context: context,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in actions)
          ListTile(
            key: a.key,
            leading: Icon(
              a.icon,
              color: a.destructive
                  ? MuzicianTheme.red
                  : MuzicianTheme.textPrimary,
            ),
            title: Text(
              a.label,
              style: TextStyle(
                color: a.destructive
                    ? MuzicianTheme.red
                    : MuzicianTheme.textPrimary,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              a.onTap();
            },
          ),
      ],
    ),
  );
}

/// Label row above a harmony lane's bar grid, shown only when the section has
/// more than one harmony lane. Secondary lanes get a delete action.
class _HarmonyLaneHeader extends ConsumerWidget {
  const _HarmonyLaneHeader({
    required this.section,
    required this.lane,
    required this.laneIndex,
  });
  final SongSection section;
  final SongLane lane;
  final int laneIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = lane.label ?? harmonyLaneFallbackLabel(laneIndex);
    final instrument = lane.id.isEmpty
        ? ref
              .read(songwriterProvider.notifier)
              .projectDefaultHarmonyInstrumentForSelectedProject
        : lane.harmonyInstrument;
    final instrumentLabel = switch (instrument) {
      HarmonyLaneInstrument.fretboard => 'Fretboard',
      HarmonyLaneInstrument.piano => 'Piano',
      null => 'Instrument needed',
    };
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 280;
          return Row(
            children: [
              if (!compact) ...[
                Icon(
                  switch (instrument) {
                    HarmonyLaneInstrument.piano => Icons.piano,
                    HarmonyLaneInstrument.fretboard => Icons.music_note,
                    null => Icons.help_outline,
                  },
                  size: 12,
                  color: MuzicianTheme.textMuted,
                ),
                const SizedBox(width: 5),
              ],
              GestureDetector(
                key: Key('renameHarmonyLane_${lane.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: lane.id.isEmpty
                    ? null
                    : () => showLaneRenameDialog(
                        context,
                        ref,
                        sectionId: section.id,
                        lane: lane,
                      ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                key: Key('harmonyLaneInstrument_${lane.id}'),
                label: '$instrumentLabel Harmony instrument',
                child: Text(
                  instrumentLabel,
                  style: const TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (lane.id.isNotEmpty &&
                  ref
                      .read(songwriterProvider.notifier)
                      .canChangeHarmonyLaneInstrument(
                        sectionId: section.id,
                        laneId: lane.id,
                      ))
                IconButton(
                  key: Key('changeHarmonyLaneInstrument_${lane.id}'),
                  tooltip: 'Change Harmony instrument',
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  icon: const Icon(
                    Icons.swap_horiz,
                    color: MuzicianTheme.textMuted,
                  ),
                  onPressed: () async {
                    final instrument = await _promptHarmonyLaneInstrument(
                      context,
                    );
                    if (instrument == null || !context.mounted) return;
                    final changed = ref
                        .read(songwriterProvider.notifier)
                        .setHarmonyLaneInstrument(
                          sectionId: section.id,
                          laneId: lane.id,
                          instrument: instrument,
                        );
                    if (!changed) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This lane or one of its linked voicings changed.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              if (lane.id.isNotEmpty)
                IconButton(
                  key: Key('duplicateHarmonyLane_${lane.id}'),
                  tooltip: 'Duplicate Harmony lane',
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  icon: const Icon(
                    Icons.copy_all_outlined,
                    color: MuzicianTheme.textMuted,
                  ),
                  onPressed: () => ref
                      .read(songwriterProvider.notifier)
                      .duplicateHarmonyLane(
                        sectionId: section.id,
                        laneId: lane.id,
                      ),
                ),
              if (lane.id.isNotEmpty && laneIndex > 0)
                IconButton(
                  key: Key('deleteHarmonyLane_${lane.id}'),
                  tooltip: 'Delete Harmony lane',
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: MuzicianTheme.textMuted,
                  ),
                  onPressed: () => _confirmDelete(context, ref, label),
                ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String label) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => MuzicianDialog(
        title: 'Delete $label?',
        content: const Text(
          'The chords in this lane and any Save / Voicing lanes anchored to it are removed.',
          key: Key('deleteHarmonyLaneImpact'),
          style: TextStyle(color: MuzicianTheme.textSecondary),
        ),
        actions: [
          MuzicianDialogButton(
            'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          MuzicianDialogButton(
            'Delete',
            key: const Key('confirmDeleteHarmonyLane'),
            emphasis: MuzicianDialogEmphasis.destructive,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              HapticFeedback.mediumImpact();
              ref
                  .read(songwriterProvider.notifier)
                  .removeLane(sectionId: section.id, laneId: lane.id);
            },
          ),
        ],
      ),
    );
  }
}

Future<HarmonyLaneInstrument?> _promptHarmonyLaneInstrument(
  BuildContext context,
) => showModalBottomSheet<HarmonyLaneInstrument>(
  context: context,
  backgroundColor: MuzicianTheme.surface,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a Harmony instrument',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'All chords in this lane will use the selected instrument.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          for (final instrument in HarmonyLaneInstrument.values)
            ListTile(
              key: Key('harmonyInstrumentOption_${instrument.name}'),
              leading: Icon(
                instrument == HarmonyLaneInstrument.piano
                    ? Icons.piano
                    : Icons.music_note,
                color: MuzicianTheme.sky,
              ),
              title: Text(
                instrument == HarmonyLaneInstrument.piano
                    ? 'Piano'
                    : 'Fretboard',
              ),
              onTap: () => Navigator.of(context).pop(instrument),
            ),
          TextButton(
            key: const Key('harmonyInstrumentCancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  ),
);

class _BarRow extends ConsumerWidget {
  const _BarRow({
    required this.section,
    this.onEditInstrumentSave,
    required this.lane,
    required this.instanceIndex,
    required this.keyRoot,
    required this.keyScaleName,
    required this.onEnsureLane,
    this.isPrimary = true,
  });
  final SongSection section;
  final ValueChanged<SaveEntry>? onEditInstrumentSave;
  final SongLane lane;
  final int instanceIndex;
  final int? keyRoot;
  final String? keyScaleName;
  final VoidCallback onEnsureLane;

  /// True for the section's first harmony lane. Lyric affordances and inline
  /// save badges render only on the primary lane; extra harmony lanes are
  /// pure chord layers.
  final bool isPrimary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final saveState = ref.watch(saveSystemProvider);
    final bars = section.lengthBars < 1 ? 1 : section.lengthBars;
    final activeBar = ref.watch(
      songwriterActivePositionProvider.select(
        (p) =>
            p != null &&
                p.sectionId == section.id &&
                p.instanceIndex == instanceIndex
            ? p.localBar
            : null,
      ),
    );
    bool isActiveCell(int startBar, int span) =>
        activeBar != null &&
        activeBar >= startBar &&
        activeBar < startBar + span;
    Key? activeKey(int startBar, int span) => isActiveCell(startBar, span)
        ? Key('activeBarCell_${section.id}_${instanceIndex}_$startBar')
        : null;
    final blockByStart = <int, SongBlock>{};
    final blockSpan = <int, SongBlock>{};
    for (final b in lane.blocks) {
      blockByStart[b.startBar] = b;
      for (var i = b.startBar; i < b.endBar; i++) {
        blockSpan[i] = b;
      }
    }
    // Save-lane blocks are surfaced inline on the bar grid: as a badge over the
    // chord that shares the bar, or as a standalone save cell on an empty bar.
    // Each save lane renders on its anchor harmony lane's row (legacy
    // anchor-less save lanes resolve to the primary lane).
    final saveBySpan = <int, SongBlock>{};
    for (final l in _anchoredSaveLanes()) {
      for (final b in l.blocks) {
        for (var i = b.startBar; i < b.endBar; i++) {
          saveBySpan[i] = b;
        }
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
              final save = saveBySpan[i];
              cells.add(
                _BarCell(
                  key: activeKey(i, span),
                  flex: span,
                  block: owner,
                  blockName: writerSaveEntryForBlock(saveState, owner)?.name,
                  brokenReference:
                      owner.saveId != null &&
                      writerSaveEntryForBlock(saveState, owner) == null,
                  semanticsLabel: _barCellSemanticsLabel(
                    owner,
                    writerSaveEntryForBlock(saveState, owner)?.name,
                    i,
                  ),
                  onBrokenDelete: () => notifier.removeBlock(
                    sectionId: section.id,
                    laneId: lane.id,
                    blockId: owner.id,
                  ),
                  saveBlock: save,
                  saveName: save == null
                      ? null
                      : writerSaveEntryForBlock(saveState, save)?.name,
                  saveIcon: save == null
                      ? Icons.bookmark
                      : _saveIcon(ref, save),
                  instanceIndex: instanceIndex,
                  isActive: isActiveCell(i, span),
                  onTap: () => _onTapBlock(context, ref, owner),
                  onSaveTap: save == null
                      ? null
                      : () => _onTapSave(
                          context,
                          ref,
                          save,
                          onEditInstrumentSave: onEditInstrumentSave,
                        ),
                  onLongPress: () => _removeBlock(context, notifier, owner),
                ),
              );
              i += span;
            } else if (owner != null) {
              i++;
            } else if (saveBySpan[i] != null) {
              // Standalone save (placed on a bar with no chord). Render it as a
              // save cell spanning its bars; tap removes it (with undo).
              final save = saveBySpan[i]!;
              if (save.startBar == i) {
                final span = save.spanBars.clamp(1, end - i);
                cells.add(
                  _BarCell(
                    key: Key('saveCell_${save.id}_$instanceIndex'),
                    flex: span,
                    block: null,
                    saveBlock: save,
                    saveName:
                        writerSaveEntryForBlock(saveState, save)?.name ??
                        _saveName(ref, save),
                    brokenReference:
                        save.saveId != null &&
                        writerSaveEntryForBlock(saveState, save) == null,
                    semanticsLabel: _barCellSemanticsLabel(
                      save,
                      writerSaveEntryForBlock(saveState, save)?.name,
                      i,
                    ),
                    onBrokenDelete: () => _removeSave(context, ref, save),
                    saveIcon: _saveIcon(ref, save),
                    saveRoman: _saveRoman(ref, save),
                    instanceIndex: instanceIndex,
                    isActive: isActiveCell(i, span),
                    onTap: () => _onTapSave(
                      context,
                      ref,
                      save,
                      onEditInstrumentSave: onEditInstrumentSave,
                    ),
                    onLongPress: () => _removeSave(context, ref, save),
                  ),
                );
                i += span;
              } else {
                i++; // covered by a spanning save that started earlier
              }
            } else {
              // Snapshot `i` — it is mutated by this while-loop, so a closure
              // capturing it directly would read its post-loop value (`end`),
              // landing every empty-cell tap on the start of the next row.
              final bar = i;
              cells.add(
                _BarCell(
                  key: activeKey(bar, 1),
                  flex: 1,
                  block: null,
                  instanceIndex: instanceIndex,
                  isActive: isActiveCell(bar, 1),
                  semanticsLabel: 'Empty bar ${bar + 1}',
                  onTap: () => _onTapEmpty(context, ref, bar),
                ),
              );
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
                child: Stack(
                  children: [
                    Row(children: rows[r]),
                    Positioned.fill(
                      child: SongwriterRowPlayhead(
                        sectionId: section.id,
                        instanceIndex: instanceIndex,
                        rowStartBar: r * perRow,
                        barsInRow: (bars - r * perRow).clamp(1, perRow),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Save lanes whose voicings belong to this row's harmony lane. Anchor-less
  /// save lanes follow the primary lane; stale explicit anchors stay in their
  /// own unresolved row instead of falling back to primary.
  List<SongLane> _anchoredSaveLanes() {
    final out = <SongLane>[];
    for (final l in section.lanes) {
      if (l.kind != SongLaneKind.save) continue;
      final anchor = saveAnchorLane(section, l);
      if (l.anchorLaneId != null && anchor == null) continue;
      final belongsHere = anchor == null ? isPrimary : anchor.id == lane.id;
      if (belongsHere) out.add(l);
    }
    return out;
  }

  void _playFromBar(WidgetRef ref, int bar) {
    final project = ref.read(songwriterProvider);
    final tick = sectionBarGlobalTick(
      project.sections,
      project.config,
      section.id,
      bar,
      instanceIndex: instanceIndex,
    );
    final pb = ref.read(songwriterPlaybackProvider.notifier);
    pb.stopPlayback();
    unawaited(pb.startPlayback(startTick: tick));
  }

  void _onTapEmpty(BuildContext context, WidgetRef ref, int bar) {
    showBarActionSheet(
      context: context,
      title: 'Bar ${bar + 1}',
      actions: [
        BarAction(
          key: const Key('barActionPlayFromHere'),
          label: 'Play from here',
          icon: Icons.play_arrow,
          onTap: () => _playFromBar(ref, bar),
        ),
        BarAction(
          key: const Key('barActionAddChord'),
          label: 'Add chord',
          icon: Icons.piano,
          onTap: () => _addAt(context, ref, bar),
        ),
        BarAction(
          key: const Key('barActionAddLibrary'),
          label: 'Add from library',
          icon: Icons.library_music,
          onTap: () => _pickFromLibrary(context, ref, bar),
        ),
      ],
    );
  }

  Future<void> _addAt(BuildContext context, WidgetRef ref, int bar) async {
    final block = await showHarmonyChordSheet(
      context,
      startBar: bar,
      spanBars: 1,
      keyRoot: keyRoot,
      keyScaleName: keyScaleName,
      instanceIndex: instanceIndex,
      currentLyric: '',
      showLyrics: isPrimary,
      onPickFromLibrary: () => _pickFromLibrary(context, ref, bar),
    );
    if (block == null) return;
    HapticFeedback.selectionClick();
    final notifier = ref.read(songwriterProvider.notifier);
    notifier.runHistoryGroup(() {
      if (block.isSilent && lane.id.isEmpty) onEnsureLane();
      final laneId = lane.id.isNotEmpty
          ? lane.id
          : ref
                .read(songwriterProvider)
                .sections
                .where((s) => s.id == section.id)
                .expand((s) => s.lanes)
                .where((l) => l.kind == SongLaneKind.harmony)
                .firstOrNull
                ?.id;
      if (block.isSilent) {
        if (laneId == null || laneId.isEmpty) return;
        notifier.addSilentBlock(
          sectionId: section.id,
          laneId: laneId,
          startBar: bar,
          spanBars: 1,
          verseCount: section.repeat.clamp(1, 16),
        );
        final newBlockId = ref
            .read(songwriterProvider)
            .sections
            .where((s) => s.id == section.id)
            .expand((s) => s.lanes)
            .where((l) => l.id == laneId)
            .expand((l) => l.blocks)
            .where((b) => b.startBar == bar)
            .lastOrNull
            ?.id;
        if (isPrimary && block.lyrics.isNotEmpty && newBlockId != null) {
          notifier.setBlockLyric(
            sectionId: section.id,
            laneId: laneId,
            blockId: newBlockId,
            verseIndex: instanceIndex,
            text: block.lyrics.first,
          );
        }
      } else {
        final result = notifier.addHarmonyChord(
          sectionId: section.id,
          laneId: lane.id.isEmpty ? null : lane.id,
          block: block,
          saveName: block.chordSymbol,
        );
        if (!result.success) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Could not add this Harmony chord.',
              ),
            ),
          );
          return;
        }
        if (isPrimary && block.lyrics.isNotEmpty) {
          final placedLaneId = ref
              .read(songwriterProvider)
              .sections
              .where((candidate) => candidate.id == section.id)
              .expand((candidate) => candidate.lanes)
              .where((candidate) => candidate.kind == SongLaneKind.harmony)
              .firstWhere(
                (candidate) => candidate.blocks.any(
                  (candidateBlock) => candidateBlock.id == result.blockId,
                ),
              )
              .id;
          notifier.setBlockLyric(
            sectionId: section.id,
            laneId: placedLaneId,
            blockId: result.blockId!,
            verseIndex: instanceIndex,
            text: block.lyrics.first,
          );
        }
      }
    });
  }

  /// Tap on a placed block → unified, non-destructive action sheet.
  void _onTapBlock(BuildContext context, WidgetRef ref, SongBlock block) {
    final notifier = ref.read(songwriterProvider.notifier);
    final entry = writerSaveEntryForBlock(ref.read(saveSystemProvider), block);
    final isChord =
        !block.isSilent &&
        block.chordRootPc != null &&
        block.chordQuality != null;
    final harmonySave = entry?.snapshot;
    final save = _anchoredSaveLanes()
        .expand((l) => l.blocks)
        .where((b) => b.startBar < block.endBar && block.startBar < b.endBar)
        .firstOrNull;

    showBarActionSheet(
      context: context,
      title: isChord ? (block.chordSymbol ?? 'Chord') : 'Bar',
      actions: [
        BarAction(
          key: const Key('barActionPlayFromHere'),
          label: 'Play from here',
          icon: Icons.play_arrow,
          onTap: () => _playFromBar(ref, block.startBar),
        ),
        if (isChord)
          BarAction(
            key: const Key('barActionChangeChord'),
            label: 'Change chord',
            icon: Icons.edit,
            onTap: () => _editBlock(context, ref, block),
          ),
        if (isChord)
          BarAction(
            key: const Key('barActionVoicings'),
            label: 'Voicings & library',
            icon: Icons.library_music,
            onTap: () => _openHarmonyTools(context, ref, block),
          ),
        if (isChord)
          BarAction(
            key: const Key('barActionReplaceChord'),
            label: 'Replace chord',
            icon: Icons.swap_horiz,
            onTap: () => _replaceChord(context, ref, block),
          ),
        if (harmonySave is HarmonyChordSnapshot && onEditInstrumentSave != null)
          BarAction(
            key: const Key('barActionEditInstrument'),
            label: harmonySave.harmonyInstrument == HarmonyLaneInstrument.piano
                ? 'Edit in Piano'
                : 'Edit in Fretboard',
            icon: Icons.open_in_new,
            onTap: () => onEditInstrumentSave!(entry!),
          ),
        if (isPrimary)
          BarAction(
            key: const Key('barActionLyrics'),
            label: 'Lyrics — Verse ${instanceIndex + 1}',
            icon: Icons.lyrics_outlined,
            onTap: () => _editVerseLyric(context, ref, block),
          ),
        if (entry != null) ...[
          BarAction(
            key: const Key('barActionRenameBlock'),
            label: 'Rename',
            icon: Icons.drive_file_rename_outline,
            onTap: () => renameWriterBlockSave(context, ref, entry),
          ),
          if (harmonySave is HarmonyChordSnapshot)
            BarAction(
              key: const Key('barActionCreateStandaloneSave'),
              label: 'Create standalone Save',
              icon: Icons.copy_all_outlined,
              onTap: () =>
                  createStandaloneHarmonySaveFromBlock(context, ref, entry),
            )
          else if (lane.kind != SongLaneKind.harmony)
            BarAction(
              key: const Key('barActionMakeBlockUnique'),
              label: 'Make Unique',
              icon: Icons.copy_all_outlined,
              onTap: () => makeWriterBlockUnique(
                context,
                ref,
                section: section,
                lane: lane,
                block: block,
                entry: entry,
              ),
            ),
        ],
        if (block.saveId != null && entry == null)
          BarAction(
            key: const Key('barActionBrokenReference'),
            label: 'Broken save reference',
            icon: Icons.link_off,
            onTap: () => showBrokenReferenceSheet(
              context,
              onDelete: () => notifier.removeBlock(
                sectionId: section.id,
                laneId: lane.id,
                blockId: block.id,
              ),
            ),
          ),
        if (save != null)
          BarAction(
            key: const Key('barActionRemoveSave'),
            label: 'Remove save',
            icon: Icons.bookmark_remove,
            destructive: true,
            onTap: () => _removeSave(context, ref, save),
          ),
        BarAction(
          key: const Key('barActionRemove'),
          label: isChord ? 'Remove chord' : 'Remove',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () => _removeBlock(context, notifier, block),
        ),
      ],
    );
  }

  /// Opens the voicings / harmony / library sheet for a chord block (with an
  /// "Edit chord & lyrics" escape hatch).
  void _openHarmonyTools(BuildContext context, WidgetRef ref, SongBlock block) {
    final cfg = ref.read(songwriterProvider).config;
    final notifier = ref.read(songwriterProvider.notifier);
    final harmonyInstrument = notifier.harmonyInstrumentForLane(
      sectionId: section.id,
      laneId: lane.id,
    );
    final voicings = harmonyInstrument == HarmonyLaneInstrument.fretboard
        ? suggestVoicings(
            chordRootPc: block.chordRootPc!,
            quality: block.chordQuality!,
          )
        : const <VoicingSuggestion>[];
    final thirdAbove = suggestThirdAbove(
      chordRootPc: block.chordRootPc!,
      chordQuality: block.chordQuality!,
      chordTonePcs: _chordPcs(block),
      keyRootPc: cfg.keyRoot,
      keyScaleName: cfg.keyScaleName,
    );
    final compatibleThirdAbove =
        harmonyInstrument == HarmonyLaneInstrument.piano ? thirdAbove : null;
    final matches = matchLibrary(
      harmonyBlock: block,
      searchableSaves: notifier
          .searchableSavesForLibraryMatch()
          .where(
            (save) =>
                save.snapshot is! HarmonyChordSnapshot &&
                save.snapshot.instrument == harmonyInstrument?.name,
          )
          .toList(),
      keyRootPc: cfg.keyRoot,
      keyScaleName: cfg.keyScaleName,
    );

    showHarmonyBlockSheet(
      context,
      block: block,
      voicings: voicings,
      thirdAbove: compatibleThirdAbove,
      chordMatches: matches.chordMatches,
      onAcceptVoicing: (v) => notifier.acceptVoicingSuggestion(
        sectionId: section.id,
        harmonyBlockId: block.id,
        suggestion: v,
      ),
      onAcceptThirdAbove: (s) => notifier.acceptThirdAboveSuggestion(
        sectionId: section.id,
        harmonyBlockId: block.id,
        suggestion: s,
      ),
      onAcceptLibrary: (saveId) => notifier.acceptLibraryMatch(
        sectionId: section.id,
        harmonyBlockId: block.id,
        saveId: saveId,
      ),
      onEditChord: () => _editBlock(context, ref, block),
      editChordLabel: isPrimary ? 'Edit chord & lyrics' : 'Edit chord',
    );
  }

  List<int> _chordPcs(SongBlock block) {
    final out = <int>[];
    for (final name in block.chordNotes) {
      final pc = noteToPC[name];
      if (pc != null && !out.contains(pc)) out.add(pc);
    }
    return out;
  }

  /// Opens the project save browser (piano / fretboard / piano-roll voicings)
  /// and drops the chosen save as a save-lane block at [bar] — no chord wheel.
  void _pickFromLibrary(BuildContext context, WidgetRef ref, int bar) {
    final selId = ref.read(saveSystemProvider).selectedProjectId;
    if (selId == null) {
      showGlassSnackbar(
        context,
        title: 'No project',
        message: 'Select a project to browse its library.',
        contentType: ContentType.warning,
      );
      return;
    }
    final harmonyInstrument = ref
        .read(songwriterProvider.notifier)
        .harmonyInstrumentForLane(
          sectionId: section.id,
          laneId: lane.id.isEmpty ? null : lane.id,
        );
    if (harmonyInstrument == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Choose an instrument for this lane.')),
      );
      return;
    }
    _showCompatibleHarmonySaves(
      context: context,
      ref: ref,
      title: 'Harmony library',
      instrument: harmonyInstrument,
      onPick: (entry) {
        HapticFeedback.selectionClick();
        final inserted = ref
            .read(songwriterProvider.notifier)
            .insertWriterBlockFromSave(
              saveId: entry.id,
              sectionId: section.id,
              laneKind: SongLaneKind.harmony,
              laneId: lane.id.isEmpty ? null : lane.id,
              startBar: bar,
            );
        if (!inserted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Could not add this Harmony save.')),
          );
        }
      },
    );
  }

  void _replaceChord(BuildContext context, WidgetRef ref, SongBlock block) {
    final instrument = ref
        .read(songwriterProvider.notifier)
        .harmonyInstrumentForLane(sectionId: section.id, laneId: lane.id);
    if (instrument == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Choose an instrument for this lane.')),
      );
      return;
    }
    _showCompatibleHarmonySaves(
      context: context,
      ref: ref,
      title: 'Replace chord',
      instrument: instrument,
      onPick: (entry) {
        final replaced = ref
            .read(songwriterProvider.notifier)
            .replaceHarmonyBlockWithSave(
              sectionId: section.id,
              laneId: lane.id,
              blockId: block.id,
              saveId: entry.id,
            );
        if (!replaced) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Choose a Harmony save made for this instrument.'),
            ),
          );
        }
      },
    );
  }

  void _showCompatibleHarmonySaves({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required HarmonyLaneInstrument instrument,
    required ValueChanged<SaveEntry> onPick,
  }) {
    final saveState = ref.read(saveSystemProvider);
    final projectId = saveState.selectedProjectId;
    if (projectId == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Select a project to browse Harmony saves.'),
        ),
      );
      return;
    }
    final entries =
        saveState.saves
            .where(
              (entry) =>
                  entry.snapshot is HarmonyChordSnapshot &&
                  (entry.snapshot as HarmonyChordSnapshot).harmonyInstrument ==
                      instrument &&
                  resolveSaveInProject(saveState, projectId, entry.id) != null,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    showWidgetSheet(
      context: context,
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No ${instrument.name == 'piano' ? 'Piano' : 'Fretboard'} Harmony saves yet.',
                style: const TextStyle(color: MuzicianTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final entry in entries)
              ListTile(
                key: Key('harmonyLibrarySave_${entry.id}'),
                leading: Icon(
                  instrument == HarmonyLaneInstrument.piano
                      ? Icons.piano
                      : Icons.music_note,
                  color: MuzicianTheme.violet,
                ),
                title: Text(entry.name),
                subtitle: Text(
                  (entry.snapshot as HarmonyChordSnapshot)
                          .writerBlock
                          .chordSymbol ??
                      'Harmony chord',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onPick(entry);
                },
              ),
        ],
      ),
    );
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
      showLyrics: isPrimary,
    );
    if (next == null) return;
    HapticFeedback.selectionClick();
    final notifier = ref.read(songwriterProvider.notifier);
    final updated = notifier.updateHarmonyBlock(
      sectionId: section.id,
      laneId: lane.id,
      blockId: block.id,
      content: next,
      lyricVerseIndex: isPrimary ? instanceIndex : null,
    );
    if (!updated && context.mounted) {
      showGlassSnackbar(
        context,
        title: 'Chord not updated',
        message:
            notifier.lastHarmonyMutationError ??
            'Could not update this chord. Change the Fretboard tuning, capo, or fret range and try again.',
        contentType: ContentType.warning,
      );
    }
  }

  /// Edits the per-verse lyric of [block]. [laneId] defaults to this row's
  /// harmony lane, but a save block lives in its own save lane, so callers pass
  /// that lane's id explicitly.
  void _editVerseLyric(
    BuildContext context,
    WidgetRef ref,
    SongBlock block, {
    String? laneId,
  }) {
    final targetLaneId = laneId ?? lane.id;
    final current = instanceIndex < block.lyrics.length
        ? block.lyrics[instanceIndex]
        : '';
    showDialog<void>(
      context: context,
      builder: (_) => _VerseLyricDialog(
        verseNumber: instanceIndex + 1,
        initialText: current,
        onSave: (text) => ref
            .read(songwriterProvider.notifier)
            .setBlockLyric(
              sectionId: section.id,
              laneId: targetLaneId,
              blockId: block.id,
              verseIndex: instanceIndex,
              text: text,
            ),
      ),
    );
  }

  /// Resolves the save lane that owns [save], or empty id if none.
  String _saveLaneId(SongBlock save) => section.lanes
      .firstWhere(
        (l) =>
            l.kind == SongLaneKind.save && l.blocks.any((b) => b.id == save.id),
        orElse: () => const SongLane(id: '', kind: SongLaneKind.save, order: 0),
      )
      .id;

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
    final revision = notifier.historyRevision;
    showUndoSnack(
      context,
      'Block removed',
      historyRevision: notifier.historyRevisionListenable,
      expectedRevision: revision,
      onUndo: () => notifier.undo(ifRevision: revision),
    );
  }

  /// Display name for a save block, resolved from the save system; falls back
  /// to 'Save' when the referenced entry is missing.
  String _saveName(WidgetRef ref, SongBlock save) {
    return writerSaveEntryForBlock(ref.read(saveSystemProvider), save)?.name ??
        'Save';
  }

  SongLane? _saveLane(SongBlock save) => section.lanes
      .where(
        (candidate) =>
            candidate.kind == SongLaneKind.save &&
            candidate.blocks.any((block) => block.id == save.id),
      )
      .firstOrNull;

  /// Instrument icon for a save block: piano for a piano save, guitar
  /// (music note) for a fretboard save. Falls back to a bookmark when the
  /// referenced save can't be resolved.
  IconData _saveIcon(WidgetRef ref, SongBlock save) {
    final saveState = ref.read(saveSystemProvider);
    final snapshot = resolveBlockSnapshot(
      save,
      saveState.saves,
      projectId: saveState.selectedProjectId,
      folders: saveState.folders,
    );
    if (snapshot == null) return Icons.bookmark;
    return saveInstrumentIcon(snapshot.instrument);
  }

  /// Roman numeral for a save block: resolves the save's snapshot to a chord
  /// (explicit pending chord or detected from its notes) and maps it to the
  /// project key. Null when no chord resolves or it is non-diatonic.
  String? _saveRoman(WidgetRef ref, SongBlock save) {
    final saveState = ref.read(saveSystemProvider);
    final snapshot = resolveBlockSnapshot(
      save,
      saveState.saves,
      projectId: saveState.selectedProjectId,
      folders: saveState.folders,
    );
    return saveBlockRomanNumeral(snapshot, keyRoot, keyScaleName);
  }

  void _onTapSave(
    BuildContext context,
    WidgetRef ref,
    SongBlock save, {
    ValueChanged<SaveEntry>? onEditInstrumentSave,
  }) {
    final entry = writerSaveEntryForBlock(ref.read(saveSystemProvider), save);
    final saveLane = _saveLane(save);
    // Replace-from-library is intentionally omitted for now: addLibraryBlockAt
    // rejects a placement that overlaps the existing save, so a "replace" would
    // silently no-op. It belongs with the upcoming forced-save flow. Tap stays
    // non-destructive (menu); removal is an explicit item or a long-press.
    showBarActionSheet(
      context: context,
      title: _saveName(ref, save),
      actions: [
        BarAction(
          key: const Key('barActionLyrics'),
          label: 'Lyrics — Verse ${instanceIndex + 1}',
          icon: Icons.lyrics_outlined,
          onTap: () =>
              _editVerseLyric(context, ref, save, laneId: _saveLaneId(save)),
        ),
        if (entry != null &&
            (entry.snapshot is FretboardSnapshot ||
                entry.snapshot is PianoSnapshot) &&
            onEditInstrumentSave != null)
          BarAction(
            key: const Key('barActionEditInstrument'),
            label: entry.snapshot is PianoSnapshot
                ? 'Edit in Piano'
                : 'Edit in Fretboard',
            icon: Icons.open_in_new,
            onTap: () => onEditInstrumentSave(entry),
          ),
        if (entry != null)
          BarAction(
            key: const Key('barActionRenameBlock'),
            label: 'Rename',
            icon: Icons.drive_file_rename_outline,
            onTap: () => renameWriterBlockSave(context, ref, entry),
          ),
        if (entry != null && saveLane != null)
          BarAction(
            key: const Key('barActionMakeBlockUnique'),
            label: 'Make Unique',
            icon: Icons.copy_all_outlined,
            onTap: () => makeWriterBlockUnique(
              context,
              ref,
              section: section,
              lane: saveLane,
              block: save,
              entry: entry,
            ),
          ),
        if (save.saveId != null && entry == null)
          BarAction(
            key: const Key('barActionBrokenReference'),
            label: 'Broken save reference',
            icon: Icons.link_off,
            onTap: () => showBrokenReferenceSheet(
              context,
              onDelete: () => _removeSave(context, ref, save),
            ),
          ),
        BarAction(
          key: const Key('barActionRemoveSave'),
          label: 'Remove save',
          icon: Icons.bookmark_remove,
          destructive: true,
          onTap: () => _removeSave(context, ref, save),
        ),
      ],
    );
  }

  /// Removes a save block (its badge on a chord, or a standalone save cell)
  /// from the save lane, with an undo affordance.
  void _removeSave(BuildContext context, WidgetRef ref, SongBlock save) {
    final notifier = ref.read(songwriterProvider.notifier);
    final saveLaneId = _saveLaneId(save);
    if (saveLaneId.isEmpty) return;
    HapticFeedback.lightImpact();
    notifier.removeBlock(
      sectionId: section.id,
      laneId: saveLaneId,
      blockId: save.id,
    );
    final revision = notifier.historyRevision;
    showUndoSnack(
      context,
      'Save removed',
      historyRevision: notifier.historyRevisionListenable,
      expectedRevision: revision,
      onUndo: () => notifier.undo(ifRevision: revision),
    );
  }
}

class _BarCell extends StatelessWidget {
  const _BarCell({
    super.key,
    required this.flex,
    required this.block,
    required this.instanceIndex,
    required this.onTap,
    required this.semanticsLabel,
    this.blockName,
    this.brokenReference = false,
    this.onBrokenDelete,
    this.saveBlock,
    this.saveName,
    this.saveIcon = Icons.bookmark,
    this.saveRoman,
    this.onSaveTap,
    this.onLongPress,
    this.isActive = false,
  });
  final int flex;
  final SongBlock? block;
  final String? blockName;
  final bool brokenReference;
  final VoidCallback? onBrokenDelete;
  final SongBlock? saveBlock;
  final String? saveName;
  final IconData saveIcon;
  final String? saveRoman;
  final int instanceIndex;
  final VoidCallback onTap;
  final String semanticsLabel;
  final VoidCallback? onSaveTap;
  final VoidCallback? onLongPress;
  final bool isActive;

  bool get _isSaveOnly => block == null && saveBlock != null;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        explicitChildNodes: true,
        label: semanticsLabel,
        hint: 'Open block actions',
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 64,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isActive
                  ? MuzicianTheme.violet.withValues(alpha: 0.34)
                  : (block != null
                        ? MuzicianTheme.violet.withValues(alpha: 0.18)
                        : _isSaveOnly
                        ? MuzicianTheme.sky.withValues(alpha: 0.14)
                        : Colors.transparent),
              border: Border(
                left: BorderSide(
                  color: isActive
                      ? MuzicianTheme.violet
                      : _isSaveOnly
                      ? MuzicianTheme.sky.withValues(alpha: 0.5)
                      : MuzicianTheme.textMuted.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                right: BorderSide(
                  color: isActive
                      ? MuzicianTheme.violet
                      : _isSaveOnly
                      ? MuzicianTheme.sky.withValues(alpha: 0.5)
                      : MuzicianTheme.textMuted.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _content()),
                // Badge marking a save that shares the bar with a chord. Its own
                // tap target so it opens the save action menu directly, instead of
                // the chord's menu.
                if (block != null && saveBlock != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      key: Key('saveBadge_${saveBlock!.id}_$instanceIndex'),
                      tooltip:
                          'Open actions for ${saveName ?? 'attached save'}',
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onSaveTap,
                      icon: Icon(saveIcon, size: 16, color: MuzicianTheme.sky),
                    ),
                  ),
                if (brokenReference && block != null)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: writerBrokenReferenceAction(
                      context,
                      block: block!,
                      onDelete: onBrokenDelete ?? onTap,
                    ),
                  ),
                if (brokenReference && block == null && saveBlock != null)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: writerBrokenReferenceAction(
                      context,
                      block: saveBlock!,
                      onDelete: onBrokenDelete ?? onTap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_isSaveOnly) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(saveIcon, size: 16, color: MuzicianTheme.sky),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              saveName ?? 'Save',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
          if ((saveRoman ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              saveRoman!,
              key: Key('saveRoman_${saveBlock!.id}_$instanceIndex'),
              style: const TextStyle(
                color: MuzicianTheme.violet,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
          if (instanceIndex < saveBlock!.lyrics.length &&
              saveBlock!.lyrics[instanceIndex].isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                saveBlock!.lyrics[instanceIndex],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (block == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '\u00b7',
              style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 18),
            ),
          )
        else if (block!.isSilent)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                key: Key('silentCell_${block!.id}_$instanceIndex'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: MuzicianTheme.textMuted,
                ),
              ),
              if (blockName != null && blockName!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    blockName!,
                    key: Key('writerBlockName_${block!.id}_$instanceIndex'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
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
          if (blockName != null &&
              blockName!.isNotEmpty &&
              blockName != block!.chordSymbol) ...[
            const SizedBox(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                blockName!,
                key: Key('writerBlockName_${block!.id}_$instanceIndex'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MuzicianTheme.textSecondary,
                  fontSize: 9,
                  height: 1.1,
                ),
              ),
            ),
          ],
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const Spacer(),
        ],
      ],
    );
  }
}

String _barCellSemanticsLabel(SongBlock block, String? name, int startBar) {
  final label =
      name ?? block.chordSymbol ?? (block.isSilent ? 'Silence' : 'Block');
  final broken = block.saveId != null && name == null
      ? ', broken save reference'
      : '';
  return '$label, bar ${startBar + 1}$broken';
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
    final saveState = ref.watch(saveSystemProvider);
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
      builder: (context, constraints) {
        const perRow = 4;
        final narrowCells = constraints.maxWidth / perRow < 90;
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
              final saveEntry = writerSaveEntryForBlock(saveState, owner);
              final displayName =
                  saveEntry?.name ?? pattern?.name ?? 'pattern?';
              final hasBrokenReference =
                  owner.saveId != null && saveEntry == null;
              cells.add(
                Expanded(
                  flex: span,
                  child: Semantics(
                    button: true,
                    explicitChildNodes: true,
                    label: 'Edit drum pattern $displayName',
                    hint: 'Open block actions',
                    child: GestureDetector(
                      key: Key('sheetDrumTile_${owner.patternId ?? owner.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (owner.patternId == null) return;
                        showSongwriterDrumPatternSheet(
                          context: context,
                          patternId: owner.patternId!,
                          sectionId: section.id,
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
                            if (!narrowCells) ...[
                              const Icon(
                                Icons.graphic_eq,
                                size: 14,
                                color: MuzicianTheme.textPrimary,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                displayName,
                                key: Key(
                                  'writerBlockName_${owner.id}_$instanceIndex',
                                ),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: MuzicianTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (saveEntry != null)
                              writerLinkedBlockActionsMenu(
                                context,
                                ref,
                                section: section,
                                lane: lane,
                                block: owner,
                                entry: saveEntry,
                              ),
                            if (hasBrokenReference)
                              writerBrokenReferenceAction(
                                context,
                                block: owner,
                                onDelete: () => ref
                                    .read(songwriterProvider.notifier)
                                    .removeBlock(
                                      sectionId: section.id,
                                      laneId: lane.id,
                                      blockId: owner.id,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              i += span;
            } else if (owner != null) {
              i++;
            } else {
              cells.add(
                Expanded(
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
                ),
              );
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
                lane.label ?? laneKindFallbackLabel(lane.kind),
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

class _PatternLaneRow extends ConsumerWidget {
  const _PatternLaneRow({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    required this.isMelody,
    this.onEditMelodyPerformance,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final bool isMelody;
  final ValueChanged<String>? onEditMelodyPerformance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final saveState = ref.watch(saveSystemProvider);
    final notifier = ref.read(songwriterProvider.notifier);
    final settingsFallback = ref.watch(
      settingsProvider.select(
        (settings) => settings.defaultNewProjectHarmonyInstrument,
      ),
    );
    final selectedProject = saveState.folders
        .where((folder) => folder.id == saveState.selectedProjectId)
        .firstOrNull;
    final projectDefault =
        selectedProject?.projectConfig?.defaultHarmonyInstrument ??
        settingsFallback ??
        HarmonyLaneInstrument.fretboard;
    final patternNames = isMelody
        ? {
            for (final pattern in project.melodyPatterns)
              pattern.id: pattern.name,
          }
        : {
            for (final pattern in project.guitarStrumPatterns)
              pattern.id: pattern.name,
          };
    final harmonyLanes = section.lanes
        .where(
          (candidate) =>
              candidate.kind == SongLaneKind.harmony &&
              effectiveHarmonyInstrument(candidate, projectDefault) ==
                  HarmonyLaneInstrument.fretboard,
        )
        .toList();
    final resolvedAnchor = isMelody
        ? null
        : guitarStrumAnchorLane(
            section,
            lane,
            projectDefault: projectDefault,
          )?.id;
    final hasUnresolvedStrumAnchor =
        !isMelody && lane.anchorLaneId != null && resolvedAnchor == null;
    final ownerByBar = <int, SongBlock>{};
    for (final block in lane.blocks) {
      for (var bar = block.startBar; bar < block.endBar; bar++) {
        ownerByBar[bar] = block;
      }
    }

    void openPattern(SongBlock block) {
      final patternId = block.patternId;
      if (patternId == null || !patternNames.containsKey(patternId)) return;
      if (isMelody) {
        showSongwriterMelodyPatternEditor(
          context: context,
          patternId: patternId,
        );
      } else {
        showGuitarStrumPatternSheet(context: context, patternId: patternId);
      }
    }

    int availableBarsAt(int bar) {
      var available = 0;
      while (bar + available < section.lengthBars &&
          !ownerByBar.containsKey(bar + available)) {
        available++;
      }
      return available;
    }

    int spanForPatternAt(int lengthTicks, int bar) {
      final measureTicks = project.config.measureTicks;
      final requiredBars = (lengthTicks + measureTicks - 1) ~/ measureTicks;
      return requiredBars.clamp(1, availableBarsAt(bar));
    }

    Future<void> createPatternAt(int bar) async {
      final patternId = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: MuzicianTheme.dialogBg,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'Use existing pattern',
                  style: TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (patternNames.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'No existing patterns yet.',
                    style: TextStyle(color: MuzicianTheme.textSecondary),
                  ),
                ),
              for (final entry in patternNames.entries)
                ListTile(
                  key: Key('reuseWriterPattern_${entry.key}'),
                  minTileHeight: 48,
                  leading: Icon(
                    isMelody ? Icons.music_note : Icons.music_note_outlined,
                    color: isMelody ? MuzicianTheme.sky : MuzicianTheme.emerald,
                  ),
                  title: Text(entry.value),
                  onTap: () => Navigator.of(sheetContext).pop(entry.key),
                ),
              const Divider(height: 16),
              ListTile(
                key: const Key('createWriterPattern'),
                minTileHeight: 48,
                leading: const Icon(Icons.add, color: MuzicianTheme.sky),
                title: const Text('Create new pattern'),
                onTap: () => Navigator.of(sheetContext).pop('__create__'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || patternId == null) return;

      if (patternId == '__create__') {
        String createdId = '';
        notifier.runHistoryGroup(() {
          if (isMelody) {
            createdId = notifier.addMelodyPattern(
              lengthTicks: project.config.measureTicks,
            );
            notifier.addMelodyBlock(
              sectionId: section.id,
              laneId: lane.id,
              patternId: createdId,
              startBar: bar,
              spanBars: 1,
            );
          } else {
            createdId = notifier.addGuitarStrumPattern(
              lengthTicks: project.config.measureTicks,
            );
            notifier.addGuitarStrumBlock(
              sectionId: section.id,
              laneId: lane.id,
              patternId: createdId,
              startBar: bar,
              spanBars: 1,
            );
          }
        });
        if (createdId.isEmpty || !context.mounted) return;
        if (isMelody) {
          final createdBlock = ref
              .read(songwriterProvider)
              .sections
              .firstWhere((candidate) => candidate.id == section.id)
              .lanes
              .firstWhere((candidate) => candidate.id == lane.id)
              .blocks
              .firstWhere(
                (candidate) =>
                    candidate.patternId == createdId &&
                    candidate.startBar == bar,
              );
          showSongwriterMelodyPatternEditor(
            context: context,
            patternId: createdId,
            initialPlacement: SongwriterMelodyInitialPlacement(
              sectionId: section.id,
              laneId: lane.id,
              blockId: createdBlock.id,
            ),
          );
        } else {
          showGuitarStrumPatternSheet(context: context, patternId: createdId);
        }
        return;
      }

      notifier.runHistoryGroup(() {
        if (isMelody) {
          final pattern = ref
              .read(songwriterProvider)
              .melodyPatterns
              .where((candidate) => candidate.id == patternId)
              .firstOrNull;
          if (pattern == null) return;
          notifier.addMelodyBlock(
            sectionId: section.id,
            laneId: lane.id,
            patternId: patternId,
            startBar: bar,
            spanBars: spanForPatternAt(pattern.lengthTicks, bar),
          );
        } else {
          final pattern = ref
              .read(songwriterProvider)
              .guitarStrumPatterns
              .where((candidate) => candidate.id == patternId)
              .firstOrNull;
          if (pattern == null) return;
          notifier.addGuitarStrumBlock(
            sectionId: section.id,
            laneId: lane.id,
            patternId: patternId,
            startBar: bar,
            spanBars: spanForPatternAt(pattern.lengthTicks, bar),
          );
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            children: [
              Icon(
                isMelody ? Icons.music_note : Icons.music_note_outlined,
                size: 13,
                color: isMelody ? MuzicianTheme.sky : MuzicianTheme.emerald,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  lane.label ?? laneKindFallbackLabel(lane.kind),
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (!isMelody)
                Semantics(
                  label:
                      'Select Fretboard Harmony source for ${lane.label ?? 'Guitar Strum'}',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: Key('strumAnchor_${lane.id}_$instanceIndex'),
                      value: hasUnresolvedStrumAnchor
                          ? null
                          : resolvedAnchor ?? '',
                      hint: hasUnresolvedStrumAnchor
                          ? const Text('Unresolved')
                          : null,
                      isDense: false,
                      iconSize: 16,
                      dropdownColor: MuzicianTheme.surface,
                      style: const TextStyle(
                        color: MuzicianTheme.textSecondary,
                        fontSize: 10,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Unassigned'),
                        ),
                        for (
                          var index = 0;
                          index < harmonyLanes.length;
                          index++
                        )
                          DropdownMenuItem(
                            value: harmonyLanes[index].id,
                            child: Text(
                              harmonyLanes[index].label ??
                                  (index == 0
                                      ? 'Primary Fretboard'
                                      : 'Fretboard ${index + 1}'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        notifier.setLaneAnchorLane(
                          sectionId: section.id,
                          laneId: lane.id,
                          harmonyLaneId: value == null || value.isEmpty
                              ? null
                              : value,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final perRow = constraints.maxWidth < 360 ? 2 : 4;
            final narrowCells = constraints.maxWidth / perRow < 90;
            final rows = <List<Widget>>[];
            final bars = section.lengthBars.clamp(1, 64);
            for (var start = 0; start < bars; start += perRow) {
              final end = (start + perRow).clamp(0, bars);
              final cells = <Widget>[];
              var bar = start;
              while (bar < end) {
                final owner = ownerByBar[bar];
                if (owner != null) {
                  final span = (owner.endBar.clamp(bar + 1, end)) - bar;
                  final isContinuation = owner.startBar < bar;
                  final patternName = owner.patternId == null
                      ? null
                      : patternNames[owner.patternId];
                  final displayName = patternName ?? 'pattern?';
                  final melodyPattern = isMelody
                      ? project.melodyPatterns
                            .where((pattern) => pattern.id == owner.patternId)
                            .firstOrNull
                      : null;
                  final strumPattern = isMelody
                      ? null
                      : project.guitarStrumPatterns
                            .where((pattern) => pattern.id == owner.patternId)
                            .firstOrNull;
                  final patternDuration = melodyPattern == null
                      ? null
                      : _formatMusicDuration(
                          melodyPattern.lengthTicks,
                          project.config,
                        );
                  final playbackSummary = melodyPattern == null
                      ? null
                      : _melodyPlacementPlaybackSummary(
                          melodyPattern.lengthTicks,
                          owner.spanBars,
                          project.config,
                        );
                  final tileLabel = isContinuation
                      ? 'Continue ${isMelody ? 'melody' : 'guitar strum'} pattern $displayName, bars ${owner.startBar + 1} through ${owner.endBar}'
                      : isMelody
                      ? 'Edit melody pattern $displayName. Pattern duration $patternDuration. Placed bars ${owner.startBar + 1} through ${owner.endBar}. $playbackSummary.'
                      : 'Edit guitar strum pattern $displayName';
                  cells.add(
                    Expanded(
                      flex: span,
                      child: Semantics(
                        button: true,
                        explicitChildNodes: true,
                        label: tileLabel,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: Key(
                              '${isMelody ? 'sheetMelodyTile' : 'sheetGuitarStrumTile'}_${owner.patternId ?? owner.id}_${instanceIndex}_$bar',
                            ),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => openPattern(owner),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              constraints: const BoxConstraints(minHeight: 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (isMelody
                                            ? MuzicianTheme.sky
                                            : MuzicianTheme.emerald)
                                        .withValues(alpha: .14),
                                border: Border.all(
                                  color:
                                      (isMelody
                                              ? MuzicianTheme.sky
                                              : MuzicianTheme.emerald)
                                          .withValues(alpha: .45),
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      if (!narrowCells) ...[
                                        Icon(
                                          isMelody
                                              ? Icons.edit_note
                                              : Icons.music_note_outlined,
                                          size: 14,
                                          color: MuzicianTheme.textPrimary,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Expanded(
                                        child: Text(
                                          isContinuation
                                              ? '$displayName · continued'
                                              : displayName,
                                          key: Key(
                                            'writerBlockName_${owner.id}_${instanceIndex}_$bar',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: MuzicianTheme.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isMelody && !isContinuation)
                                        PopupMenuButton<String>(
                                          key: Key(
                                            'melodyBlockActions_${owner.id}_$instanceIndex',
                                          ),
                                          tooltip: 'Melody block actions',
                                          padding: EdgeInsets.zero,
                                          child: const SizedBox(
                                            width: 44,
                                            height: 44,
                                            child: Icon(
                                              Icons.more_vert,
                                              size: 18,
                                              color:
                                                  MuzicianTheme.textSecondary,
                                            ),
                                          ),
                                          onSelected: (action) {
                                            if (action == 'placement') {
                                              _showPatternPlacementDialog(
                                                context,
                                                ref,
                                                section,
                                                lane,
                                                owner,
                                              );
                                            } else if (action ==
                                                    'performance' &&
                                                owner.patternId != null) {
                                              onEditMelodyPerformance?.call(
                                                owner.patternId!,
                                              );
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            const PopupMenuItem(
                                              value: 'placement',
                                              child: ListTile(
                                                leading: Icon(Icons.open_with),
                                                title: Text('Adjust placement'),
                                                dense: true,
                                              ),
                                            ),
                                            if (onEditMelodyPerformance != null)
                                              const PopupMenuItem(
                                                value: 'performance',
                                                child: ListTile(
                                                  leading: Icon(Icons.piano),
                                                  title: Text(
                                                    'Edit performance',
                                                  ),
                                                  dense: true,
                                                ),
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                  if (isMelody &&
                                      !isContinuation &&
                                      melodyPattern != null) ...[
                                    Text(
                                      'Duration: $patternDuration',
                                      style: const TextStyle(
                                        color: MuzicianTheme.textSecondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      'Placement: bars ${owner.startBar + 1}–${owner.endBar} · $playbackSummary',
                                      style: const TextStyle(
                                        color: MuzicianTheme.textSecondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                  if (!isMelody && strumPattern != null)
                                    _StrumPatternTimelinePreview(
                                      pattern: strumPattern,
                                      beatTicks: project.config.ticksPerBeat,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  bar += span;
                } else {
                  final emptyBar = bar++;
                  cells.add(
                    Expanded(
                      child: Semantics(
                        button: true,
                        label:
                            'Create ${isMelody ? 'melody' : 'guitar strum'} pattern at bar ${emptyBar + 1}',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: Key(
                              'empty${isMelody ? 'Melody' : 'GuitarStrum'}Bar_${lane.id}_${instanceIndex}_$emptyBar',
                            ),
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => createPatternAt(emptyBar),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 44,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: MuzicianTheme.glassBorder,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: MuzicianTheme.textMuted,
                                  semanticLabel: 'Add pattern',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }
              rows.add(cells);
            }
            return Column(
              children: [
                for (var row = 0; row < rows.length; row++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row == rows.length - 1 ? 0 : 6,
                    ),
                    child: Row(children: rows[row]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _formatMusicDuration(int durationTicks, SongwriterConfig config) {
  final safeDuration = durationTicks < 0 ? 0 : durationTicks;
  final bars = safeDuration ~/ config.measureTicks;
  final afterBars = safeDuration % config.measureTicks;
  final beats = afterBars ~/ config.ticksPerBeat;
  final ticks = afterBars % config.ticksPerBeat;
  final units = <String>[
    if (bars > 0) '$bars ${bars == 1 ? 'bar' : 'bars'}',
    if (beats > 0) '$beats ${beats == 1 ? 'beat' : 'beats'}',
    if (ticks > 0) '$ticks ${ticks == 1 ? 'tick' : 'ticks'}',
  ];
  return units.isEmpty ? '0 ticks' : units.join(' + ');
}

String _melodyPlacementPlaybackSummary(
  int patternLengthTicks,
  int spanBars,
  SongwriterConfig config,
) {
  final patternTicks = patternLengthTicks < 1 ? 1 : patternLengthTicks;
  final placedTicks = spanBars * config.measureTicks;
  if (patternTicks > placedTicks) {
    return 'clips after ${_formatMusicDuration(placedTicks, config)}';
  }
  if (patternTicks == placedTicks) return 'plays once';
  if (placedTicks % patternTicks == 0) {
    return 'repeats ×${placedTicks ~/ patternTicks} to fill';
  }
  return 'repeats, then clips the final pass';
}

Future<void> _showPatternPlacementDialog(
  BuildContext context,
  WidgetRef ref,
  SongSection section,
  SongLane lane,
  SongBlock block,
) => showDialog<void>(
  context: context,
  builder: (_) => _PatternPlacementDialog(
    section: section,
    lane: lane,
    block: block,
    onApply: (startBar, spanBars) => ref
        .read(songwriterProvider.notifier)
        .setBlockPlacement(
          sectionId: section.id,
          laneId: lane.id,
          blockId: block.id,
          startBar: startBar,
          spanBars: spanBars,
        ),
  ),
);

class _PatternPlacementDialog extends StatefulWidget {
  const _PatternPlacementDialog({
    required this.section,
    required this.lane,
    required this.block,
    required this.onApply,
  });

  final SongSection section;
  final SongLane lane;
  final SongBlock block;
  final void Function(int startBar, int spanBars) onApply;

  @override
  State<_PatternPlacementDialog> createState() =>
      _PatternPlacementDialogState();
}

class _PatternPlacementDialogState extends State<_PatternPlacementDialog> {
  late final _startBarController = TextEditingController(
    text: '${widget.block.startBar + 1}',
  );
  late final _spanBarsController = TextEditingController(
    text: '${widget.block.spanBars}',
  );

  @override
  void dispose() {
    _startBarController.dispose();
    _spanBarsController.dispose();
    super.dispose();
  }

  int? get _startBar => int.tryParse(_startBarController.text);
  int? get _spanBars => int.tryParse(_spanBarsController.text);

  SongBlock? get _candidate {
    final startBar = _startBar;
    final spanBars = _spanBars;
    if (startBar == null || spanBars == null) return null;
    return widget.block.copyWith(startBar: startBar - 1, spanBars: spanBars);
  }

  bool get _isValid {
    final candidate = _candidate;
    return candidate != null &&
        isValidBlockPlacement(
          section: widget.section,
          lane: widget.lane,
          candidate: candidate,
        );
  }

  String _validationMessage() {
    final startBar = _startBar;
    final spanBars = _spanBars;
    if (startBar == null ||
        startBar < 1 ||
        startBar > widget.section.lengthBars) {
      return 'Choose a start bar from 1 to ${widget.section.lengthBars}.';
    }
    if (spanBars == null || spanBars < 1) {
      return 'Placement must be at least 1 bar long.';
    }
    final candidate = _candidate!;
    if (candidate.endBar > widget.section.lengthBars) {
      return 'The block must end by bar ${widget.section.lengthBars}.';
    }
    if (blocksOverlap(widget.lane.blocks, candidate)) {
      return 'This placement overlaps another block in the lane.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: MuzicianTheme.dialogBg,
      title: const Text('Adjust melody placement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('melodyPlacementStartBar'),
                  controller: _startBarController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Start bar',
                    helperText: '1-based',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('melodyPlacementSpanBars'),
                  controller: _spanBarsController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Length (bars)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _validationMessage(),
              style: TextStyle(
                color: _isValid
                    ? MuzicianTheme.textSecondary
                    : MuzicianTheme.orange,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('applyMelodyPlacement'),
          onPressed: _isValid
              ? () {
                  final candidate = _candidate!;
                  widget.onApply(candidate.startBar, candidate.spanBars);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _StrumPatternTimelinePreview extends StatelessWidget {
  const _StrumPatternTimelinePreview({
    required this.pattern,
    required this.beatTicks,
  });

  final GuitarStrumPattern pattern;
  final int beatTicks;

  @override
  Widget build(BuildContext context) {
    final lengthTicks = pattern.lengthTicks < 1 ? 1 : pattern.lengthTicks;
    final events = pattern.events.asMap().entries.toList()
      ..sort((a, b) {
        final tickOrder = a.value.tick.compareTo(b.value.tick);
        return tickOrder == 0 ? a.key.compareTo(b.key) : tickOrder;
      });
    final eventDescription = events.isEmpty
        ? 'no strum events'
        : events
              .map(
                (entry) =>
                    '${entry.value.direction == GuitarStrumDirection.down ? 'down' : 'up'} at tick ${entry.value.tick}',
              )
              .join(', ');
    return Semantics(
      key: Key('strumPatternPreview_${pattern.id}'),
      label: 'Ordered strum preview: $eventDescription',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 26,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PatternTickGridPainter(
                        lengthTicks: lengthTicks,
                        beatTicks: beatTicks,
                      ),
                    ),
                  ),
                  for (final entry in events)
                    Positioned(
                      left: _strumEventX(
                        entry.value.tick,
                        lengthTicks,
                        availableWidth,
                      ),
                      top: 0,
                      bottom: 0,
                      child: Icon(
                        entry.value.direction == GuitarStrumDirection.down
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 14,
                        color: MuzicianTheme.emerald,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  double _strumEventX(int tick, int lengthTicks, double width) {
    final safeWidth = width > 16 ? width - 16 : 0;
    final safeTick = tick.clamp(0, lengthTicks);
    return (safeWidth * safeTick / lengthTicks)
        .clamp(0.0, safeWidth)
        .toDouble();
  }
}

class _PatternTickGridPainter extends CustomPainter {
  const _PatternTickGridPainter({
    required this.lengthTicks,
    required this.beatTicks,
  });

  final int lengthTicks;
  final int beatTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = MuzicianTheme.textMuted.withValues(alpha: 0.38)
      ..strokeWidth = 1;
    final ticksPerBeat = beatTicks < 1 ? 1 : beatTicks;
    final beatCount = (lengthTicks + ticksPerBeat - 1) ~/ ticksPerBeat;
    final lineStride = beatCount > 16 ? (beatCount / 16).ceil() : 1;
    for (var beat = 0; beat <= beatCount; beat += lineStride) {
      final tick = (beat * ticksPerBeat).clamp(0, lengthTicks);
      final x = size.width * tick / lengthTicks;
      canvas.drawLine(Offset(x, 3), Offset(x, size.height - 3), line);
    }
  }

  @override
  bool shouldRepaint(_PatternTickGridPainter oldDelegate) =>
      lengthTicks != oldDelegate.lengthTicks ||
      beatTicks != oldDelegate.beatTicks;
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
              child: Container(height: 1, color: MuzicianTheme.glassBorder),
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
              child: Container(height: 1, color: MuzicianTheme.glassBorder),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.onAddSection});

  final VoidCallback onAddSection;

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
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('writerEmptyAddSection'),
            onPressed: onAddSection,
            icon: const Icon(Icons.add),
            label: const Text('Start an 8-bar section'),
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
  }

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: widget.title,
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
        MuzicianDialogButton(
          'Done',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () {
            widget.onChanged(_v);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
