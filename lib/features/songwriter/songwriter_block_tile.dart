import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../models/save_system.dart';
import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../schema/rules/songwriter_library_match_rules.dart';
import '../../schema/rules/songwriter_third_above_rules.dart';
import '../../schema/rules/songwriter_voicing_rules.dart';
import '../../utils/note_utils.dart';
import '../../store/songwriter_store.dart';
import '../../store/save_system_store.dart';
import '../../ui/save_browser_panel.dart';
import 'songwriter_block_preview.dart';
import 'songwriter_save_lane_filter.dart';
import 'songwriter_undo.dart';

class SongwriterBlockTile extends ConsumerStatefulWidget {
  const SongwriterBlockTile({
    super.key,
    required this.sectionId,
    required this.laneId,
    required this.blockId,
    this.barWidth = 40,
    this.highlighted = false,
  });
  final String sectionId;
  final String laneId;
  final String blockId;
  final double barWidth;
  final bool highlighted;

  @override
  ConsumerState<SongwriterBlockTile> createState() =>
      _SongwriterBlockTileState();
}

class _SongwriterBlockTileState extends ConsumerState<SongwriterBlockTile> {
  double _dragDx = 0;
  double _resizeDx = 0;

  SongBlock? _watchBlock() => ref.watch(
    songwriterProvider.select((p) {
      for (final s in p.sections) {
        if (s.id != widget.sectionId) continue;
        for (final l in s.lanes) {
          if (l.id != widget.laneId) continue;
          for (final b in l.blocks) {
            if (b.id == widget.blockId) return b;
          }
        }
      }
      return null;
    }),
  );

  void _applyMove(SongBlock block) {
    final deltaBars = (_dragDx / widget.barWidth).round();
    if (deltaBars == 0) return;
    ref
        .read(songwriterProvider.notifier)
        .setBlockPlacement(
          sectionId: widget.sectionId,
          laneId: widget.laneId,
          blockId: widget.blockId,
          startBar: block.startBar + deltaBars,
          spanBars: block.spanBars,
        );
  }

  void _applyResize(SongBlock block) {
    final deltaBars = (_resizeDx / widget.barWidth).round();
    if (deltaBars == 0) return;
    final newSpan = block.spanBars + deltaBars;
    if (newSpan < 1) return;
    ref
        .read(songwriterProvider.notifier)
        .setBlockPlacement(
          sectionId: widget.sectionId,
          laneId: widget.laneId,
          blockId: widget.blockId,
          startBar: block.startBar,
          spanBars: newSpan,
        );
  }

