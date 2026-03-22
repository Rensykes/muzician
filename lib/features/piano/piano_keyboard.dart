/// PianoKeyboard – interactive keyboard with horizontal scroll.
/// Uses CustomPainter for high-performance rendering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano.dart';
import '../../store/piano_store.dart';
import '../../theme/muzician_theme.dart';

const double _whiteKeyW = 42;
const double _blackKeyW = 26;
const double _whiteKeyH = 210;
const double _blackKeyH = 130;

class PianoKeyboard extends ConsumerWidget {
  const PianoKeyboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            _PosKey(key: key, x: whiteIndex * _whiteKeyW - _blackKeyW / 2));
      }
    }

    final totalWidth = whiteIndex * _whiteKeyW;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: totalWidth,
        height: _whiteKeyH,
        child: Stack(
          children: [
            // White keys first
            ...positioned.where((pk) => !pk.key.isBlack).map((pk) =>
                _buildKey(pk, state, notifier)),
            // Black keys on top
            ...positioned.where((pk) => pk.key.isBlack).map((pk) =>
                _buildKey(pk, state, notifier)),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(
      _PosKey pk, PianoState state, PianoNotifier notifier) {
    final key = pk.key;
    final selectedExact =
        state.selectedKeys.any((k) => k.midiNote == key.midiNote);
    final selectedPitchClass = state.selectedNotes.contains(key.noteName);
    final isSelected =
        (state.viewMode == PianoViewMode.exact ||
                state.viewMode == PianoViewMode.exactFocus)
            ? selectedExact
            : selectedPitchClass;

    final inFocusMode =
        state.viewMode == PianoViewMode.focus && state.selectedNotes.isNotEmpty;
    if (inFocusMode && !selectedPitchClass) return const SizedBox.shrink();

    final inExactFocusMode = state.viewMode == PianoViewMode.exactFocus &&
        state.selectedKeys.isNotEmpty;
    if (inExactFocusMode && !selectedExact) return const SizedBox.shrink();

    final isHighlighted = state.highlightedNotes.isNotEmpty &&
        state.highlightedNotes.contains(key.noteName);

    final opacity = isSelected
        ? 1.0
        : state.highlightedNotes.isNotEmpty
            ? (isHighlighted ? 1.0 : 0.3)
            : 1.0;

    final baseBg = key.isBlack ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final accentBg = key.isNatural ? MuzicianTheme.sky : const Color(0xFFC084FC);
    final bgColor = isSelected ? accentBg : baseBg;

    return Positioned(
      left: pk.x,
      top: 0,
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          onTap: () => notifier.toggleKey(key.keyIndex, key.midiNote, key.noteName),
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
}

class _PosKey {
  final PianoKeyCell key;
  final double x;
  const _PosKey({required this.key, required this.x});
}
