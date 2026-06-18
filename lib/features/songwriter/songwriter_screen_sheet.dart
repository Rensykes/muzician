/// Notation-Sheet (lead-sheet inspired) — the sole Writer layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_library_match_rules.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../store/save_system_store.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../ui/core/coach_overlay.dart';
import '../../ui/glass_snackbar.dart';
import '../../ui/save_browser_panel.dart';
import '../../utils/note_utils.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'songwriter_block_preview.dart';
import 'songwriter_coach_steps.dart';
import 'songwriter_save_lane_filter.dart';
import '../../theme/muzician_theme.dart';
import 'drum_pattern_sheet.dart';
import 'harmony_chord_sheet.dart';
import 'songwriter_header.dart';
import 'songwriter_save_panel.dart';
import 'songwriter_structure_editor.dart';
import 'songwriter_undo.dart';
import '../_mockup_shell.dart';

class SongwriterScreenSheet extends ConsumerStatefulWidget {
  const SongwriterScreenSheet({super.key});

  @override
  ConsumerState<SongwriterScreenSheet> createState() =>
      _SongwriterScreenSheetState();
}

class _SongwriterScreenSheetState extends ConsumerState<SongwriterScreenSheet> {
  final _coachKeys = WriterCoachKeys();

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
  Widget build(BuildContext context) {
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
            KeyedSubtree(
              key: _coachKeys.header,
              child: SongwriterHeader(
                onOpenSaveLoad: () => _openSaveLoad(context),
                onOpenStructure: () => _openStructure(context),
                onStartTour: () =>
                    startCoachTour(context, writerCoachSteps(_coachKeys)),
              ),
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
                        const _EmptyState(key: Key('songwriterEmptyHint')),
                      if (twoColumns)
                        // Wide layout: sections flow in two columns.
                        Wrap(
                          spacing: 24,
                          runSpacing: 36,
                          children: [
                            for (final section in project.sections)
                              SizedBox(
                                width: columnWidth,
                                child: _SectionSheet(sectionId: section.id),
                              ),
                          ],
                        )
                      else
                        for (final section in project.sections)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 36),
                            child: _SectionSheet(sectionId: section.id),
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
    ref.listen(
      songwriterActivePositionProvider.select(
        (p) => p != null &&
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
        // Lyrics lanes (one strip per lyrics lane on this section).
        for (final lane
            in section.lanes.where((l) => l.kind == SongLaneKind.lyrics)) ...[
          const SizedBox(height: 8),
          _LyricLaneRow(
            key: Key('sheetLyricLane_${lane.id}_$instanceIndex'),
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
            PopupMenuButton<String>(
              key: Key('sheetSectionMenu_${section.id}'),
              icon: const Icon(Icons.more_vert, color: MuzicianTheme.textPrimary),
              onSelected: (value) async {
                if (value == 'addDrumLane') {
                  ref.read(songwriterProvider.notifier).addLane(
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
                  final patternId = ref.read(songwriterProvider.notifier)
                      .addDrumPattern(name: 'Pattern');
                  ref.read(songwriterProvider.notifier).addDrumBlock(
                        sectionId: section.id,
                        laneId: laneId,
                        patternId: patternId,
                        startBar: 0,
                        spanBars: section.lengthBars,
                      );
                }
                if (value == 'addLyricLane') {
                  ref.read(songwriterProvider.notifier).addLane(
                        sectionId: section.id,
                        kind: SongLaneKind.lyrics,
                        label: 'Lyrics',
                      );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  key: Key('addDrumLaneSheetAction'),
                  value: 'addDrumLane',
                  child: ListTile(
                    leading: Icon(Icons.graphic_eq),
                    title: Text('Add drum lane'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  key: Key('addLyricLaneSheetAction'),
                  value: 'addLyricLane',
                  child: ListTile(
                    leading: Icon(Icons.lyrics_outlined),
                    title: Text('Add lyrics lane'),
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
    final activeBar = ref.watch(
      songwriterActivePositionProvider.select(
        (p) => p != null &&
                p.sectionId == section.id &&
                p.instanceIndex == instanceIndex
            ? p.localBar
            : null,
      ),
    );
    bool isActiveCell(int startBar, int span) =>
        activeBar != null && activeBar >= startBar && activeBar < startBar + span;
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
    final saveBySpan = <int, SongBlock>{};
    for (final l in section.lanes.where((l) => l.kind == SongLaneKind.save)) {
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
              cells.add(_BarCell(
                key: activeKey(i, span),
                flex: span,
                block: owner,
                saveBlock: save,
                instanceIndex: instanceIndex,
                isActive: isActiveCell(i, span),
                onTap: () => _onTapBlock(context, ref, owner),
                onSaveTap:
                    save == null ? null : () => _onTapSave(context, ref, save),
                onLongPress: () =>
                    _removeBlock(context, notifier, owner),
              ));
              i += span;
            } else if (owner != null) {
              i++;
            } else if (saveBySpan[i] != null) {
              // Standalone save (placed on a bar with no chord). Render it as a
              // save cell spanning its bars; tap removes it (with undo).
              final save = saveBySpan[i]!;
              if (save.startBar == i) {
                final span = save.spanBars.clamp(1, end - i);
                cells.add(_BarCell(
                  key: Key('saveCell_${save.id}_$instanceIndex'),
                  flex: span,
                  block: null,
                  saveBlock: save,
                  saveName: _saveName(ref, save),
                  instanceIndex: instanceIndex,
                  isActive: isActiveCell(i, span),
                  onTap: () => _onTapSave(context, ref, save),
                ));
                i += span;
              } else {
                i++; // covered by a spanning save that started earlier
              }
            } else {
              // Snapshot `i` — it is mutated by this while-loop, so a closure
              // capturing it directly would read its post-loop value (`end`),
              // landing every empty-cell tap on the start of the next row.
              final bar = i;
              cells.add(_BarCell(
                key: activeKey(bar, 1),
                flex: 1,
                block: null,
                instanceIndex: instanceIndex,
                isActive: isActiveCell(bar, 1),
                onTap: () => _addAt(context, ref, bar),
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
      onPickFromLibrary: () => _pickFromLibrary(context, ref, bar),
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

  /// Tap on a placed block. Chord blocks open the voicings / harmony /
  /// library sheet (with an "Edit chord & lyrics" escape hatch); silent
  /// lyric-only blocks go straight to the chord editor.
  void _onTapBlock(BuildContext context, WidgetRef ref, SongBlock block) {
    final isChord = !block.isSilent &&
        block.chordRootPc != null &&
        block.chordQuality != null;
    if (!isChord) {
      _editBlock(context, ref, block);
      return;
    }

    final cfg = ref.read(songwriterProvider).config;
    final notifier = ref.read(songwriterProvider.notifier);
    final voicings = suggestVoicings(
      chordRootPc: block.chordRootPc!,
      quality: block.chordQuality!,
    );
    final thirdAbove = suggestThirdAbove(
      chordRootPc: block.chordRootPc!,
      chordQuality: block.chordQuality!,
      chordTonePcs: _chordPcs(block),
      keyRootPc: cfg.keyRoot,
      keyScaleName: cfg.keyScaleName,
    );
    final matches = matchLibrary(
      harmonyBlock: block,
      searchableSaves: notifier.searchableSavesForLibraryMatch(),
      keyRootPc: cfg.keyRoot,
      keyScaleName: cfg.keyScaleName,
    );

    showHarmonyBlockSheet(
      context,
      block: block,
      voicings: voicings,
      thirdAbove: thirdAbove,
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
    if (lane.id.isEmpty) onEnsureLane();
    showWidgetSheet(
      context: context,
      title: 'From library',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: SaveBrowserPanel(
          rootFolderId: selId,
          allowedInstruments: songwriterSaveLaneAllowedInstruments,
          onPick: (entry) {
            Navigator.of(context).pop();
            HapticFeedback.selectionClick();
            ref.read(songwriterProvider.notifier).addLibraryBlockAt(
                  sectionId: section.id,
                  saveId: entry.id,
                  startBar: bar,
                );
          },
        ),
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

  /// Display name for a save block, resolved from the save system; falls back
  /// to 'Save' when the referenced entry is missing.
  String _saveName(WidgetRef ref, SongBlock save) {
    final id = save.saveId;
    if (id == null) return 'Save';
    final entry =
        ref.read(saveSystemProvider).saves.where((s) => s.id == id).firstOrNull;
    return entry?.name ?? 'Save';
  }

  /// Tapping a save (its badge on a chord, or a standalone save cell) removes
  /// it from the save lane, with an undo affordance.
  void _onTapSave(BuildContext context, WidgetRef ref, SongBlock save) {
    final notifier = ref.read(songwriterProvider.notifier);
    final saveLane = section.lanes.firstWhere(
      (l) =>
          l.kind == SongLaneKind.save &&
          l.blocks.any((b) => b.id == save.id),
      orElse: () => const SongLane(id: '', kind: SongLaneKind.save, order: 0),
    );
    if (saveLane.id.isEmpty) return;
    HapticFeedback.lightImpact();
    notifier.removeBlock(
      sectionId: section.id,
      laneId: saveLane.id,
      blockId: save.id,
    );
    showUndoSnack(
      context,
      'Save removed',
      () => notifier.insertBlock(
        sectionId: section.id,
        laneId: saveLane.id,
        block: save,
      ),
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
    this.saveBlock,
    this.saveName,
    this.onSaveTap,
    this.onLongPress,
    this.isActive = false,
  });
  final int flex;
  final SongBlock? block;
  final SongBlock? saveBlock;
  final String? saveName;
  final int instanceIndex;
  final VoidCallback onTap;
  final VoidCallback? onSaveTap;
  final VoidCallback? onLongPress;
  final bool isActive;

  bool get _isSaveOnly => block == null && saveBlock != null;

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
              // tap target so it can be removed without opening the chord sheet.
              if (block != null && saveBlock != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: onSaveTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      key: Key('saveBadge_${saveBlock!.id}_$instanceIndex'),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(
                        Icons.bookmark,
                        size: 13,
                        color: MuzicianTheme.sky,
                      ),
                    ),
                  ),
                ),
            ],
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
          const Icon(Icons.bookmark, size: 16, color: MuzicianTheme.sky),
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

class _LyricLaneRow extends ConsumerWidget {
  const _LyricLaneRow({
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
    final notifier = ref.read(songwriterProvider.notifier);
    final ownerByBar = <int, SongBlock>{};
    for (final b in lane.blocks) {
      for (var i = b.startBar; i < b.endBar; i++) {
        ownerByBar[i] = b;
      }
    }

    final cells = <Widget>[];
    var i = 0;
    while (i < bars) {
      final owner = ownerByBar[i];
      if (owner != null && owner.startBar == i) {
        final span = owner.spanBars.clamp(1, bars - i);
        final text = instanceIndex < owner.lyrics.length
            ? owner.lyrics[instanceIndex]
            : '';
        cells.add(Expanded(
          flex: span,
          child: GestureDetector(
            key: Key('sheetLyricTile_${owner.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _editLyric(context, notifier, owner, text),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: MuzicianTheme.sky.withValues(alpha: 0.12),
                border: Border.all(
                  color: MuzicianTheme.sky.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text.isEmpty ? 'Add lyrics' : text,
                style: TextStyle(
                  fontSize: 12,
                  color: text.isEmpty
                      ? MuzicianTheme.textMuted
                      : MuzicianTheme.textPrimary,
                ),
              ),
            ),
          ),
        ));
        i += span;
      } else if (owner != null) {
        i++;
      } else {
        final bar = i;
        cells.add(Expanded(
          flex: 1,
          child: GestureDetector(
            key: Key('sheetLyricEmpty_${lane.id}_$bar'),
            behavior: HitTestBehavior.opaque,
            onTap: () => notifier.addLyricBlock(
              sectionId: section.id,
              laneId: lane.id,
              startBar: bar,
              spanBars: 1,
              verseCount: section.repeat,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 28,
              decoration: BoxDecoration(
                border: Border.all(color: MuzicianTheme.glassBorder),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ));
        i++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: Key('sheetLyricJot_${lane.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: lane.blocks.isEmpty
              ? () => notifier.addLyricBlock(
                    sectionId: section.id,
                    laneId: lane.id,
                    startBar: 0,
                    spanBars: bars,
                    verseCount: section.repeat,
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              lane.label ?? 'Lyrics',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        Row(children: cells),
      ],
    );
  }

  void _editLyric(
    BuildContext context,
    SongwriterNotifier notifier,
    SongBlock block,
    String current,
  ) {
    final controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text('Lyrics', style: TextStyle(color: MuzicianTheme.textPrimary)),
        content: TextField(
          key: const Key('lyricLaneEditField'),
          controller: controller,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Type lyrics…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('lyricLaneEditSave'),
            onPressed: () {
              notifier.setBlockLyric(
                sectionId: section.id,
                laneId: lane.id,
                blockId: block.id,
                verseIndex: instanceIndex,
                text: controller.text,
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