  @override
  Widget build(BuildContext context) {
    final block = _watchBlock();
    if (block == null) return const SizedBox.shrink();

    final saves = ref.watch(saveSystemProvider).saves;
    final broken =
        block.embedded == null &&
        block.saveId != null &&
        !saves.any((e) => e.id == block.saveId);

    final primary =
        block.chordSymbol ?? block.romanNumeral ?? _saveLabel(saves, block);
    final secondary = block.chordSymbol != null ? block.romanNumeral : null;

    return GestureDetector(
      key: Key('block_${widget.blockId}'),
      onTap: () => _onTap(context, block, saves),
      onLongPress: () => _openMenu(context, block),
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
      onHorizontalDragEnd: (_) => _applyMove(block),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: _blockFill(block, widget.highlighted, broken),
          borderRadius: BorderRadius.circular(8),
          border: _blockBorder(block, widget.highlighted, broken),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    primary,
                    style: const TextStyle(
                      color: MuzicianTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (secondary != null)
                    Text(
                      secondary,
                      style: const TextStyle(
                        color: MuzicianTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            GestureDetector(
              key: Key('resizeHandle_${widget.blockId}'),
              onHorizontalDragStart: (_) => _resizeDx = 0,
              onHorizontalDragUpdate: (d) => _resizeDx += d.delta.dx,
              onHorizontalDragEnd: (_) => _applyResize(block),
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(8),
                    ),
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context, SongBlock block, List<SaveEntry> saves) {
    // Harmony block: show the chord + voicing suggestions.
    if (block.chordRootPc != null && block.chordQuality != null) {
      final cfg = ref.read(songwriterProvider).config;
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
      final swNotifier = ref.read(songwriterProvider.notifier);
      final searchable = swNotifier.searchableSavesForLibraryMatch();
      final matches = matchLibrary(
        harmonyBlock: block,
        searchableSaves: searchable,
        keyRootPc: cfg.keyRoot,
        keyScaleName: cfg.keyScaleName,
      );
      showHarmonyBlockSheet(
        context,
        block: block,
        voicings: voicings,
        thirdAbove: thirdAbove,
        chordMatches: matches.chordMatches,
        scaleMatches: matches.scaleMatches,
        onAcceptVoicing: (v) {
          swNotifier.acceptVoicingSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: v,
          );
        },
        onAcceptThirdAbove: (s) {
          swNotifier.acceptThirdAboveSuggestion(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            suggestion: s,
          );
        },
        onAcceptLibrary: (saveId) {
          swNotifier.acceptLibraryMatch(
            sectionId: widget.sectionId,
            harmonyBlockId: widget.blockId,
            saveId: saveId,
          );
        },
      );
      return;
    }
    // Save block: existing flow (resolve snapshot → preview or broken-ref).
    final snapshot = resolveBlockSnapshot(block, saves);
    if (snapshot != null) {
      showBlockPreviewSheet(context, snapshot);
    } else {
      showBrokenReferenceSheet(
        context,
        onDelete: () {
          ref
              .read(songwriterProvider.notifier)
              .removeBlock(
                sectionId: widget.sectionId,
                laneId: widget.laneId,
                blockId: widget.blockId,
              );
        },
      );
    }
  }

  void _openMenu(BuildContext context, SongBlock block) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('Edit placement'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _editPlacement(context, block);
              },
            ),
            if (block.embedded == null && block.saveId != null)
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Make Unique'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final saves = ref.read(saveSystemProvider).saves;
                  final snap = resolveBlockSnapshot(block, saves);
                  if (snap != null) {
                    ref
                        .read(songwriterProvider.notifier)
                        .makeBlockUnique(
                          sectionId: widget.sectionId,
                          laneId: widget.laneId,
                          blockId: widget.blockId,
                          snapshot: snap,
                        );
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Re-link'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final picked = await showModalBottomSheet<SaveEntry>(
                  context: context,
                  isScrollControlled: true,
                  // Allow fretboard / piano / piano_roll enrichment saves,
                  // but exclude songwriter + song arrangement-level saves so
                  // a save-lane block cannot point at a whole project save.
                  builder: (ctx) => SaveBrowserPanel(
                    allowedInstruments:
                        songwriterSaveLaneAllowedInstruments,
                    onPick: (entry) => Navigator.pop(ctx, entry),
                  ),
                );
                if (picked != null) {
                  ref
                      .read(songwriterProvider.notifier)
                      .relinkBlock(
                        sectionId: widget.sectionId,
                        laneId: widget.laneId,
                        blockId: widget.blockId,
                        saveId: picked.id,
                      );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetCtx);
                final n = ref.read(songwriterProvider.notifier);
                n.removeBlock(
                  sectionId: widget.sectionId,
                  laneId: widget.laneId,
                  blockId: widget.blockId,
                );
                showUndoSnack(
                  context,
                  'Block deleted',
                  () => n.insertBlock(
                    sectionId: widget.sectionId,
                    laneId: widget.laneId,
                    block: block,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editPlacement(BuildContext context, SongBlock block) {
    showDialog<void>(
      context: context,
      builder: (_) => _PlacementDialog(
        initialStart: block.startBar,
        initialSpan: block.spanBars,
        onApply: (start, span) => ref
            .read(songwriterProvider.notifier)
            .setBlockPlacement(
              sectionId: widget.sectionId,
              laneId: widget.laneId,
              blockId: widget.blockId,
              startBar: start,
              spanBars: span,
            ),
      ),
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

  String _saveLabel(List<SaveEntry> saves, SongBlock block) {
    final snap = block.embedded;
    if (snap != null) return snap.pendingChord?.symbol ?? 'Saved';
    final id = block.saveId;
    if (id == null) return 'Block';
    for (final e in saves) {
      if (e.id == id) return e.name;
    }
    return 'Missing';
  }
}

Color _blockFill(SongBlock block, bool highlighted, bool broken) {
  if (broken) return MuzicianTheme.red.withValues(alpha: 0.25);
  final base = block.chordRootPc != null
      ? MuzicianTheme.violet
      : MuzicianTheme.teal;
  return base.withValues(alpha: highlighted ? 0.45 : 0.25);
}

Border _blockBorder(SongBlock block, bool highlighted, bool broken) {
  if (broken) {
    return Border.all(color: MuzicianTheme.red.withValues(alpha: 0.5));
  }
  final base = block.chordRootPc != null
      ? MuzicianTheme.violet
      : MuzicianTheme.teal;
  if (highlighted) {
    return Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5);
  }
  return Border.all(color: base.withValues(alpha: 0.5));
}

class _PlacementDialog extends StatefulWidget {
  const _PlacementDialog({
    required this.initialStart,
    required this.initialSpan,
    required this.onApply,
  });
  final int initialStart;
  final int initialSpan;
  final void Function(int startBar, int spanBars) onApply;

  @override
  State<_PlacementDialog> createState() => _PlacementDialogState();
}

class _PlacementDialogState extends State<_PlacementDialog> {
  late int _start = widget.initialStart;
  late int _span = widget.initialSpan;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Block placement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(
            'Start bar',
            _start,
            0,
            (v) => setState(() => _start = v < 0 ? 0 : v),
          ),
          _row(
            'Span (bars)',
            _span,
            1,
            (v) => setState(() => _span = v < 1 ? 1 : v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onApply(_start, _span);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _row(String label, int value, int min, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text('$value'),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
