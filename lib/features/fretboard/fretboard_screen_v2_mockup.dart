/// Fretboard V2 — UI/UX redesign mockup (iteration 5).
///
/// Canvas variant: VERTICAL fretboard. Strings flow top→bottom (nut at the
/// top, frets descending), six string columns left-to-right with low E on
/// the left and high E on the right — the universal vertical chord-diagram
/// convention. Reverts to the wood palette (notes need to pop; midnight
/// contrast was too low).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../models/fretboard.dart';
import '../../schema/rules/fretboard_rules.dart' show tunings;
import '../../store/fretboard_store.dart';
import '../../theme/muzician_theme.dart';

class FretboardScreenV2Mockup extends ConsumerStatefulWidget {
  const FretboardScreenV2Mockup({super.key});

  @override
  ConsumerState<FretboardScreenV2Mockup> createState() => _FretboardScreenV2MockupState();
}

class _FretboardScreenV2MockupState extends ConsumerState<FretboardScreenV2Mockup> {
  String _scale = 'C maj';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fretboardProvider);
    final notifier = ref.read(fretboardProvider.notifier);
    final selectedCount = state.selectedNotes.length;
    final detected = selectedCount == 0
        ? null
        : selectedCount == 1
            ? 'Selected: ${state.selectedNotes.first}'
            : 'Selected: ${state.selectedNotes.join(' · ')}';

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Fretboard',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Fretboard',
              chipLabel: _scale,
              onClose: () => Navigator.of(context).pop(),
              actions: [
                IconBtn(icon: Icons.bookmark_border_rounded, onTap: () {}),
                IconBtn(icon: Icons.tune_rounded, onTap: () {}),
              ],
            ),
            ModeSegment<FretboardInputMode>(
              current: state.inputMode,
              onSelect: notifier.setInputMode,
              options: const [
                (FretboardInputMode.free, Icons.touch_app_rounded, 'Free'),
                (FretboardInputMode.chord, Icons.library_music_rounded, 'Chord'),
              ],
            ),
            Expanded(
              child: GlassFrame(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: _VerticalFretboardCanvas(
                  tuningName: state.currentTuning,
                  capo: state.capo,
                  selectedCells: state.selectedCells,
                  onToggleCell: notifier.toggleCell,
                  resolveNoteName: (stringIndex, fret) =>
                      _noteNameFor(state.currentTuning, stringIndex, fret),
                ),
              ),
            ),
            DetectionRibbon(detectedLabel: detected),
            DockedToolbar(
              children: [
                DockField(
                  value: _tuningLabel(state.currentTuning),
                  flex: 3,
                  onTap: () async {
                    final byLabel = {
                      for (final t in TuningName.values) _tuningLabel(t): t,
                    };
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Tuning',
                      options: byLabel.keys.toList(),
                      current: _tuningLabel(state.currentTuning),
                    );
                    if (picked != null) notifier.setTuning(byLabel[picked]!);
                  },
                ),
                DockField(
                  value: state.capo == 0 ? 'Capo 0' : 'Capo ${state.capo}',
                  flex: 2,
                  onTap: () async {
                    final picked = await showPickerSheet<int>(
                      context: context,
                      title: 'Capo',
                      options: List.generate(13, (i) => i),
                      current: state.capo,
                    );
                    if (picked != null) notifier.setCapo(picked);
                  },
                ),
                DockField(
                  value: _scale,
                  flex: 3,
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
                DockPrimaryButton(
                  icon: Icons.library_music_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Open chord voicing picker'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: Duration(milliseconds: 900),
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

  String _tuningLabel(TuningName name) {
    final raw = tunings[name]?.displayName ?? name.name;
    return raw.startsWith('Std ') ? raw.substring(4) : raw;
  }

  String _noteNameFor(TuningName tuningName, int stringIndex, int fret) {
    final t = tunings[tuningName]!;
    final openMidi = t.strings[stringIndex].midiNote;
    return _midiToName(openMidi + fret);
  }
}

const _semitones = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
String _midiToName(int midi) {
  final pc = midi % 12;
  final oct = (midi ~/ 12) - 1;
  return '${_semitones[pc]}$oct';
}

// ── Vertical fretboard canvas ──────────────────────────────────────────────

class _VerticalFretboardCanvas extends StatelessWidget {
  final TuningName tuningName;
  final int capo;
  final List<FretCoordinate> selectedCells;
  final void Function(int stringIndex, int fret, String noteName) onToggleCell;
  final String Function(int stringIndex, int fret) resolveNoteName;
  const _VerticalFretboardCanvas({
    required this.tuningName,
    required this.capo,
    required this.selectedCells,
    required this.onToggleCell,
    required this.resolveNoteName,
  });

  @override
  Widget build(BuildContext context) {
    final tuning = tunings[tuningName]!;
    return LayoutBuilder(
      builder: (ctx, c) {
        final layout = _VFretLayout(width: c.maxWidth, height: c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final hit = layout.hitTest(d.localPosition);
            if (hit == null) return;
            HapticFeedback.selectionClick();
            final (col, fret) = hit;
            final stringIndex = 5 - col; // col 0 = low E = stringIndex 5.
            onToggleCell(stringIndex, fret, resolveNoteName(stringIndex, fret));
          },
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _VFretPainter(
              tuning: tuning,
              capo: capo,
              selectedCells: selectedCells,
              layout: layout,
            ),
          ),
        );
      },
    );
  }
}

