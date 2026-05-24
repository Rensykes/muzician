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
import '../../schema/rules/piano_rules.dart' show getKeysForRange;
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';
import 'piano_chord_picker.dart';
import 'piano_note_detection_panel.dart';
import 'piano_range_selector.dart';
import 'piano_save_panel.dart';
import 'piano_scale_picker.dart';

class PianoScreenV2Mockup extends ConsumerStatefulWidget {
  const PianoScreenV2Mockup({super.key});

  @override
  ConsumerState<PianoScreenV2Mockup> createState() => _PianoScreenV2MockupState();
}

class _PianoScreenV2MockupState extends ConsumerState<PianoScreenV2Mockup> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final activeScale = ref.watch(pianoActiveScaleProvider);
    final activeChord = ref.watch(pianoActiveChordProvider);
    // Octave-aware pitch labels (e.g. C4, E5) so the ribbon shows the
    // EXACT pitches the user tapped, not just their pitch classes.
    final selectedLabels = (state.selectedKeys.toList()
          ..sort((a, b) => a.midiNote.compareTo(b.midiNote)))
        .map((k) => '${k.noteName}${(k.midiNote ~/ 12) - 1}')
        .toList();
    final detected = selectedLabels.isEmpty
        ? null
        : 'Selected: ${selectedLabels.join(' · ')}';

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Piano',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Piano',
              chipLabel: state.selectedNotes.isEmpty
                  ? null
                  : '${state.selectedNotes.length} note${state.selectedNotes.length == 1 ? "" : "s"}',
              onClose: () => Navigator.of(context).pop(),
              actions: [
                IconBtn(
                  icon: Icons.bookmark_border_rounded,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Saves',
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PianoSavePanel(),
                    ),
                  ),
                ),
                IconBtn(
                  icon: Icons.tune_rounded,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Settings',
                    child: _PianoTuneSheetContent(),
                  ),
                ),
              ],
            ),
            Expanded(
              child: GlassFrame(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: _VerticalPianoCanvas(
                  range: state.currentRange,
                  // Octave-specific selection: identify the exact pitch by
                  // MIDI, not by pitch class. Tap C4 → only the C4 row lights
                  // up, not C2/C3/C5.
                  selectedMidis: state.selectedKeys.map((k) => k.midiNote).toSet(),
                  viewMode: state.viewMode,
                  onTapMidi: (midi, name) {
                    HapticFeedback.selectionClick();
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
                DockTab(
                  icon: Icons.piano_outlined,
                  label: 'Range',
                  color: MuzicianTheme.sky,
                  hasValue: state.currentRange != PianoRangeName.key88,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Range',
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PianoRangeSelector(),
                    ),
                  ),
                ),
                DockTab(
                  icon: Icons.stacked_line_chart,
                  label: 'Scale',
                  color: MuzicianTheme.emerald,
                  hasValue: activeScale != null || state.highlightedNotes.isNotEmpty,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Scale',
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PianoScalePicker(),
                    ),
                  ),
                ),
                DockTab(
                  icon: Icons.library_music_outlined,
                  label: 'Chord',
                  color: MuzicianTheme.violet,
                  hasValue: activeChord != null,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Chord',
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PianoChordPicker(),
                    ),
                  ),
                ),
                DockTab(
                  icon: Icons.auto_fix_high_rounded,
                  label: 'Detect',
                  color: MuzicianTheme.teal,
                  hasValue: state.selectedNotes.isNotEmpty,
                  onTap: () => showWidgetSheet(
                    context: context,
                    title: 'Note detection',
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PianoNoteDetectionPanel(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

// ── Tune sheet content ─────────────────────────────────────────────────────

class _PianoTuneSheetContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final hasFilters = state.selectedKeys.isNotEmpty ||
        state.highlightedNotes.isNotEmpty ||
        state.focusedNotes.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasFilters) ...[
            ClearAllButton(
              onClear: () {
                HapticFeedback.mediumImpact();
                notifier.clearSelectedNotes();
                notifier.setHighlightedNotes([]);
                ref.read(pianoActiveScaleProvider.notifier).state = null;
                ref.read(pianoActiveChordProvider.notifier).state = null;
                Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: 16),
          ],
          const _TuneSectionLabel('View mode'),
          ModeSegment<PianoViewMode>(
            current: state.viewMode,
            onSelect: notifier.setViewMode,
            options: const [
              (PianoViewMode.exact, Icons.visibility_rounded, 'Exact'),
              (PianoViewMode.exactFocus, Icons.center_focus_strong_rounded, 'Solo'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TuneSectionLabel extends StatelessWidget {
  final String label;
  const _TuneSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: MuzicianTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Vertical canvas ─────────────────────────────────────────────────────────

class _VerticalPianoCanvas extends StatefulWidget {
  final PianoRangeName range;
  final Set<int> selectedMidis; // exact MIDI pitches (octave-specific).
  final PianoViewMode viewMode;
  final void Function(int midi, String name) onTapMidi;
  const _VerticalPianoCanvas({
    required this.range,
    required this.selectedMidis,
    required this.viewMode,
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
    final allKeys = getKeysForRange(widget.range).reversed.toList();
    // Solo mode = production "exactFocus": show only EXACT tapped pitches.
    // The scale highlight does NOT spread across octaves here; tap C4 and
    // only C4 is visible, not every C in the range.
    final keys = widget.viewMode == PianoViewMode.exactFocus
        ? allKeys.where((k) => widget.selectedMidis.contains(k.midiNote)).toList()
        : allKeys;
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
                // Octave-specific selection: this row matches only if the
                // EXACT midi was tapped (k.noteName is pitch-class only).
                final selected = widget.selectedMidis.contains(k.midiNote);
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
          // Realistic key colors. Selected = cyan overlay (production tap).
          color: selected
              ? MuzicianTheme.sky
              : isBlack
                  ? const Color(0xFF18181D)
                  : const Color(0xFFEDEDE6),
          border: Border(
            left: BorderSide(
              color: selected
                  ? MuzicianTheme.scaffoldBg
                  : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: MuzicianTheme.scaffoldBg.withValues(alpha: 0.7),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: Text(
                '$name$octave',
                style: TextStyle(
                  color: selected
                      ? MuzicianTheme.scaffoldBg
                      : isBlack
                          ? const Color(0xFFB8BCC8)
                          : const Color(0xFF1A1A22),
                  fontSize: isC ? 13 : 11,
                  fontWeight: isC || selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: MuzicianTheme.scaffoldBg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
