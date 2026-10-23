/// PianoKeyboard – interactive keyboard with horizontal scroll.
/// Uses CustomPainter for high-performance rendering.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../schema/rules/piano_rules.dart';
import '../../models/save_system.dart';
import '../../store/piano_store.dart';
import '../../store/save_system_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/out_of_key_dialog.dart';
import '../../ui/core/project_off_scale_dialog.dart';
import '../../utils/note_player.dart';
import '../../utils/note_utils.dart' as note_utils;

const double _whiteKeyW = 42;
const double _blackKeyW = 26;
const double _whiteKeyH = 210;
const double _blackKeyH = 130;

/// Height the keyboard needs to render without clipping a key: the tallest
/// (white) key plus the horizontal scroll view's vertical padding (12), the
/// glass-frame padding (8) and margin (8) the host wraps it in, plus a small
/// safety buffer. Pin the keyboard to this so no key clips and the detection
/// area below takes the remaining space.
const double pianoKeyboardHeight = _whiteKeyH + 12 + 8 + 8 + 6;

/// Returns the horizontal scroll offset that places [midi] near the left edge.
double _scrollOffsetForMidi(int midi, PianoRangeName range) {
  final startMidi = pianoRanges[range]!.startMidi;
  var whiteCount = 0;
  for (var m = startMidi; m < midi; m++) {
    if (!isBlackMidiKey(m)) whiteCount++;
  }
  return (whiteCount * _whiteKeyW - 32.0).clamp(0.0, double.maxFinite);
}

class PianoKeyboard extends ConsumerStatefulWidget {
  /// When true, suppress the built-in view-mode toolbar. The V2 shell
  /// renders an equivalent segmented control above the canvas.
  final bool hideToolbar;

  /// When non-null, render these MIDI keys as a controlled, read-only overlay.
  /// This is used by Writer so inspecting a melody never changes the user's
  /// Piano selection or detection state. An empty set is still controlled mode.
  final Set<int>? controlledMidiNotes;

  const PianoKeyboard({
    super.key,
    this.hideToolbar = false,
    this.controlledMidiNotes,
  });

