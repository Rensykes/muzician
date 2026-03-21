/// GuitarFretboard – CustomPainter-driven fretboard rendering all note names
/// across 6 strings and up to 12 frets. Dimensions calculated mathematically.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';

// ─── Layout Constants ──────────────────────────────────────────────────────────

const double _labelW = 32;
const double _openColW = 52;
const double _nutW = 7;
const double _fretW = 66;
const double _stringH = 50;
const double _headerH = 30;
const double _vPad = 14;
const int _numStrings = 6;

double _stringY(int idx) => _headerH + idx * _stringH + _stringH / 2;
double _noteX(int fret) {
  if (fret == 0) return _labelW + _openColW / 2;
  return _labelW + _openColW + _nutW + (fret - 1) * _fretW + _fretW / 2;
}

double _fretWireX(int fretIndex) {
  if (fretIndex == 0) return _labelW + _openColW;
  return _labelW + _openColW + _nutW + fretIndex * _fretW;
}

class GuitarFretboard extends ConsumerWidget {
  const GuitarFretboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final tuning = tunings[state.currentTuning]!;
    final cells = notifier.getFretCells();
    final numFrets = state.numFrets;
    final capo = state.capo;

    final svgWidth = _labelW + _openColW + _nutW + numFrets * _fretW + 12;
    final svgHeight = _headerH + _numStrings * _stringH + _vPad;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTapDown: (details) {
          _handleTap(details.localPosition, cells, numFrets, capo, notifier);
        },
        child: CustomPaint(
          size: Size(svgWidth, svgHeight),
          painter: _FretboardPainter(
            tuning: tuning,
            cells: cells,
            numFrets: numFrets,
            capo: capo,
            highlightedNotes: state.highlightedNotes,
            selectedNotes: state.selectedNotes,
            selectedCells: state.selectedCells,
            viewMode: state.viewMode,
          ),
        ),
      ),
    );
  }

  void _handleTap(
    Offset pos,
    List<List<FretCell>> cells,
    int numFrets,
    int capo,
    FretboardNotifier notifier,
  ) {
    const hitRadius = 18.0;
    for (final stringCells in cells) {
      for (final cell in stringCells) {
        if (capo > 0 && cell.fret < capo) continue;
        final cx = _noteX(cell.fret);
        final cy = _stringY(cell.stringIndex);
        final dx = pos.dx - cx;
        final dy = pos.dy - cy;
        if (math.sqrt(dx * dx + dy * dy) <= hitRadius) {
          notifier.toggleCell(cell.stringIndex, cell.fret, cell.noteName);
          return;
        }
      }
    }
  }
}

// ─── Painter ───────────────────────────────────────────────────────────────────

class _FretboardPainter extends CustomPainter {
  final Tuning tuning;
  final List<List<FretCell>> cells;
  final int numFrets;
  final int capo;
  final List<String> highlightedNotes;
  final List<String> selectedNotes;
  final List<FretCoordinate> selectedCells;
  final FretboardViewMode viewMode;

  _FretboardPainter({
    required this.tuning,
    required this.cells,
    required this.numFrets,
    required this.capo,
    required this.highlightedNotes,
    required this.selectedNotes,
    required this.selectedCells,
    required this.viewMode,
  });

  static const _naturalColor = Color(0xFF38BDF8);
  static const _accidentalColor = Color(0xFFC084FC);
  static const _boardDark = Color(0xFF1A0D00);
  static const _boardMid = Color(0xFF3D1F00);
  static const _stringBase = Color(0xFFC8A050);
  static const _fretWireColor = Color(0xFF9AA5AE);
  static const _nutColor = Color(0xFFE8E4D8);
  static const _markerFill = Color(0x1AFFFFFF);
  static const _stringLabel = Color(0xFF94A3B8);
  static const _fretNumber = Color(0xFF64748B);
  static const _stringWidths = [0.8, 1.0, 1.3, 1.7, 2.1, 2.6];

  @override
  void paint(Canvas canvas, Size size) {
    _drawBoard(canvas, size);
    _drawFretWires(canvas);
    _drawCapo(canvas);
    _drawPositionMarkers(canvas);
    _drawStrings(canvas, size);
    _drawStringLabels(canvas);
    _drawFretNumbers(canvas);
    _drawNoteBubbles(canvas);
  }