/// Pure-geometry layout helper. Shared between painter + tap hit testing.
class _VFretLayout {
  final double width;
  final double height;
  static const topLabelH = 44.0;
  static const leftMarginW = 24.0;
  static const rightMarginW = 12.0;
  static const numFrets = 12;
  static const stringCount = 6;

  _VFretLayout({required this.width, required this.height});

  double get boardLeft => leftMarginW;
  double get boardTop => topLabelH;
  double get boardW => width - leftMarginW - rightMarginW;
  double get boardH => height - topLabelH - 12;
  double get colW => boardW / stringCount;
  double get rowH => boardH / numFrets;

  Rect get boardRect => Rect.fromLTWH(boardLeft, boardTop, boardW, boardH);

  /// Returns (col, fret) or null if outside the interactive area.
  /// fret 0 = open string (in the band above the nut).
  (int, int)? hitTest(Offset p) {
    if (p.dx < boardLeft || p.dx > boardLeft + boardW) return null;
    final col = ((p.dx - boardLeft) / colW).floor().clamp(0, stringCount - 1);
    // Open band: between top of canvas and the nut line.
    if (p.dy >= topLabelH - 22 && p.dy < topLabelH) {
      return (col, 0);
    }
    if (p.dy < topLabelH) return null;
    if (p.dy > topLabelH + boardH) return null;
    final fret = ((p.dy - topLabelH) / rowH).floor() + 1;
    if (fret < 1 || fret > numFrets) return null;
    return (col, fret);
  }
}

class _VFretPainter extends CustomPainter {
  final Tuning tuning;
  final int capo;
  final List<FretCoordinate> selectedCells;
  final _VFretLayout layout;
  _VFretPainter({
    required this.tuning,
    required this.capo,
    required this.selectedCells,
    required this.layout,
  });

  // Wood palette (reverted from midnight — notes pop better against warm wood).
  static const _boardDark = Color(0xFF1A0D00);
  static const _boardMid = Color(0xFF3D1F00);
  static const _stringGold = Color(0xFFC8A050);
  static const _nutColor = Color(0xFFE8E4D8);
  static const _fretWireColor = Color(0xFF9AA5AE);
  static const _natural = Color(0xFF38BDF8);
  static const _accidental = Color(0xFFC084FC);

  /// Column order: leftmost (col 0) = low E (stringIndex 5),
  /// rightmost (col 5) = high E (stringIndex 0). Vertical chord-diagram convention.
  static const _stringNames = ['E', 'A', 'D', 'G', 'B', 'E'];

  @override
  void paint(Canvas c, Size size) {
    final r = layout.boardRect;
    _paintStringLabels(c, Offset(layout.boardLeft, 0), Size(layout.boardW, _VFretLayout.topLabelH));
    _paintBoard(c, r);
    _paintFretWires(c, r);
    _paintPositionMarkers(c, r);
    _paintStrings(c, r);
    _paintFretNumbers(c, Offset(0, layout.boardTop), Size(_VFretLayout.leftMarginW, layout.boardH));
    if (capo > 0) _paintCapo(c, r);
    _paintMutedAndOpenMarkers(c, r);
    _paintSelectedNotes(c, r);
  }

