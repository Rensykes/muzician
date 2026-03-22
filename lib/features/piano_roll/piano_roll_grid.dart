/// PianoRollGrid – CustomPainter-based grid with synchronized scrolling,
/// tap-to-toggle, drag-to-move, and edge-to-resize.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../theme/muzician_theme.dart';

// ── Layout constants ────────────────────────────────────────────────────────

const double _pitchLabelWidth = 44;
const double _rulerHeight = 28;
const double _cellWidth = 28;
const double _rowHeight = 18;

// ── Helpers ─────────────────────────────────────────────────────────────────

bool _isBlackKey(int midi) {
  const black = {1, 3, 6, 8, 10};
  return black.contains(midi % 12);
}

Color _noteColor(PianoRollNote note, String? selectedNoteId, int? selectedColumnTick) {
  if (note.id == selectedNoteId) return MuzicianTheme.sky;
  if (selectedColumnTick != null &&
      note.startTick <= selectedColumnTick &&
      selectedColumnTick < note.startTick + note.durationTicks) {
    return MuzicianTheme.emerald;
  }
  return MuzicianTheme.teal;
}

// ── Grid Painter ────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final PianoRollState state;
  final int totalTicks;
  final TimeSignature timeSig;
  final double cellW;
  final double rowH;

  _GridPainter({
    required this.state,
    required this.totalTicks,
    required this.timeSig,
    required this.cellW,
    required this.rowH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rangeSize = state.pitchRangeEnd - state.pitchRangeStart + 1;
    if (rangeSize <= 0 || totalTicks <= 0) return;

    // Background rows
    for (int i = 0; i < rangeSize; i++) {
      final midi = state.pitchRangeEnd - i;
      final y = i * rowH;
      final isBlack = _isBlackKey(midi);
      canvas.drawRect(
        Rect.fromLTWH(0, y, totalTicks * cellW, rowH),
        Paint()
          ..color = isBlack
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.015),
      );
    }

    // Horizontal grid lines
    final hLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= rangeSize; i++) {
      final y = i * rowH;
      canvas.drawLine(Offset(0, y), Offset(totalTicks * cellW, y), hLinePaint);
    }

    // Vertical grid lines
    final beatTicks = timeSig.beatUnit == 8 ? 2 : 4;
    final measureTicks = rules.ticksPerMeasure(timeSig);
    for (int tick = 0; tick <= totalTicks; tick++) {
      final x = tick * cellW;
      final isMeasure = tick % measureTicks == 0;
      final isBeat = tick % beatTicks == 0;
      final paint = Paint()
        ..color = isMeasure
            ? Colors.white.withValues(alpha: 0.18)
            : isBeat
                ? Colors.white.withValues(alpha: 0.09)
                : Colors.white.withValues(alpha: 0.035)
        ..strokeWidth = isMeasure ? 1.0 : 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, rangeSize * rowH), paint);
    }

    // Selected column highlight
    if (state.selectedColumnTick != null) {
      final x = state.selectedColumnTick! * cellW;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, cellW, rangeSize * rowH),
        Paint()..color = MuzicianTheme.sky.withValues(alpha: 0.08),
      );
    }

    // Notes
    for (final note in state.notes) {
      final midi = note.midiNote;
      if (midi < state.pitchRangeStart || midi > state.pitchRangeEnd) continue;
      final rowIdx = state.pitchRangeEnd - midi;
      final x = note.startTick * cellW;
      final y = rowIdx * rowH;
      final w = note.durationTicks * cellW;

      final color = _noteColor(note, state.selectedNoteId, state.selectedColumnTick);
      final rrect =
          RRect.fromRectAndRadius(Rect.fromLTWH(x + 1, y + 1, w - 2, rowH - 2), const Radius.circular(4));
      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.35));
      canvas.drawRRect(
          rrect,
          Paint()
            ..color = color.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);

      // Note label
      final tp = TextPainter(
        text: TextSpan(
          text: note.pitchClass,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - 4);
      if (tp.width < w - 4) {
        tp.paint(canvas, Offset(x + 3, y + (rowH - tp.height) / 2));
      }

      // Resize handle (right-edge, 16 px zone)
      if (w > 8) {
        canvas.drawRect(
          Rect.fromLTWH(x + w - 8, y + 3, 5, rowH - 6),
          Paint()..color = color.withValues(alpha: 0.6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => true;
}

// ── Ruler Painter ───────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final TimeSignature timeSig;
  final int totalTicks;
  final int? selectedColumnTick;
  final double cellW;

  _RulerPainter({
    required this.timeSig,
    required this.totalTicks,
    required this.cellW,
    this.selectedColumnTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measureTicks = rules.ticksPerMeasure(timeSig);
    final beatTicks = timeSig.beatUnit == 8 ? 2 : 4;

    for (int tick = 0; tick < totalTicks; tick++) {
      final x = tick * cellW;
      final isMeasure = tick % measureTicks == 0;
      final isBeat = tick % beatTicks == 0;

      if (isMeasure) {
        final measure = tick ~/ measureTicks + 1;
        final tp = TextPainter(
          text: TextSpan(
            text: '$measure',
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, (_rulerHeight - tp.height) / 2));
      } else if (isBeat) {
        canvas.drawCircle(
          Offset(x + cellW / 2, _rulerHeight / 2),
          1.5,
          Paint()..color = MuzicianTheme.textMuted,
        );
      }

      // Tick line
      final lineH = isMeasure ? _rulerHeight * 0.6 : (isBeat ? _rulerHeight * 0.35 : 0);
      if (lineH > 0) {
        canvas.drawLine(
          Offset(x, _rulerHeight - lineH),
          Offset(x, _rulerHeight),
          Paint()
            ..color = isMeasure
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.12)
            ..strokeWidth = 0.5,
        );
      }
    }

    // Selected column marker
    if (selectedColumnTick != null) {
      final x = selectedColumnTick! * cellW + cellW / 2;
      canvas.drawCircle(
        Offset(x, _rulerHeight - 4),
        3,
        Paint()..color = MuzicianTheme.sky,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => true;
}

// ── Pitch Sidebar Painter ───────────────────────────────────────────────────

class _PitchSidebarPainter extends CustomPainter {
  final int rangeStart;
  final int rangeEnd;
  final double rowH;

  _PitchSidebarPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.rowH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rangeSize = rangeEnd - rangeStart + 1;
    for (int i = 0; i < rangeSize; i++) {
      final midi = rangeEnd - i;
      final y = i * rowH;
      final isBlack = _isBlackKey(midi);

      if (isBlack) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, _pitchLabelWidth, rowH),
          Paint()..color = Colors.white.withValues(alpha: 0.03),
        );
      }

      final label = rules.midiToNoteWithOctave(midi);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          _pitchLabelWidth - tp.width - 4,
          y + (rowH - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchSidebarPainter old) =>
      rangeStart != old.rangeStart || rangeEnd != old.rangeEnd || rowH != old.rowH;
}

// ── Main Widget ─────────────────────────────────────────────────────────────

enum _DragMode { none, moveNote, resizeNote }

class PianoRollGrid extends ConsumerStatefulWidget {
  const PianoRollGrid({super.key});

  @override
  ConsumerState<PianoRollGrid> createState() => _PianoRollGridState();
}

class _PianoRollGridState extends ConsumerState<PianoRollGrid> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();
  final _sidebarVScroll = ScrollController();
  final _rulerHScroll = ScrollController();

  _DragMode _dragMode = _DragMode.none;
  String? _dragNoteId;
  int _dragStartMidi = 0;
  int _noteOriginalStartTick = 0;
  int _noteOriginalMidi = 0;
  int _grabOffsetTicks = 0;
  Offset _totalPointerDelta = Offset.zero;
  bool _movedBeyondSlop = false;
  bool _longPressConsumed = false;
  Timer? _longPressTimer;

  // Zoom state — mutable cell width and row height driven by pinch.
  double _cellW = _cellWidth;
  double _rowH = _rowHeight;
  // Pinch tracking (two-pointer raw events).
  bool _pinching = false;
  final Map<int, Offset> _pointers = {};
  double _pinchInitHDist = 1.0;
  double _pinchInitVDist = 1.0;
  double _pinchInitCellW = _cellWidth;
  double _pinchInitRowH = _rowHeight;

  // Mouse cursor (desktop)
  SystemMouseCursor _cursor = SystemMouseCursors.basic;

  @override
  void initState() {
    super.initState();
    // Synchronize scroll positions
    _vScroll.addListener(_syncVertical);
    _hScroll.addListener(_syncHorizontal);
  }

  void _syncVertical() {
    if (_sidebarVScroll.hasClients &&
        _sidebarVScroll.offset != _vScroll.offset) {
      _sidebarVScroll.jumpTo(_vScroll.offset);
    }
  }

  void _syncHorizontal() {
    if (_rulerHScroll.hasClients && _rulerHScroll.offset != _hScroll.offset) {
      _rulerHScroll.jumpTo(_hScroll.offset);
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _vScroll.removeListener(_syncVertical);
    _hScroll.removeListener(_syncHorizontal);
    _hScroll.dispose();
    _vScroll.dispose();
    _sidebarVScroll.dispose();
    _rulerHScroll.dispose();
    super.dispose();
  }

  // ── Hit Testing ─────────────────────────────────────────────────────────

  PianoRollNote? _hitTestNote(Offset pos, PianoRollState state) {
    for (final note in state.notes.reversed) {
      if (note.midiNote < state.pitchRangeStart ||
          note.midiNote > state.pitchRangeEnd) {
        continue;
      }
      final rowIdx = state.pitchRangeEnd - note.midiNote;
      final x = note.startTick * _cellW;
      final y = rowIdx * _rowH;
      final w = note.durationTicks * _cellW;
      final rect = Rect.fromLTWH(x, y, w, _rowH);
      if (rect.contains(pos)) return note;
    }
    return null;
  }

  bool _isResizeHit(Offset pos, PianoRollNote note, PianoRollState state) {
    final x = note.startTick * _cellW;
    final w = note.durationTicks * _cellW;
    return pos.dx > x + w - 16;
  }

  ({int tick, int midi}) _posToTickMidi(Offset pos, PianoRollState state) {
    final tick = (pos.dx / _cellW).floor();
    final rowIdx = (pos.dy / _rowH).floor();
    final midi = state.pitchRangeEnd - rowIdx;
    return (tick: tick, midi: midi);
  }

  // ── Beat-grid snapping ────────────────────────────────────────────────

  int _beatTicks(TimeSignature ts) => ts.beatUnit == 8 ? 2 : 4;

  int _snapToBeat(int tick, int beatTicks) =>
      ((tick / beatTicks).round() * beatTicks).clamp(0, 1 << 20);

  // ── Gesture Handlers ──────────────────────────────────────────────────

  void _onRulerTap(TapUpDetails details, PianoRollState state) {
    final tick = ((details.localPosition.dx + _rulerHScroll.offset) / _cellWidth)
        .floor();
    final maxTick = rules.totalTicks(
        state.config.timeSignature, state.config.totalMeasures);
    if (tick >= 0 && tick < maxTick) {
      ref.read(pianoRollProvider.notifier).selectColumn(tick);
      HapticFeedback.selectionClick();
    }
  }

  // ── Raw pointer handlers (bypasses gesture arena — reliable on iOS) ──────

  void _onPointerDown(PointerDownEvent event, PianoRollState state) {
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length >= 2) {
      // Second finger down — switch to pinch-zoom mode.
      _pinching = true;
      _longPressTimer?.cancel();
      _dragMode = _DragMode.none;
      _dragNoteId = null;
      _movedBeyondSlop = false;
      final positions = _pointers.values.toList();
      _pinchInitHDist = max(1.0, (positions[0].dx - positions[1].dx).abs());
      _pinchInitVDist = max(1.0, (positions[0].dy - positions[1].dy).abs());
      _pinchInitCellW = _cellW;
      _pinchInitRowH = _rowH;
      return;
    }

    // Single-touch — existing logic.
    _pinching = false;
    final pos = _localToGrid(event.localPosition);
    final hit = _hitTestNote(pos, state);
    _totalPointerDelta = Offset.zero;
    _movedBeyondSlop = false;
    _longPressConsumed = false;

    if (hit != null) {
      final coord = _posToTickMidi(pos, state);
      _dragNoteId = hit.id;
      _dragStartMidi = coord.midi;
      _noteOriginalStartTick = hit.startTick;
      _noteOriginalMidi = hit.midiNote;
      _grabOffsetTicks = coord.tick - hit.startTick;
      _dragMode = _isResizeHit(pos, hit, state)
          ? _DragMode.resizeNote
          : _DragMode.moveNote;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 500), () {
        if (!_movedBeyondSlop && _dragNoteId != null) {
          ref.read(pianoRollProvider.notifier).removeNote(_dragNoteId!);
          HapticFeedback.mediumImpact();
          _dragNoteId = null;
          _dragMode = _DragMode.none;
          _longPressConsumed = true;
        }
      });
    } else {
      _dragMode = _DragMode.none;
      _dragNoteId = null;
    }
  }

  void _onPointerMove(PointerMoveEvent event, PianoRollState state) {
    _pointers[event.pointer] = event.localPosition;

    if (_pinching && _pointers.length >= 2) {
      // Pinch-zoom: scale cellW horizontally, rowH vertically.
      final positions = _pointers.values.toList();
      final hDist = max(1.0, (positions[0].dx - positions[1].dx).abs());
      final vDist = max(1.0, (positions[0].dy - positions[1].dy).abs());
      setState(() {
        _cellW = (_pinchInitCellW * (hDist / _pinchInitHDist)).clamp(10.0, 80.0);
        _rowH  = (_pinchInitRowH  * (vDist / _pinchInitVDist)).clamp(10.0, 40.0);
      });
      return;
    }

    _totalPointerDelta += event.delta;
    if (!_movedBeyondSlop && _totalPointerDelta.distance > 8.0) {
      _movedBeyondSlop = true;
      _longPressTimer?.cancel();
      if (_dragNoteId != null) {
        ref.read(pianoRollProvider.notifier).selectNote(_dragNoteId!);
      }
    }
    if (!_movedBeyondSlop) return;

    if (_dragMode == _DragMode.none) {
      _manualScroll(event.delta);
      return;
    }
    if (_dragNoteId == null) return;
    final notifier = ref.read(pianoRollProvider.notifier);
    final pos = _localToGrid(event.localPosition);
    final coord = _posToTickMidi(pos, state);

    if (_dragMode == _DragMode.moveNote) {
      final bt = _beatTicks(state.config.timeSignature);
      final rawStart = (pos.dx / _cellW).floor() - _grabOffsetTicks;
      final snappedStart = _snapToBeat(rawStart, bt);
      final midiDelta = coord.midi - _dragStartMidi;
      notifier.moveNote(_dragNoteId!, snappedStart, _noteOriginalMidi + midiDelta);
    } else if (_dragMode == _DragMode.resizeNote) {
      final cursorTick = (pos.dx / _cellW).floor();
      final newDuration = max(1, cursorTick - _noteOriginalStartTick + 1);
      notifier.resizeNote(_dragNoteId!, newDuration);
    }
  }

  void _onPointerUp(PointerUpEvent event, PianoRollState state) {
    final wasPinching = _pinching;
    _pointers.remove(event.pointer);
    _longPressTimer?.cancel();

    if (wasPinching) {
      if (_pointers.isEmpty) _pinching = false;
      // Don't fire tap after a pinch gesture.
      _dragMode = _DragMode.none;
      _dragNoteId = null;
      _movedBeyondSlop = false;
      _totalPointerDelta = Offset.zero;
      return;
    }
    if (!_movedBeyondSlop && !_longPressConsumed) {
      final pos = _localToGrid(event.localPosition);
      final hit = _hitTestNote(pos, state);
      final notifier = ref.read(pianoRollProvider.notifier);
      if (hit != null) {
        notifier.selectNote(hit.id == state.selectedNoteId ? null : hit.id);
        notifier.selectColumn(hit.startTick);
        HapticFeedback.selectionClick();
      } else {
        final coord = _posToTickMidi(pos, state);
        final maxTick = rules.totalTicks(
            state.config.timeSignature, state.config.totalMeasures);
        if (coord.tick >= 0 &&
            coord.tick < maxTick &&
            coord.midi >= state.pitchRangeStart &&
            coord.midi <= state.pitchRangeEnd) {
          notifier.toggleCellNote(coord.midi, coord.tick, 1);
          notifier.selectColumn(coord.tick);
          HapticFeedback.lightImpact();
        }
      }
    } else if (_dragMode != _DragMode.none) {
      HapticFeedback.lightImpact();
    }
    _dragMode = _DragMode.none;
    _dragNoteId = null;
    _movedBeyondSlop = false;
    _totalPointerDelta = Offset.zero;
  }

  void _manualScroll(Offset delta) {
    if (_hScroll.hasClients) {
      final newH = (_hScroll.offset - delta.dx)
          .clamp(0.0, _hScroll.position.maxScrollExtent);
      _hScroll.jumpTo(newH);
    }
    if (_vScroll.hasClients) {
      final newV = (_vScroll.offset - delta.dy)
          .clamp(0.0, _vScroll.position.maxScrollExtent);
      _vScroll.jumpTo(newV);
    }
  }

  void _onHover(PointerHoverEvent event, PianoRollState state) {
    final pos = _localToGrid(event.localPosition);
    final hit = _hitTestNote(pos, state);
    final next = hit == null
        ? SystemMouseCursors.basic
        : _isResizeHit(pos, hit, state)
            ? SystemMouseCursors.resizeRight
            : SystemMouseCursors.move;
    if (next != _cursor) setState(() => _cursor = next);
  }

  Offset _localToGrid(Offset local) {
    // GestureDetector is placed after the sidebar and below the ruler,
    // so localPosition is already relative to the grid area.
    return Offset(
      local.dx + _hScroll.offset,
      local.dy + _vScroll.offset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);
    final rangeSize = state.pitchRangeEnd - state.pitchRangeStart + 1;
    final totalTicks =
        rules.totalTicks(state.config.timeSignature, state.config.totalMeasures);
    final gridW = totalTicks * _cellW;
    final gridH = rangeSize * _rowH;

    return Container(
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        border: Border.all(color: MuzicianTheme.glassBorder, width: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // ── Top row: corner + ruler ──
          SizedBox(
            height: _rulerHeight,
            child: Row(
              children: [
                // Corner
                Container(
                  width: _pitchLabelWidth,
                  color: MuzicianTheme.surface,
                ),
                // Ruler (synced horizontally) — tap to select column
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onRulerTap(d, state),
                    child: SingleChildScrollView(
                      controller: _rulerHScroll,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: CustomPaint(
                        size: Size(gridW, _rulerHeight),
                        painter: _RulerPainter(
                          timeSig: state.config.timeSignature,
                          totalTicks: totalTicks,                        cellW: _cellW,                          selectedColumnTick: state.selectedColumnTick,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Main area: sidebar + grid ──
          Expanded(
            child: Row(
              children: [
                // Pitch sidebar (synced vertically)
                SizedBox(
                  width: _pitchLabelWidth,
                  child: SingleChildScrollView(
                    controller: _sidebarVScroll,
                    physics: const NeverScrollableScrollPhysics(),
                    child: CustomPaint(
                      size: Size(_pitchLabelWidth, gridH),
                      painter: _PitchSidebarPainter(
                        rangeStart: state.pitchRangeStart,
                        rangeEnd: state.pitchRangeEnd,
                        rowH: _rowH,
                      ),
                    ),
                  ),
                ),

                // Grid — raw Listener bypasses gesture arena for reliable touch
                Expanded(
                  child: MouseRegion(
                    cursor: _cursor,
                    onHover: (e) => _onHover(e, state),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _onPointerDown(e, state),
                      onPointerMove: (e) => _onPointerMove(e, state),
                      onPointerUp: (e) => _onPointerUp(e, state),
                      child: SingleChildScrollView(
                        controller: _vScroll,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(gridW, gridH),
                              painter: _GridPainter(
                                state: state,
                                totalTicks: totalTicks,
                                timeSig: state.config.timeSignature,
                                cellW: _cellW,
                                rowH: _rowH,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