  void _drawBoard(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _labelW,
      _headerH,
      size.width - _labelW,
      _numStrings * _stringH,
    );
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_boardMid, _boardDark],
    );
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );
  }

  void _drawFretWires(Canvas canvas) {
    for (int i = 0; i <= numFrets; i++) {
      final x = _fretWireX(i);
      final isNut = i == 0;
      final paint = Paint()
        ..color = isNut ? _nutColor : _fretWireColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(x, _headerH, isNut ? _nutW : 1.5, _numStrings * _stringH),
        paint,
      );
    }
  }

  void _drawCapo(Canvas canvas) {
    if (capo <= 0) return;
    final x = _fretWireX(capo);
    // Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 3, _headerH - 2, 14, _numStrings * _stringH + 4),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0x2EFB923C),
    );
    // Bar
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 1, _headerH, 10, _numStrings * _stringH.toDouble()),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xEBFB923C),
    );
    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: 'CAPO $capo',
        style: const TextStyle(
          color: Color(0xFFFB923C),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x + 4 - tp.width / 2, _headerH - 9 - tp.height));
  }

  void _drawPositionMarkers(Canvas canvas) {
    final midY = _headerH + (_numStrings * _stringH) / 2;
    final paint = Paint()..color = _markerFill;
    for (final fret in positionMarkerFrets) {
      if (fret > numFrets) continue;
      final x = _noteX(fret);
      if (fret == 12) {
        canvas.drawCircle(Offset(x, midY - _stringH * 1.5), 5, paint);
        canvas.drawCircle(Offset(x, midY + _stringH * 1.5), 5, paint);
      } else {
        canvas.drawCircle(Offset(x, midY), 5, paint);
      }
    }
  }

  void _drawStrings(Canvas canvas, Size size) {
    for (int si = 0; si < tuning.strings.length; si++) {
      final y = _stringY(si);
      canvas.drawLine(
        Offset(_labelW, y),
        Offset(size.width - 6, y),
        Paint()
          ..color = _stringBase.withValues(alpha: 0.75)
          ..strokeWidth = _stringWidths[si],
      );
    }
  }

  void _drawStringLabels(Canvas canvas) {
    for (int si = 0; si < tuning.strings.length; si++) {
      final label = tuning.strings[si].note.replaceAll(RegExp(r'\d'), '');
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: _stringLabel,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(_labelW / 2 - tp.width / 2, _stringY(si) - tp.height / 2),
      );
    }
  }

  void _drawFretNumbers(Canvas canvas) {
    for (int fret = 0; fret <= numFrets; fret++) {
      final showLabel = fret == 0 ||
          positionMarkerFrets.contains(fret);
      if (!showLabel) continue;
      final text = fret == 0 ? 'Open' : '$fret';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: _fretNumber, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_noteX(fret) - tp.width / 2, _headerH - 8 - tp.height));
    }
  }

  void _drawNoteBubbles(Canvas canvas) {
    for (final stringCells in cells) {
      for (final cell in stringCells) {
        final cx = _noteX(cell.fret);
        final cy = _stringY(cell.stringIndex);
        final r = cell.fret == 0 ? 13.0 : 15.0;
        final fs = cell.fret == 0 ? 8.0 : 9.0;
        final behindCapo = capo > 0 && cell.fret < capo;

        final isSelectedExact = selectedCells.any(
          (c) => c.stringIndex == cell.stringIndex && c.fret == cell.fret,
        );
        final isSelectedPitchClass = selectedNotes.contains(cell.noteName);
        final isSelected =
            (viewMode == FretboardViewMode.exact ||
                    viewMode == FretboardViewMode.exactFocus)
                ? isSelectedExact
                : isSelectedPitchClass;

        final inFocusMode =
            viewMode == FretboardViewMode.focus && selectedNotes.isNotEmpty;
        if (inFocusMode && !isSelectedPitchClass && !behindCapo) continue;

        final inExactFocusMode =
            viewMode == FretboardViewMode.exactFocus && selectedCells.isNotEmpty;
        if (inExactFocusMode && !isSelectedExact && !behindCapo) continue;

        final isHighlighted = highlightedNotes.isNotEmpty &&
            highlightedNotes.contains(cell.noteName);

        final baseColor =
            behindCapo ? const Color(0xFF334155) : (cell.isNatural ? _naturalColor : _accidentalColor);
        final bubbleFill = isSelected ? Colors.white : baseColor;
        final bubbleStroke = isSelected
            ? baseColor
            : (cell.fret == 0 ? const Color(0x40FFFFFF) : Colors.transparent);
        final strokeWidth = isSelected ? 2.5 : (cell.fret == 0 ? 1.0 : 0.0);
        final textColor = isSelected ? baseColor : Colors.white;
        final opacity = behindCapo
            ? 0.18
            : isSelected
                ? 1.0
                : highlightedNotes.isNotEmpty
                    ? (isHighlighted ? 1.0 : 0.25)
                    : 0.88;

        // Draw circle
        final fillPaint = Paint()
          ..color = bubbleFill.withValues(alpha: 0.95 * opacity);
        canvas.drawCircle(Offset(cx, cy), r, fillPaint);

        if (strokeWidth > 0) {
          final strokePaint = Paint()
            ..color = bubbleStroke.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth;
          canvas.drawCircle(Offset(cx, cy), r, strokePaint);
        }

        // Draw text
        final tp = TextPainter(
          text: TextSpan(
            text: cell.noteName,
            style: TextStyle(
              color: textColor.withValues(alpha: opacity),
              fontSize: fs,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) =>
      old.numFrets != numFrets ||
      old.capo != capo ||
      old.tuning.name != tuning.name ||
      old.viewMode != viewMode ||
      old.selectedNotes != selectedNotes ||
      old.selectedCells != selectedCells ||
      old.highlightedNotes != highlightedNotes;
}
