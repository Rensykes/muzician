/// PianoKeyboard – interactive keyboard with horizontal scroll.
/// Uses CustomPainter for high-performance rendering.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../store/piano_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';

const double _whiteKeyW = 42;
const double _blackKeyW = 26;
const double _whiteKeyH = 210;
const double _blackKeyH = 130;

class PianoKeyboard extends ConsumerStatefulWidget {
  const PianoKeyboard({super.key});

  @override
  ConsumerState<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends ConsumerState<PianoKeyboard> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoProvider);
    final notifier = ref.read(pianoProvider.notifier);
    final keys = notifier.getKeys();

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
    final selectedPitchClass = state.selectedNotes.contains(key.noteName);
    final isSelected =
        (state.viewMode == PianoViewMode.exact ||
            state.viewMode == PianoViewMode.exactFocus)
        ? selectedExact
        : selectedPitchClass;

    final inFocusMode =
        state.viewMode == PianoViewMode.focus && state.selectedNotes.isNotEmpty;
    if (inFocusMode && !selectedPitchClass) return const SizedBox.shrink();

    final inExactFocusMode =
        state.viewMode == PianoViewMode.exactFocus &&
        state.selectedKeys.isNotEmpty;
    if (inExactFocusMode && !selectedExact) return const SizedBox.shrink();

    final isHighlighted =
        state.highlightedNotes.isNotEmpty &&
        state.highlightedNotes.contains(key.noteName);

    final inFocusOrSolo =
        state.viewMode == PianoViewMode.focus ||
        state.viewMode == PianoViewMode.exactFocus;
    final opacity = isSelected
        ? 1.0
        : (!inFocusOrSolo && state.highlightedNotes.isNotEmpty)
        ? (isHighlighted ? 1.0 : 0.3)
        : 1.0;

    final baseBg = key.isBlack
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);
    final accentBg = key.isNatural
        ? MuzicianTheme.sky
        : const Color(0xFFC084FC);
    final bgColor = isSelected ? accentBg : baseBg;

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
    final result = await showDialog<_OutOfKeyResult>(
      context: context,
      builder: (ctx) => const _OutOfKeyDialog(),
    );
    if (result == null) return;
    if (result.suppress) {
      await ref.read(settingsProvider.notifier).setSuppressOutOfKeyAlert(true);
    }
    notifier.setHighlightedNotes([]);
    onConfirmed();
  }
}

// ─── Out-of-Key Dialog ────────────────────────────────────────────────────────

class _OutOfKeyResult {
  final bool suppress;
  const _OutOfKeyResult({required this.suppress});
}

class _OutOfKeyDialog extends StatefulWidget {
  const _OutOfKeyDialog();

  @override
  State<_OutOfKeyDialog> createState() => _OutOfKeyDialogState();
}

class _OutOfKeyDialogState extends State<_OutOfKeyDialog> {
  bool _suppress = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Outside the key',
        style: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This note is outside the highlighted scale. Adding it will clear the scale highlight.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _suppress = !_suppress),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _suppress
                        ? MuzicianTheme.sky.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      color: _suppress
                          ? MuzicianTheme.sky
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: _suppress
                      ? const Icon(
                          Icons.check,
                          size: 12,
                          color: MuzicianTheme.sky,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Don't show this again",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_OutOfKeyResult(suppress: _suppress)),
          child: const Text(
            'Continue',
            style: TextStyle(
              color: MuzicianTheme.sky,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
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
    (PianoViewMode.pitchClass, 'All', 'All occurrences'),
    (PianoViewMode.exact, 'Exact', 'Tapped positions only'),
    (PianoViewMode.focus, 'Focus', 'Hide unselected'),
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
