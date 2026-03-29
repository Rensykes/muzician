/// PianoKeyboard – interactive keyboard with horizontal scroll.
/// Uses CustomPainter for high-performance rendering.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../schema/rules/piano_rules.dart';
import '../../store/piano_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/out_of_key_dialog.dart';

const double _whiteKeyW = 42;
const double _blackKeyW = 26;
const double _whiteKeyH = 210;
const double _blackKeyH = 130;

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
  const PianoKeyboard({super.key});

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
      _scrollOffsetForMidi(midi, range).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final keys = notifier.getKeys();

    ref.listen(pianoScrollToMidiProvider, (_, next) {
      if (next == null) return;
      _animateToMidi(next);
      ref.read(pianoScrollToMidiProvider.notifier).state = null;
    });

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
        _ViewModeBar(current: state.viewMode, onSelect: notifier.setViewMode),
        const SizedBox(height: 4),
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: totalWidth,
            height: _whiteKeyH,
            child: Stack(
              children: [
                // White keys first
                ...positioned
                    .where((pk) => !pk.key.isBlack)
                    .map((pk) => _buildKey(pk, state, notifier)),
                // Black keys on top
                ...positioned
                    .where((pk) => pk.key.isBlack)
                    .map((pk) => _buildKey(pk, state, notifier)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKey(_PosKey pk, PianoState state, PianoNotifier notifier) {
    final key = pk.key;
    final selectedExact = state.selectedKeys.any(
      (k) => k.midiNote == key.midiNote,
    );
    final isSelected = selectedExact;

    // focusedNotes: pitch classes tapped in the detection panel.
    final isFocusedPitchClass = state.focusedNotes.contains(key.noteName);

    // In Solo mode, hide keys that are neither selected nor focused.
    final inExactFocusMode =
        state.viewMode == PianoViewMode.exactFocus &&
        state.selectedKeys.isNotEmpty;
    if (inExactFocusMode && !selectedExact && !isFocusedPitchClass) {
      return const SizedBox.shrink();
    }

    final isHighlighted =
        state.highlightedNotes.isNotEmpty &&
        state.highlightedNotes.contains(key.noteName);

    final opacity = (isSelected || isFocusedPitchClass)
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
        ? MuzicianTheme.sky
        : const Color(0xFFC084FC);
    final bgColor = (isSelected || isFocusedPitchClass) ? accentBg : baseBg;

    return Positioned(
      left: pk.x,
      top: 0,
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          onTap: () => _guardOutOfKey(
            noteName: key.noteName,
            onConfirmed: () =>
                notifier.toggleKey(key.keyIndex, key.midiNote, key.noteName),
            notifier: notifier,
          ),
          child: Container(
            width: key.isBlack ? _blackKeyW : _whiteKeyW,
            height: key.isBlack ? _blackKeyH : _whiteKeyH,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(key.isBlack ? 6 : 8),
                bottomRight: Radius.circular(key.isBlack ? 6 : 8),
              ),
              border: Border.all(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : key.isBlack
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0x330F172A),
                width: 1,
              ),
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              key.noteName,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : key.isBlack
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF0F172A),
                fontSize: key.isBlack ? 9 : 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
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

    final suppress = ref.read(settingsProvider).suppressOutOfKeyAlert;
    if (suppress) {
      notifier.setHighlightedNotes([]);
      onConfirmed();
      return;
    }

    if (!mounted) return;
    final result = await showDialog<OutOfKeyResult>(
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
    (PianoViewMode.exact, 'Exact', 'Tapped positions only'),
    (PianoViewMode.exactFocus, 'Solo', 'Exact positions only'),
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
                      ? MuzicianTheme.sky.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: active
                        ? MuzicianTheme.sky.withValues(alpha: 0.4)
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
                            ? MuzicianTheme.sky
                            : MuzicianTheme.textSecondary,
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
                            ? MuzicianTheme.sky.withValues(alpha: 0.6)
                            : MuzicianTheme.textMuted,
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