  void _paintBoard(Canvas c, Rect r) {
    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_boardMid, _boardDark],
      ).createShader(r);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), p);
  }

  void _paintStringLabels(Canvas c, Offset o, Size s) {
    // String letters anchor at the top of the band (~y=12 from top).
    final colW = s.width / _VFretLayout.stringCount;
    for (var i = 0; i < _VFretLayout.stringCount; i++) {
      final x = o.dx + i * colW + colW / 2;
      _drawText(
        c,
        _stringNames[i],
        Offset(x, o.dy + 12),
        color: MuzicianTheme.textSecondary,
        size: 13,
        weight: FontWeight.w700,
        center: true,
      );
    }
  }

  void _paintFretWires(Canvas c, Rect r) {
    final rowH = r.height / _VFretLayout.numFrets;

    // Nut (top edge): thicker bright wire.
    final nut = Paint()
      ..color = _nutColor
      ..strokeWidth = 4;
    c.drawLine(Offset(r.left, r.top), Offset(r.right, r.top), nut);

    // Fret wires below the nut.
    final wire = Paint()
      ..color = _fretWireColor
      ..strokeWidth = 1.5;
    for (var f = 1; f <= _VFretLayout.numFrets; f++) {
      final y = r.top + f * rowH;
      c.drawLine(Offset(r.left, y), Offset(r.right, y), wire);
    }
  }

  void _paintPositionMarkers(Canvas c, Rect r) {
    final rowH = r.height / _VFretLayout.numFrets;
    final colW = r.width / _VFretLayout.stringCount;
    final p = Paint()..color = Colors.white.withValues(alpha: 0.10);
    const single = [3, 5, 7, 9];
    for (final f in single) {
      final cx = r.left + r.width / 2;
      final cy = r.top + (f - 0.5) * rowH;
      c.drawCircle(Offset(cx, cy), 5, p);
    }
    // Octave at fret 12 — two dots on inner strings.
    final cy12 = r.top + (12 - 0.5) * rowH;
    c.drawCircle(Offset(r.left + colW * 2, cy12), 5, p);
    c.drawCircle(Offset(r.left + colW * 4, cy12), 5, p);
  }

  void _paintStrings(Canvas c, Rect r) {
    final colW = r.width / _VFretLayout.stringCount;
    // Left → right = low E → high E (thickest → thinnest).
    const widths = [2.6, 2.1, 1.7, 1.3, 1.0, 0.8];
    for (var i = 0; i < _VFretLayout.stringCount; i++) {
      final x = r.left + i * colW + colW / 2;
      final paint = Paint()
        ..color = _stringGold
        ..strokeWidth = widths[i];
      c.drawLine(Offset(x, r.top), Offset(x, r.bottom), paint);
    }
  }

  void _paintFretNumbers(Canvas c, Offset o, Size s) {
    final rowH = s.height / _VFretLayout.numFrets;
    const labeled = [3, 5, 7, 9, 12];
    for (final f in labeled) {
      final y = o.dy + (f - 0.5) * rowH;
      _drawText(
        c,
        '$f',
        Offset(o.dx + s.width / 2, y),
        color: MuzicianTheme.textMuted,
        size: 10,
        weight: FontWeight.w600,
        center: true,
      );
    }
  }

  void _paintCapo(Canvas c, Rect r) {
    final rowH = r.height / _VFretLayout.numFrets;
    final y = r.top + (capo - 0.5) * rowH;
    final capoRect = Rect.fromLTWH(r.left - 2, y - 4, r.width + 4, 8);
    c.drawRRect(
      RRect.fromRectAndRadius(capoRect, const Radius.circular(4)),
      Paint()..color = MuzicianTheme.orange.withValues(alpha: 0.85),
    );
  }

  /// Mark muted strings (x) above any string column that has no selected cell,
  /// and OPEN string indicators above any string with a selected fret == 0.
  /// Lives in the top label band between the string letter and the nut.
  void _paintMutedAndOpenMarkers(Canvas c, Rect r) {
    final colW = r.width / _VFretLayout.stringCount;
    // For mockup ergonomics: don't auto-mute every empty string — show muted
    // ONLY when a fretted note exists somewhere AND this string has nothing.
    final hasAnySelection = selectedCells.isNotEmpty;
    for (var col = 0; col < _VFretLayout.stringCount; col++) {
      final stringIndex = 5 - col;
      final cx = r.left + col * colW + colW / 2;
      final cellOnString = selectedCells.where((s) => s.stringIndex == stringIndex);
      final hasOpen = cellOnString.any((s) => s.fret == 0);
      final hasFretted = cellOnString.any((s) => s.fret > 0);
      // Markers sit at y ~ nut - 12.
      final markerY = r.top - 12;
      if (hasOpen) {
        c.drawCircle(
          Offset(cx, markerY),
          7,
          Paint()
            ..color = MuzicianTheme.sky
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else if (hasAnySelection && !hasFretted) {
        _drawText(c, '×', Offset(cx, markerY),
            color: MuzicianTheme.textMuted, size: 16, weight: FontWeight.w700, center: true);
      }
    }
  }

  /// Render every fretted cell from the real provider state.
  void _paintSelectedNotes(Canvas c, Rect r) {
    final rowH = r.height / _VFretLayout.numFrets;
    final colW = r.width / _VFretLayout.stringCount;
    for (final cell in selectedCells) {
      if (cell.fret == 0) continue; // Open string — rendered above the nut.
      if (cell.fret > _VFretLayout.numFrets) continue;
      final col = 5 - cell.stringIndex;
      final cx = r.left + col * colW + colW / 2;
      final cy = r.top + (cell.fret - 0.5) * rowH;
      final isAcc = cell.noteName.contains('#') || cell.noteName.contains('b');
      final color = isAcc ? _accidental : _natural;
      c.drawCircle(
        Offset(cx, cy),
        12,
        Paint()..color = color.withValues(alpha: 0.95),
      );
      c.drawCircle(
        Offset(cx, cy),
        12,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      // Note label (strip any octave digits).
      final label = cell.noteName.replaceAll(RegExp(r'\d'), '');
      _drawText(
        c,
        label,
        Offset(cx, cy),
        color: MuzicianTheme.scaffoldBg,
        size: 10,
        weight: FontWeight.w700,
        center: true,
      );
    }
  }

  void _drawText(
    Canvas c,
    String text,
    Offset o, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w400,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = center
        ? Offset(o.dx - tp.width / 2, o.dy - tp.height / 2)
        : o;
    tp.paint(c, offset);
  }

  @override
  bool shouldRepaint(covariant _VFretPainter old) =>
      old.tuning.name != tuning.name ||
      old.capo != capo ||
      old.selectedCells != selectedCells;
}
