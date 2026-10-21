/// PianoChordDiagram – compact CustomPainter keyboard showing 2 octaves with the
/// voicing's keys highlighted. Piano analogue of the fretboard [ChordDiagram].
library;

import 'package:flutter/material.dart';
import '../../theme/studio_theme.dart';

const double _kbW = 126;
const double _kbH = 52;
const int _whiteKeys = 14; // 2 octaves of C..B
const _whitePcs = [0, 2, 4, 5, 7, 9, 11];
// White indices (within an octave) that have a black key to their right.
const _blackAfter = {0, 1, 3, 4, 5};
const _blackPcByWhite = {0: 1, 1: 3, 3: 6, 4: 8, 5: 10};

class PianoChordDiagram extends StatelessWidget {
  /// Absolute midi notes of the voicing (already filtered to existing keys).
  final List<int> midis;

  /// Root pitch class ([noteToPC] of the chord root); null hides the root tint.
  final int? rootPc;

  /// Voicing label, e.g. "Root", "1 inv".
  final String label;

  /// Chord tone names for the text row, e.g. ["C", "E", "G"].
  final List<String> noteLabels;

  final bool isSelected;
  final VoidCallback onPress;

  const PianoChordDiagram({
    super.key,
    required this.midis,
    required this.rootPc,
    required this.label,
    required this.noteLabels,
    required this.isSelected,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    final studio = StudioPalette.of(context).isStudio;
    final keyboardWidth = studio ? 86.0 : _kbW;
    final cardWidth = 16 + MediaQuery.textScalerOf(context).scale(86);
    final keyboardHeight = studio ? 44.0 : _kbH;
    return GestureDetector(
      onTap: onPress,
      child: Container(
        width: studio ? cardWidth : null,
        constraints: BoxConstraints(minWidth: studio ? cardWidth : _kbW + 16),
        margin: EdgeInsets.only(right: studio ? 0 : 8),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: studio ? 6 : 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(studio ? 6 : 12),
          color: isSelected
              ? StudioPalette.of(context).violet.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected
                ? StudioPalette.of(context).violet.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.14),
            width: isSelected ? 1.0 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? StudioPalette.of(context).violet
                    : StudioPalette.of(context).textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: studio ? 4 : 6),
            CustomPaint(
              size: Size(keyboardWidth, keyboardHeight),
              painter: _PianoChordPainter(
                colors: StudioPalette.of(context),
                midis: midis,
                rootPc: rootPc,
              ),
            ),
            SizedBox(height: studio ? 4 : 6),
            Text(
              noteLabels.join(' '),
              style: TextStyle(
                color: StudioPalette.of(context).textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PianoChordPainter extends CustomPainter {
  final StudioPalette colors;
  final List<int> midis;
  final int? rootPc;

  _PianoChordPainter({
    required this.colors,
    required this.midis,
    required this.rootPc,
  });

  Color _fillFor(int midi) =>
      (rootPc != null && midi % 12 == rootPc) ? colors.sky : colors.violet;

  @override
  void paint(Canvas canvas, Size size) {
    if (midis.isEmpty) return;
    final midiSet = midis.toSet();
    final windowStart = (midis.reduce((a, b) => a < b ? a : b) ~/ 12) * 12;

    final whiteW = size.width / _whiteKeys;
    final blackW = whiteW * 0.62;
    final blackH = size.height * 0.6;

    // White keys
    final whiteFill = Paint()..color = const Color(0xFFF1F5F9);
    final stroke = Paint()
      ..color = const Color(0xFF0A0F1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < _whiteKeys; i++) {
      final x = i * whiteW;
      final rect = Rect.fromLTWH(x, 0, whiteW - 0.5, size.height);
      canvas.drawRect(rect, whiteFill);
      canvas.drawRect(rect, stroke);
      final midi = windowStart + (i ~/ 7) * 12 + _whitePcs[i % 7];
      if (midiSet.contains(midi)) {
        canvas.drawRect(
          rect,
          Paint()..color = _fillFor(midi).withValues(alpha: 0.6),
        );
      }
    }

    // Black keys (drawn on top)
    final blackFill = Paint()..color = const Color(0xFF0A0F1E);
    for (var i = 0; i < _whiteKeys - 1; i++) {
      final within = i % 7;
      if (!_blackAfter.contains(within)) continue;
      final x = (i + 1) * whiteW - blackW / 2;
      final rect = Rect.fromLTWH(x, 0, blackW, blackH);
      canvas.drawRect(rect, blackFill);
      final midi = windowStart + (i ~/ 7) * 12 + _blackPcByWhite[within]!;
      if (midiSet.contains(midi)) {
        canvas.drawRect(
          rect,
          Paint()..color = _fillFor(midi).withValues(alpha: 0.9),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PianoChordPainter old) =>
      old.colors != colors || old.midis != midis || old.rootPc != rootPc;
}