  @override
  ConsumerState<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends ConsumerState<PianoKeyboard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _animateToMidi(int midi) {
    if (!_scrollController.hasClients) return;
    final range = ref.read(pianoProvider).currentRange;
    _scrollController.animateTo(
      _scrollOffsetForMidi(
        midi,
        range,
      ).clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final notifier = ref.read(pianoProvider.notifier);
    final keys = notifier.getKeys();

    if (widget.controlledMidiNotes == null) {
      ref.listen(pianoScrollToMidiProvider, (_, next) {
        if (next == null) return;
        _animateToMidi(next);
        ref.read(pianoScrollToMidiProvider.notifier).state = null;
      });
    }

    // Position keys
    final positioned = <_PosKey>[];
    int whiteIndex = 0;
    for (final key in keys) {
      if (!key.isBlack) {
        positioned.add(_PosKey(key: key, x: whiteIndex * _whiteKeyW));
        whiteIndex++;
      } else {
        positioned.add(
          _PosKey(key: key, x: whiteIndex * _whiteKeyW - _blackKeyW / 2),
        );
      }
    }

    final totalWidth = whiteIndex * _whiteKeyW;

    return Column(
      children: [
        if (!widget.hideToolbar) ...[
          _ViewModeBar(current: state.viewMode, onSelect: notifier.setViewMode),
          const SizedBox(height: 4),
        ],
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: totalWidth,
            height: StudioPalette.of(context).isStudio && widget.hideToolbar
                ? 190
                : _whiteKeyH,
            child: Stack(
              children: [
                // White keys first
                ...positioned
                    .where((pk) => !pk.key.isBlack)
                    .map((pk) => _buildKey(pk, state, notifier, spelling)),
                // Black keys on top
                ...positioned
                    .where((pk) => pk.key.isBlack)
                    .map((pk) => _buildKey(pk, state, notifier, spelling)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKey(
    _PosKey pk,
    PianoState state,
    PianoNotifier notifier,
    note_utils.NoteSpelling spelling,
  ) {
    final key = pk.key;
    final controlledNotes = widget.controlledMidiNotes;
    final isControlled = controlledNotes != null;
    final selectedExact = state.selectedKeys.any(
      (k) => k.midiNote == key.midiNote,
    );
    final isSelected = isControlled
        ? controlledNotes.contains(key.midiNote)
        : selectedExact;

    // focusedNotes: pitch classes tapped in the detection panel.
    final isFocusedPitchClass =
        !isControlled && state.focusedNotes.contains(key.noteName);

    // Keep every physical key playable; Solo filters labels only.
    final showLabel =
        isControlled || state.viewMode == PianoViewMode.exact || isSelected;

    final isHighlighted =
        state.highlightedNotes.isNotEmpty &&
        state.highlightedNotes.contains(key.noteName);

    final opacity = isControlled
        ? (isSelected ? 1.0 : 0.72)
        : (isSelected || isFocusedPitchClass)
        ? 1.0
        : (state.focusedNotes.isNotEmpty)
        ? 0.25
        : (state.highlightedNotes.isNotEmpty)
        ? (isHighlighted ? 1.0 : 0.3)
        : 1.0;

    final baseBg = key.isBlack
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);
    final accentBg = key.isNatural
        ? StudioPalette.of(context).sky
        : StudioPalette.of(context).purple;
    final bgColor = (isSelected || isFocusedPitchClass) ? accentBg : baseBg;
    final keyContent = Container(
      width: key.isBlack ? _blackKeyW : _whiteKeyW,
      height: StudioPalette.of(context).isStudio && widget.hideToolbar
          ? (key.isBlack ? 118 : 190)
          : (key.isBlack ? _blackKeyH : _whiteKeyH),
      decoration: BoxDecoration(
        color: StudioPalette.of(context).isStudio
            ? Color.lerp(baseBg, bgColor, opacity)
            : bgColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(key.isBlack ? 6 : 8),
          bottomRight: Radius.circular(key.isBlack ? 6 : 8),
        ),
        border: Border.all(
          color: (isSelected || isFocusedPitchClass)
              ? StudioPalette.of(context).onAccent.withValues(alpha: 0.8)
              : key.isBlack
              ? Colors.white.withValues(alpha: 0.2)
              : const Color(0x330F172A),
          width: 1,
        ),
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 8),
      child: showLabel
          ? Text(
              note_utils.formatMidiNoteLabel(key.midiNote, spelling: spelling),
              style: TextStyle(
                color: (isSelected || isFocusedPitchClass)
                    ? StudioPalette.of(context).onAccent
                    : key.isBlack
                    ? StudioPalette.of(context).textPrimary
                    : const Color(0xFF0F172A),
                fontSize: key.isBlack ? 9 : 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            )
          : null,
    );

    return Positioned(
      left: pk.x,
      top: 0,
      child: Opacity(
        opacity: StudioPalette.of(context).isStudio ? 1 : opacity,
        child: Semantics(
          label:
              '${note_utils.formatMidiNoteLabel(key.midiNote, spelling: spelling)}, MIDI ${key.midiNote}'
              '${isSelected ? ', melody note' : ''}',
          excludeSemantics: true,
          selected: isSelected,
          child: GestureDetector(
            onTap: isControlled
                ? null
                : () {
                    NotePlayer.instance.previewNote(
                      key.midiNote,
                      volume: ref.read(settingsProvider).noteVolume,
                    );
                    _guardOutOfKey(
                      noteName: key.noteName,
                      onConfirmed: () => notifier.toggleKey(
                        key.keyIndex,
                        key.midiNote,
                        key.noteName,
                      ),
                      notifier: notifier,
                    );
                  },
            child: keyContent,
          ),
        ),
      ),
    );
  }

  Future<void> _guardOutOfKey({
    required String noteName,
    required VoidCallback onConfirmed,
    required PianoNotifier notifier,
  }) async {
    final highlighted = ref.read(pianoProvider).highlightedNotes;
    if (highlighted.isEmpty || highlighted.contains(noteName)) {
      onConfirmed();
      return;
    }

    final project = ref.read(selectedProjectProvider);
    if (project != null && project.kind == SaveFolderKind.project) {
      if (!mounted) return;
      final decision = await showStudioDialog<ProjectOffScaleDecision>(
        context: context,
        builder: (ctx) => ProjectOffScaleDialog(
          projectName: project.name,
          keyLabel: _keyLabelFor(
            project,
            ref.read(settingsProvider).noteSpelling,
          ),
          noteName: note_utils.formatRootChoiceLabel(
            noteName,
            spelling: ref.read(settingsProvider).noteSpelling,
          ),
        ),
      );
      if (decision != ProjectOffScaleDecision.switchToDump) return;
      final dumpId = ref.read(saveSystemProvider.notifier).ensureDumpFolder();
      ref.read(saveSystemProvider.notifier).selectProject(dumpId);
      notifier.setHighlightedNotes([]);
      onConfirmed();
      return;
    }

    final suppress = ref.read(settingsProvider).suppressOutOfKeyAlert;
    if (suppress) {
      notifier.setHighlightedNotes([]);
      onConfirmed();
      return;
    }

    if (!mounted) return;
    final result = await showStudioDialog<OutOfKeyResult>(
      context: context,
      builder: (ctx) => const OutOfKeyDialog(),
    );
    if (result == null) return;
    if (result.suppress) {
      await ref.read(settingsProvider.notifier).setSuppressOutOfKeyAlert(true);
    }
    notifier.setHighlightedNotes([]);
    onConfirmed();
  }

  String _keyLabelFor(SaveFolder project, note_utils.NoteSpelling spelling) {
    final cfg = project.projectConfig;
    if (cfg?.keyRootPc == null) return 'the project key';
    final root = note_utils.formatRootChoiceLabel(
      note_utils.chromaticNotes[cfg!.keyRootPc!],
      spelling: spelling,
    );
    final scale = cfg.keyScaleName ?? '';
    return '$root $scale'.trim();
  }
}

// ─── Position Key ─────────────────────────────────────────────────────────────

class _PosKey {
  final PianoKeyCell key;
  final double x;
  const _PosKey({required this.key, required this.x});
}

// ─── View Mode Bar ─────────────────────────────────────────────────────────────

class _ViewModeBar extends StatelessWidget {
  final PianoViewMode current;
  final void Function(PianoViewMode) onSelect;

  const _ViewModeBar({required this.current, required this.onSelect});

  static const _modes = [
    (PianoViewMode.exact, 'Full', 'All note labels'),
    (PianoViewMode.exactFocus, 'Solo', 'Selected note labels'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: _modes.map((m) {
          final active = current == m.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                onSelect(m.$1);
                HapticFeedback.lightImpact();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? StudioPalette.of(context).sky.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: active
                        ? StudioPalette.of(context).sky.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      m.$2,
                      style: TextStyle(
                        color: active
                            ? StudioPalette.of(context).sky
                            : StudioPalette.of(context).textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      m.$3,
                      style: TextStyle(
                        color: active
                            ? StudioPalette.of(
                                context,
                              ).sky.withValues(alpha: 0.6)
                            : StudioPalette.of(context).textMuted,
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
