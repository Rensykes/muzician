/// ChordDiagram – compact CustomPainter chord diagram showing 6 strings × 4 frets.
library;

import 'package:flutter/material.dart';
import '../../models/fretboard.dart';
import '../../theme/muzician_theme.dart';

const double _svgW = 80;
const double _svgH = 98;
const double _ml = 18;
const double _mr = 6;
const double _mt = 22;
const double _mb = 6;
const int _strings = 6;
const int _slots = 4;
final double _sg = (_svgW - _ml - _mr) / (_strings - 1);
final double _fg = (_svgH - _mt - _mb) / _slots;

double _colX(int col) => _ml + col * _sg;
int _stringToCol(int stringIndex) => _strings - 1 - stringIndex;
double _wireY(int slot) => _mt + slot * _fg;
double _dotY(int fret, int displayBase) => _mt + (fret - displayBase) * _fg + _fg / 2;

class ChordDiagram extends StatelessWidget {
  final ChordVoicing voicing;
  final String? rootNote;
  final List<String> openNotes;
  final bool isSelected;
  final VoidCallback onPress;

  const ChordDiagram({
    super.key,
    required this.voicing,
    this.rootNote,
    required this.openNotes,
    required this.isSelected,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPress,
      child: Container(
        width: _svgW,
        height: _svgH,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected
              ? MuzicianTheme.sky.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: isSelected
                ? MuzicianTheme.sky.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: CustomPaint(
          size: const Size(_svgW, _svgH),
          painter: _ChordDiagramPainter(
            voicing: voicing,
            rootNote: rootNote,
            openNotes: openNotes,
          ),
        ),
      ),
    );
  }
}

class _ChordDiagramPainter extends CustomPainter {
  final ChordVoicing voicing;
  final String? rootNote;
  final List<String> openNotes;

  _ChordDiagramPainter({
    required this.voicing,
    this.rootNote,
    required this.openNotes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final displayBase = voicing.baseFret < 1 ? 1 : voicing.baseFret;
    final isOpen = voicing.baseFret <= 1;

    // Fret label
    if (!isOpen) {
      final tp = TextPainter(
        text: TextSpan(
          text: '${displayBase}fr',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_ml - 4 - tp.width, _wireY(0)));
    }

    // Fret wires
    for (int i = 0; i <= _slots; i++) {
      canvas.drawLine(
        Offset(_ml, _wireY(i)),
        Offset(_ml + (_strings - 1) * _sg, _wireY(i)),
        Paint()
          ..color = (i == 0 && isOpen)
              ? const Color(0xFFCBD5E1)
              : Colors.white.withValues(alpha: 0.18)
          ..strokeWidth = (i == 0 && isOpen) ? 3 : 0.75
          ..strokeCap = StrokeCap.round,
      );
    }

    // String lines
    for (int col = 0; col < _strings; col++) {
      canvas.drawLine(
        Offset(_colX(col), _wireY(0)),
        Offset(_colX(col), _wireY(_slots)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.20)
          ..strokeWidth = 0.75,
      );
    }

    // Per-string marks
    for (int si = 0; si < voicing.positions.length; si++) {
      final fret = voicing.positions[si];
      final col = _stringToCol(si);
      final cx = _colX(col);

      if (fret == null) {
        // Muted
        final tp = TextPainter(
          text: const TextSpan(
            text: '×',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, _mt - 7 - tp.height));
      } else if (fret == 0) {
        // Open
        final openNote = si < openNotes.length ? openNotes[si] : '';
        final isRoot = rootNote != null && openNote == rootNote;
        final tp = TextPainter(
          text: TextSpan(
            text: '○',
            style: TextStyle(
              color: isRoot ? MuzicianTheme.sky : const Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, _mt - 7 - tp.height));
      } else {
        // Fretted dot
        final cy = _dotY(fret, displayBase);
        if (cy < _mt - _fg / 2 || cy > _wireY(_slots) + _fg / 2) continue;
        final fill = (rootNote != null &&
                si < openNotes.length &&
                openNotes[si] == rootNote)
            ? MuzicianTheme.sky
            : const Color(0xFF7C3AED);
        canvas.drawCircle(Offset(cx, cy), _fg * 0.32, Paint()..color = fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChordDiagramPainter old) =>
      old.voicing != voicing ||
      old.rootNote != rootNote ||
      old.openNotes != openNotes;
}
