/// GuitarFretboard – CustomPainter-driven fretboard rendering all note names
/// across 6 strings and up to 12 frets. Dimensions calculated mathematically.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart';
import '../../store/fretboard_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';

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

/// Returns the horizontal scroll offset that places [fret] at ~8 px from the
/// left viewport edge (accounting for the 16 px content padding).
double _scrollOffsetForFret(int fret) {
  if (fret <= 0) return 0;
  return _fretWireX(fret - 1) + 8.0;
}

class GuitarFretboard extends ConsumerStatefulWidget {
  const GuitarFretboard({super.key});

  @override
  ConsumerState<GuitarFretboard> createState() => _GuitarFretboardState();
}

class _GuitarFretboardState extends ConsumerState<GuitarFretboard> {
  // Track pointer movement to distinguish tap from scroll-drag.
  Offset? _pointerDownLocal;
  static const _scrollThreshold = 6.0;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _animateToFret(int fret) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollOffsetForFret(fret).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final tuning = tunings[state.currentTuning]!;
    final cells = notifier.getFretCells();
    final numFrets = state.numFrets;
    final capo = state.capo;

    ref.listen(fretboardProvider.select((s) => s.capo), (_, next) {
      _animateToFret(next);
    });

    ref.listen(scrollToFretProvider, (_, next) {
      if (next == null) return;
      _animateToFret(next);
      ref.read(scrollToFretProvider.notifier).state = null;
    });

    final svgWidth = _labelW + _openColW + _nutW + numFrets * _fretW + 12;
    final svgHeight = _headerH + _numStrings * _stringH + _vPad;

    return Column(
      children: [
        _ViewModeBar(
          current: state.viewMode,
          onSelect: notifier.setViewMode,
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Listener(
            onPointerDown: (e) => _pointerDownLocal = e.localPosition,
            onPointerUp: (e) {
              final down = _pointerDownLocal;
              if (down == null) return;
              final delta = (e.localPosition - down).distance;
              if (delta >= _scrollThreshold) return;
              _handleTap(e.localPosition, cells, numFrets, capo, notifier);
            },
            onPointerCancel: (_) => _pointerDownLocal = null,
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
        ),
      ],
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
          _guardOutOfKey(
            noteName: cell.noteName,
            onConfirmed: () =>
                notifier.toggleCell(cell.stringIndex, cell.fret, cell.noteName),
            notifier: notifier,
          );
          return;
        }
      }
    }
  }

  Future<void> _guardOutOfKey({
    required String noteName,
    required VoidCallback onConfirmed,
    required FretboardNotifier notifier,
  }) async {
    final highlighted = ref.read(fretboardProvider).highlightedNotes;
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
    if (result == null) return; // user dismissed
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
                      ? const Icon(Icons.check, size: 12, color: MuzicianTheme.sky)
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
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_OutOfKeyResult(suppress: _suppress)),
          child: const Text('Continue',
              style: TextStyle(
                  color: MuzicianTheme.sky,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─── View Mode Bar ─────────────────────────────────────────────────────────────

class _ViewModeBar extends StatelessWidget {
  final FretboardViewMode current;
  final void Function(FretboardViewMode) onSelect;

  const _ViewModeBar({required this.current, required this.onSelect});

  static const _modes = [
    (FretboardViewMode.pitchClass, 'All', 'All occurrences'),
    (FretboardViewMode.exact, 'Exact', 'Tapped positions only'),
    (FretboardViewMode.focus, 'Focus', 'Hide unselected'),
    (FretboardViewMode.exactFocus, 'Solo', 'Exact positions only'),
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
        final inFocusOrSolo = viewMode == FretboardViewMode.focus ||
            viewMode == FretboardViewMode.exactFocus;
        final opacity = behindCapo
            ? 0.18
            : isSelected
                ? 1.0
                : (inFocusOrSolo || highlightedNotes.isEmpty)
                    ? 0.88
                    : (isHighlighted ? 1.0 : 0.25);

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
