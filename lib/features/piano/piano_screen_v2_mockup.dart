/// Piano V2 — UI/UX redesign mockup (iteration 4).
///
/// Canvas variant: VERTICAL piano. Pitches flow top→bottom (highest at top,
/// like a vertical pitch ladder). Each pitch is a full-width tap-row; black
/// keys are darker rows, whites are lighter. Eliminates the "dead glass
/// below keyboard" problem because the canvas literally is the available
/// height. Visually echoes the Roll's pitch sidebar but is interactive.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../models/piano.dart';
import '../../schema/rules/piano_rules.dart' show getKeysForRange, pianoRanges;
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';

class PianoScreenV2Mockup extends ConsumerStatefulWidget {
  const PianoScreenV2Mockup({super.key});

  @override
  ConsumerState<PianoScreenV2Mockup> createState() => _PianoScreenV2MockupState();
}

class _PianoScreenV2MockupState extends ConsumerState<PianoScreenV2Mockup> {
  String _scale = 'C maj';
  String _chord = 'maj';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final selectedCount = state.selectedNotes.length;
    final detected = selectedCount == 0
        ? null
        : selectedCount == 1
            ? 'Selected: ${state.selectedNotes.first}'
            : 'Selected: ${state.selectedNotes.join(' · ')}';

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Piano',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Piano',
              chipLabel: _scale,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                IconBtn(icon: Icons.bookmark_border_rounded, onTap: () {}),
                IconBtn(icon: Icons.tune_rounded, onTap: () {}),
              ],
            ),
            Expanded(
              child: GlassFrame(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: _VerticalPianoCanvas(
                  range: state.currentRange,
                  selectedNotes: state.selectedNotes.toSet(),
                  onTapMidi: (midi, name) {
                    HapticFeedback.selectionClick();
                    // Reuse the same toggle API as the horizontal keyboard.
                    final keys = notifier.getKeys();
                    final idx = keys.indexWhere((k) => k.midiNote == midi);
                    if (idx >= 0) notifier.toggleKey(idx, midi, name);
                  },
                ),
              ),
            ),
            DetectionRibbon(detectedLabel: detected),
            DockedToolbar(
              children: [
                DockField(
                  value: _rangeLabel(state.currentRange),
                  flex: 3,
                  onTap: () async {
                    final byLabel = {
                      for (final r in PianoRangeName.values) _rangeLabel(r): r,
                    };
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Range',
                      options: byLabel.keys.toList(),
                      current: _rangeLabel(state.currentRange),
                    );
                    if (picked != null) notifier.setRange(byLabel[picked]!);
                  },
                ),
                DockField(
                  value: _scale,
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Scale',
                      options: const [
                        'C maj', 'C min', 'D maj', 'D min', 'E maj', 'E min',
                        'F maj', 'G maj', 'A min', 'B min', 'C pent', 'A blues',
                      ],
                      current: _scale,
                    );
                    if (picked != null) setState(() => _scale = picked);
                  },
                ),
                DockField(
                  value: _chord,
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Chord',
                      options: const ['maj', 'min', 'dom7', 'maj7', 'm7', 'sus2', 'sus4', 'dim', 'aug'],
                      current: _chord,
                    );
                    if (picked != null) setState(() => _chord = picked);
                  },
                ),
                DockPrimaryButton(
                  icon: Icons.play_arrow_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Preview $_chord chord'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Strip "X Keys (...)" → just the pitch span for compactness.
  String _rangeLabel(PianoRangeName r) {
    final raw = pianoRanges[r]?.displayName ?? r.name;
    final m = RegExp(r'\(([^)]+)\)').firstMatch(raw);
    return m?.group(1) ?? raw;
  }
}

// ── Vertical canvas ─────────────────────────────────────────────────────────

class _VerticalPianoCanvas extends StatefulWidget {
  final PianoRangeName range;
  final Set<String> selectedNotes;
  final void Function(int midi, String name) onTapMidi;
  const _VerticalPianoCanvas({
    required this.range,
    required this.selectedNotes,
    required this.onTapMidi,
  });

  @override
  State<_VerticalPianoCanvas> createState() => _VerticalPianoCanvasState();
}

class _VerticalPianoCanvasState extends State<_VerticalPianoCanvas> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pitches flow top→bottom: highest at top, lowest at bottom.
    final keys = getKeysForRange(widget.range).reversed.toList();
    return LayoutBuilder(
      builder: (ctx, c) {
        // Aim for roughly 1.5 octaves (~18 rows) on a typical phone, scroll for more.
        const minRowH = 22.0;
        const maxRowH = 32.0;
        final ideal = c.maxHeight / 18.0;
        final rowH = ideal.clamp(minRowH, maxRowH);
        final totalH = rowH * keys.length;
        // Center on middle-C of the visible range on first build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          if (_scrollController.offset != 0) return;
          final midC = keys.indexWhere((k) => k.midiNote == 60);
          if (midC < 0) return;
          final off = (midC * rowH - c.maxHeight / 2 + rowH / 2)
              .clamp(0.0, totalH - c.maxHeight);
          _scrollController.jumpTo(off);
        });
        return Stack(
          children: [
            ListView.builder(
              controller: _scrollController,
              itemCount: keys.length,
              itemExtent: rowH,
              padding: EdgeInsets.zero,
              itemBuilder: (_, i) {
                final k = keys[i];
                final selected = widget.selectedNotes.contains(k.noteName);
                return _PitchRow(
                  midi: k.midiNote,
                  name: k.noteName,
                  isBlack: k.isBlack,
                  selected: selected,
                  onTap: () => widget.onTapMidi(k.midiNote, k.noteName),
                );
              },
            ),
            // Top and bottom edge fades hint at scrollability.
            Positioned(
              left: 0, right: 0, top: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        MuzicianTheme.scaffoldBg.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        MuzicianTheme.scaffoldBg.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PitchRow extends StatelessWidget {
  final int midi;
  final String name;
  final bool isBlack;
  final bool selected;
  final VoidCallback onTap;
  const _PitchRow({
    required this.midi,
    required this.name,
    required this.isBlack,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isC = midi % 12 == 0;
    final octave = (midi ~/ 12) - 1;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? MuzicianTheme.sky.withValues(alpha: 0.32)
              : isBlack
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.18),
          border: Border(
            left: BorderSide(
              color: selected ? MuzicianTheme.sky : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: MuzicianTheme.scaffoldBg.withValues(alpha: 0.55),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            SizedBox(
              width: 36,
              child: Text(
                isC ? 'C$octave' : name,
                style: TextStyle(
                  color: selected
                      ? MuzicianTheme.scaffoldBg
                      : isBlack
                          ? MuzicianTheme.textMuted
                          : MuzicianTheme.scaffoldBg.withValues(alpha: 0.75),
                  fontSize: isC ? 13 : 11,
                  fontWeight: isC || selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: MuzicianTheme.scaffoldBg.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
