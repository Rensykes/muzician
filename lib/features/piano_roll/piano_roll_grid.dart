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
import '../../models/piano_roll_playback.dart';
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_store.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_player.dart';

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

Color _noteColor(
  PianoRollNote note,
  Set<String> selectedNoteIds,
  int? selectedColumnTick,
) {
  if (selectedNoteIds.contains(note.id)) {
    return selectedNoteIds.length > 1
        ? MuzicianTheme.violet
        : MuzicianTheme.sky;
  }
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
  final int? playbackTick;
  final double? scissorsCursorX;

  _GridPainter({
    required this.state,
    required this.totalTicks,
    required this.timeSig,
    required this.cellW,
    required this.rowH,
    this.playbackTick,
    this.scissorsCursorX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rangeSize = state.pitchRangeEnd - state.pitchRangeStart + 1;
    if (rangeSize <= 0 || totalTicks <= 0) return;

    // Background rows
    final highlightSet = state.highlightedNotes.toSet();
    for (int i = 0; i < rangeSize; i++) {
      final midi = state.pitchRangeEnd - i;
      final y = i * rowH;
      final isBlack = _isBlackKey(midi);
      final pc = rules.midiToPitchClass(midi);
      final isHighlighted = highlightSet.contains(pc);
      canvas.drawRect(
        Rect.fromLTWH(0, y, totalTicks * cellW, rowH),
        Paint()
          ..color = isHighlighted
              ? MuzicianTheme.emerald.withValues(alpha: 0.09)
              : isBlack
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

    // Selected column highlight stays visible only when playback is idle.
    if (playbackTick == null && state.selectedColumnTick != null) {
      final x = state.selectedColumnTick! * cellW;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, cellW, rangeSize * rowH),
        Paint()..color = MuzicianTheme.sky.withValues(alpha: 0.08),
      );
    }

    // Playback column highlight
    if (playbackTick != null) {
      final x = playbackTick! * cellW;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, cellW, rangeSize * rowH),
        Paint()..color = MuzicianTheme.orange.withValues(alpha: 0.12),
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

      final isSelected = state.selectedNoteIds.contains(note.id);
      final isMulti = isSelected && state.selectedNoteIds.length > 1;
      final color = _noteColor(
        note,
        state.selectedNoteIds,
        state.selectedColumnTick,
      );
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y + 1, w - 2, rowH - 2),
        const Radius.circular(4),
      );

      // Multi-selection outer glow
      if (isMulti) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 1, y - 1, w + 2, rowH + 2),
            const Radius.circular(6),
          ),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }

      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: isSelected ? 0.5 : 0.35),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: isSelected ? 0.9 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isMulti ? 1.5 : 1,
      );

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

    // Playback playhead
    if (playbackTick != null) {
      final x = playbackTick! * cellW + cellW / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, rangeSize * rowH),
        Paint()
          ..color = MuzicianTheme.orange
          ..strokeWidth = 2,
      );
    }

    // Scissors cut-line cursor
    if (scissorsCursorX != null) {
      canvas.drawLine(
        Offset(scissorsCursorX!, 0),
        Offset(scissorsCursorX!, rangeSize * rowH),
        Paint()
          ..color = MuzicianTheme.orange.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.state != state ||
      old.totalTicks != totalTicks ||
      old.timeSig != timeSig ||
      old.cellW != cellW ||
      old.rowH != rowH ||
      old.playbackTick != playbackTick ||
      old.scissorsCursorX != scissorsCursorX;
}

// ── Ruler Painter ───────────────────────────────────────────────────────────

class _RulerPainter extends CustomPainter {
  final TimeSignature timeSig;
  final int totalTicks;
  final int? selectedColumnTick;
  final int? playbackTick;
  final double cellW;

  _RulerPainter({
    required this.timeSig,
    required this.totalTicks,
    required this.cellW,
    this.selectedColumnTick,
    this.playbackTick,
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
      final lineH = isMeasure
          ? _rulerHeight * 0.6
          : (isBeat ? _rulerHeight * 0.35 : 0);
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
    if (playbackTick == null && selectedColumnTick != null) {
      final x = selectedColumnTick! * cellW + cellW / 2;
      canvas.drawCircle(
        Offset(x, _rulerHeight - 4),
        3,
        Paint()..color = MuzicianTheme.sky,
      );
    }

    if (playbackTick != null) {
      final x = playbackTick! * cellW + cellW / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, _rulerHeight),
        Paint()
          ..color = MuzicianTheme.orange
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(x, _rulerHeight - 4),
        3,
        Paint()..color = MuzicianTheme.orange,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.timeSig != timeSig ||
      old.totalTicks != totalTicks ||
      old.cellW != cellW ||
      old.selectedColumnTick != selectedColumnTick ||
      old.playbackTick != playbackTick;
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
        Offset(_pitchLabelWidth - tp.width - 4, y + (rowH - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PitchSidebarPainter old) =>
      rangeStart != old.rangeStart ||
      rangeEnd != old.rangeEnd ||
      rowH != old.rowH;
}

// ── Main Widget ─────────────────────────────────────────────────────────────

enum _DragMode { none, moveNote, resizeNote, paintBrush, deleteBrush }

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
  double? _scissorsCursorX;

  // Double-tap detection
  DateTime? _lastTapTime;
  String? _lastTapNoteId;
  Set<String> _preTapSelection = const {};

  // Empty-cell double-tap detection (snap-length insertion)
  int? _pendingEmptyTick;
  int? _pendingEmptyMidi;
  Timer? _emptyTapTimer;

  // Ruler drag state
  bool _rulerDragging = false;

  // Keyboard focus node
  final FocusNode _focusNode = FocusNode();

  // Multi-note drag: original positions snapshot keyed by note id
  Map<String, ({int startTick, int midiNote})> _multiDragOriginals = {};
  // Multi-note resize: original durations snapshot keyed by note id.
  Map<String, int> _multiResizeOriginalDurations = {};

  // Paint brush — cells already painted during the active drag, encoded as
  // `midi * 10000 + tick`. Prevents re-toggling a cell when the finger
  // dwells. Null when not painting.
  Set<int>? _paintBrushedCells;
  // Delete brush — note ids removed during the active drag. Null when not
  // deleting.
  Set<String>? _deleteBrushedNoteIds;

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
    _emptyTapTimer?.cancel();
    _focusNode.dispose();
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

  // ── Paint / Delete brush helpers ─────────────────────────────────────────

  /// Paints (= inserts) a note at the snap-aligned cell under [pos] if no
  /// note already occupies that exact (midi, snappedTick). Records the cell
  /// in [_paintBrushedCells] so the same cell is not re-painted while the
  /// finger dwells. No-op outside the timeline / pitch window.
  void _paintAt(Offset pos, PianoRollState state) {
    final brushed = _paintBrushedCells;
    if (brushed == null) return;
    final coord = _posToTickMidi(pos, state);
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (coord.tick < 0 || coord.tick >= maxTick) return;
    if (coord.midi < state.pitchRangeStart ||
        coord.midi > state.pitchRangeEnd) {
      return;
    }
    final snapped = _snapToBeat(coord.tick, state.snapTicks);
    final key = coord.midi * 10000 + snapped;
    if (brushed.contains(key)) return;
    brushed.add(key);
    // Skip the cell if a note is already anchored there — paint never
    // removes; that's what the Delete tool is for.
    final exists = state.notes.any(
      (n) => n.midiNote == coord.midi && n.startTick == snapped,
    );
    if (exists) return;
    ref
        .read(pianoRollProvider.notifier)
        .addNote(coord.midi, snapped, state.snapTicks);
    NotePlayer.instance.previewNote(
      coord.midi,
      volume: ref.read(settingsProvider).noteVolume,
    );
  }

  /// Removes the note under [pos] (if any) unless it was already removed
  /// during this drag. Tracks removed ids in [_deleteBrushedNoteIds].
  void _deleteAt(Offset pos, PianoRollState state) {
    final brushed = _deleteBrushedNoteIds;
    if (brushed == null) return;
    final hit = _hitTestNote(pos, state);
    if (hit == null || brushed.contains(hit.id)) return;
    brushed.add(hit.id);
    ref.read(pianoRollProvider.notifier).removeNote(hit.id);
  }

  // ── Beat-grid snapping ────────────────────────────────────────────────

  int _snapToBeat(int tick, int beatTicks) =>
      ((tick / beatTicks).round() * beatTicks).clamp(0, 1 << 20);

  // ── Gesture Handlers ──────────────────────────────────────────────────

  void _onRulerTap(TapUpDetails details, PianoRollState state) {
    final tick =
        ((details.localPosition.dx + _rulerHScroll.offset) / _cellWidth)
            .floor();
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (tick >= 0 && tick < maxTick) {
      ref.read(pianoRollProvider.notifier).selectColumn(tick);
      HapticFeedback.selectionClick();
    }
  }

  void _onRulerDragStart(DragStartDetails details) {
    _rulerDragging = true;
  }

  void _onRulerDragUpdate(DragUpdateDetails details, PianoRollState state) {
    if (!_rulerDragging) return;
    final absX = details.localPosition.dx;
    final tick = ((absX + _rulerHScroll.offset) / _cellW).floor();
    final maxTick = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    if (tick >= 0 && tick < maxTick) {
      ref.read(pianoRollProvider.notifier).selectColumn(tick);
    }
  }

  void _onRulerDragEnd(DragEndDetails details) {
    _rulerDragging = false;
    HapticFeedback.selectionClick();
  }

  // ── Keyboard shortcuts ──────────────────────────────────────────────

  void _togglePlayback() {
    final playbackState = ref.read(pianoRollPlaybackProvider);
    if (playbackState.status == PianoRollPlaybackStatus.playing) {
      ref.read(pianoRollPlaybackProvider.notifier).stopPlayback();
    } else {
      ref.read(pianoRollPlaybackProvider.notifier).startPlayback();
    }
  }

  void _deleteSelectedNotes() {
    final state = ref.read(pianoRollProvider);
    if (state.selectedNoteIds.isEmpty) return;
    ref.read(pianoRollProvider.notifier).deleteSelectedNotes();
    HapticFeedback.mediumImpact();
  }

  // ── Wheel zoom (desktop / web) ────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event, PianoRollState state) {
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final isCtrl =
        keys.contains(LogicalKeyboardKey.control) ||
        keys.contains(LogicalKeyboardKey.meta);
    final isAlt = keys.contains(LogicalKeyboardKey.alt);
    final delta = event.scrollDelta.dy;

    if (isCtrl && mounted) {
      setState(() {
        _cellW = (_cellW + delta * 0.5).clamp(10.0, 80.0);
      });
    }
    if (isAlt && mounted) {
      setState(() {
        _rowH = (_rowH + delta * 0.5).clamp(10.0, 40.0);
      });
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
      _multiDragOriginals = {};
      _multiResizeOriginalDurations = {};
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

    // ── Paint / Delete brush tools ────────────────────────────────────────
    // These act immediately on pointer-down and continue painting/deleting
    // as the finger drags. No long-press, no multi-select, no scroll-on-drag.
    if (state.activeTool == PianoRollTool.paint) {
      _paintBrushedCells = <int>{};
      _deleteBrushedNoteIds = null;
      _dragMode = _DragMode.paintBrush;
      _dragNoteId = null;
      _paintAt(pos, state);
      HapticFeedback.selectionClick();
      return;
    }
    if (state.activeTool == PianoRollTool.delete) {
      _deleteBrushedNoteIds = <String>{};
      _paintBrushedCells = null;
      _dragMode = _DragMode.deleteBrush;
      _dragNoteId = null;
      if (hit != null) {
        _deleteAt(pos, state);
        HapticFeedback.selectionClick();
      }
      return;
    }

    if (hit != null) {
      _dragNoteId = hit.id;
      if (state.activeTool == PianoRollTool.scissors) {
        // Scissors mode: arm long-press delete only, no move/resize drag.
        _dragMode = _DragMode.none;
      } else {
        final coord = _posToTickMidi(pos, state);
        _dragStartMidi = coord.midi;
        _noteOriginalStartTick = hit.startTick;
        _noteOriginalMidi = hit.midiNote;
        _grabOffsetTicks = coord.tick - hit.startTick;
        _dragMode = _isResizeHit(pos, hit, state)
            ? _DragMode.resizeNote
            : _DragMode.moveNote;
        if (state.selectedNoteIds.contains(hit.id) &&
            state.selectedNoteIds.length > 1) {
          if (_dragMode == _DragMode.moveNote) {
            _multiDragOriginals = {
              for (final n in state.notes)
                if (state.selectedNoteIds.contains(n.id))
                  n.id: (startTick: n.startTick, midiNote: n.midiNote),
            };
            _multiResizeOriginalDurations = {};
          } else if (_dragMode == _DragMode.resizeNote) {
            _multiResizeOriginalDurations = {
              for (final n in state.notes)
                if (state.selectedNoteIds.contains(n.id)) n.id: n.durationTicks,
            };
            _multiDragOriginals = {};
          }
        } else {
          _multiDragOriginals = {};
          _multiResizeOriginalDurations = {};
        }
      }
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
      _multiDragOriginals = {};
      _multiResizeOriginalDurations = {};
    }
  }

  void _onPointerMove(PointerMoveEvent event, PianoRollState state) {
    _pointers[event.pointer] = event.localPosition;

    if (_pinching && _pointers.length >= 2) {
      // Pinch-zoom: scale cellW horizontally, rowH vertically.
      final positions = _pointers.values.toList();
      final hDist = max(1.0, (positions[0].dx - positions[1].dx).abs());
      final vDist = max(1.0, (positions[0].dy - positions[1].dy).abs());
      if (!mounted) return;
      setState(() {
        _cellW = (_pinchInitCellW * (hDist / _pinchInitHDist)).clamp(
          10.0,
          80.0,
        );
        _rowH = (_pinchInitRowH * (vDist / _pinchInitVDist)).clamp(10.0, 40.0);
      });
      return;
    }

    _totalPointerDelta += event.delta;

    // Paint / Delete brushes respond on every move regardless of slop —
    // they're "continuous" tools, not move-or-tap.
    if (_dragMode == _DragMode.paintBrush) {
      _paintAt(_localToGrid(event.localPosition), state);
      return;
    }
    if (_dragMode == _DragMode.deleteBrush) {
      _deleteAt(_localToGrid(event.localPosition), state);
      return;
    }

    if (!_movedBeyondSlop && _totalPointerDelta.distance > 8.0) {
      _movedBeyondSlop = true;
      _longPressTimer?.cancel();
      if (_dragNoteId != null &&
          state.activeTool != PianoRollTool.scissors &&
          _multiDragOriginals.isEmpty &&
          _multiResizeOriginalDurations.isEmpty) {
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
      final rawStart = (pos.dx / _cellW).floor() - _grabOffsetTicks;
      final snappedStart = _snapToBeat(rawStart, state.snapTicks);
      final midiDelta = coord.midi - _dragStartMidi;
      if (_multiDragOriginals.isNotEmpty) {
        final tickDelta = snappedStart - _noteOriginalStartTick;
        notifier.moveNotesBatch([
          for (final e in _multiDragOriginals.entries)
            (
              id: e.key,
              startTick: e.value.startTick + tickDelta,
              midiNote: e.value.midiNote + midiDelta,
            ),
        ]);
      } else {
        notifier.moveNote(
          _dragNoteId!,
          snappedStart,
          _noteOriginalMidi + midiDelta,
        );
      }
    } else if (_dragMode == _DragMode.resizeNote) {
      final cursorTick = (pos.dx / _cellW).floor();
      final newDuration = max(1, cursorTick - _noteOriginalStartTick + 1);
      if (_multiResizeOriginalDurations.length > 1 &&
          _multiResizeOriginalDurations.containsKey(_dragNoteId)) {
        final anchorOriginal = _multiResizeOriginalDurations[_dragNoteId!]!;
        final durationDelta = newDuration - anchorOriginal;
        notifier.resizeNotesBatch([
          for (final entry in _multiResizeOriginalDurations.entries)
            (id: entry.key, durationTicks: max(1, entry.value + durationDelta)),
        ]);
      } else {
        notifier.resizeNote(_dragNoteId!, newDuration);
      }
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
      _multiDragOriginals = {};
      _multiResizeOriginalDurations = {};
      _movedBeyondSlop = false;
      _totalPointerDelta = Offset.zero;
      return;
    }
    // Paint/Delete brushes already acted on down/move — finalise and skip
    // the tap-handling branch below.
    if (_dragMode == _DragMode.paintBrush ||
        _dragMode == _DragMode.deleteBrush) {
      _paintBrushedCells = null;
      _deleteBrushedNoteIds = null;
      _dragMode = _DragMode.none;
      _dragNoteId = null;
      _multiDragOriginals = {};
      _multiResizeOriginalDurations = {};
      _movedBeyondSlop = false;
      _totalPointerDelta = Offset.zero;
      return;
    }

    if (!_movedBeyondSlop && !_longPressConsumed) {
      final pos = _localToGrid(event.localPosition);
      final hit = _hitTestNote(pos, state);
      final notifier = ref.read(pianoRollProvider.notifier);
      if (hit != null) {
        if (state.activeTool == PianoRollTool.scissors) {
          final coord = _posToTickMidi(pos, state);
          if (state.selectedNoteIds.length > 1 &&
              state.selectedNoteIds.contains(hit.id)) {
            notifier.splitSelectedNotesAtTick(coord.tick);
          } else {
            notifier.splitNote(hit.id, coord.tick);
          }
          HapticFeedback.lightImpact();
        } else {
          NotePlayer.instance.previewNote(
            hit.midiNote,
            volume: ref.read(settingsProvider).noteVolume,
          );
          final now = DateTime.now();
          final isDoubleTap =
              _lastTapNoteId == hit.id &&
              _lastTapTime != null &&
              now.difference(_lastTapTime!).inMilliseconds < 300;
          if (isDoubleTap) {
            // Restore the selection that existed before the first tap,
            // then toggle this note in/out of it.
            final toggled = _preTapSelection.contains(hit.id)
                ? _preTapSelection.difference({hit.id})
                : {..._preTapSelection, hit.id};
            notifier.setSelection(toggled.isEmpty ? {hit.id} : toggled);
            notifier.selectColumn(hit.startTick);
            HapticFeedback.mediumImpact();
            _lastTapTime = null;
            _lastTapNoteId = null;
          } else {
            _preTapSelection = state.selectedNoteIds;
            final isAlreadySolo =
                state.selectedNoteIds.length == 1 &&
                state.selectedNoteIds.contains(hit.id);
            notifier.selectNote(isAlreadySolo ? null : hit.id);
            notifier.selectColumn(hit.startTick);
            HapticFeedback.selectionClick();
            _lastTapTime = now;
            _lastTapNoteId = hit.id;
          }
        }
      } else {
        if (state.activeTool != PianoRollTool.scissors) {
          final coord = _posToTickMidi(pos, state);
          final maxTick = rules.totalTicks(
            state.config.timeSignature,
            state.config.totalMeasures,
          );
          if (coord.tick >= 0 &&
              coord.tick < maxTick &&
              coord.midi >= state.pitchRangeStart &&
              coord.midi <= state.pitchRangeEnd) {
            NotePlayer.instance.previewNote(
              coord.midi,
              volume: ref.read(settingsProvider).noteVolume,
            );
            // Double-tap detection on empty cell for snap-length insertion.
            final isDoubleTap =
                _pendingEmptyTick == coord.tick &&
                _pendingEmptyMidi == coord.midi;
            if (isDoubleTap) {
              // Cancel the deferred 1-tick creation and create snap-tick.
              _emptyTapTimer?.cancel();
              _emptyTapTimer = null;
              _pendingEmptyTick = null;
              _pendingEmptyMidi = null;
              notifier.toggleCellNote(coord.midi, coord.tick, state.snapTicks);
              HapticFeedback.mediumImpact();
            } else {
              // Cancel any previous pending tap, then start deferred timer.
              _emptyTapTimer?.cancel();
              _pendingEmptyTick = coord.tick;
              _pendingEmptyMidi = coord.midi;
              _emptyTapTimer = Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                ref
                    .read(pianoRollProvider.notifier)
                    .toggleCellNote(coord.midi, coord.tick, 1);
                _pendingEmptyTick = null;
                _pendingEmptyMidi = null;
              });
              HapticFeedback.lightImpact();
            }
            notifier.selectColumn(coord.tick);
          }
        }
      }
    } else if (_dragMode != _DragMode.none) {
      HapticFeedback.lightImpact();
    }
    _dragMode = _DragMode.none;
    _dragNoteId = null;
    _multiDragOriginals = {};
    _multiResizeOriginalDurations = {};
    _movedBeyondSlop = false;
    _totalPointerDelta = Offset.zero;
  }

  void _manualScroll(Offset delta) {
    if (_hScroll.hasClients) {
      final newH = (_hScroll.offset - delta.dx).clamp(
        0.0,
        _hScroll.position.maxScrollExtent,
      );
      _hScroll.jumpTo(newH);
    }
    if (_vScroll.hasClients) {
      final newV = (_vScroll.offset - delta.dy).clamp(
        0.0,
        _vScroll.position.maxScrollExtent,
      );
      _vScroll.jumpTo(newV);
    }
  }

  void _onHover(PointerHoverEvent event, PianoRollState state) {
    final pos = _localToGrid(event.localPosition);
    final hit = _hitTestNote(pos, state);
    final tool = state.activeTool;
    final isScissors = tool == PianoRollTool.scissors;
    final SystemMouseCursor next;
    if (tool == PianoRollTool.paint) {
      next = SystemMouseCursors.precise;
    } else if (tool == PianoRollTool.delete) {
      next = hit != null
          ? SystemMouseCursors.precise
          : SystemMouseCursors.forbidden;
    } else if (hit == null) {
      next = SystemMouseCursors.basic;
    } else if (isScissors) {
      next = SystemMouseCursors.precise;
    } else {
      next = _isResizeHit(pos, hit, state)
          ? SystemMouseCursors.resizeRight
          : SystemMouseCursors.move;
    }
    final newScissorX = (isScissors && hit != null) ? pos.dx : null;
    if ((next != _cursor || newScissorX != _scissorsCursorX) && mounted) {
      setState(() {
        _cursor = next;
        _scissorsCursorX = newScissorX;
      });
    }
  }

  Offset _localToGrid(Offset local) {
    // GestureDetector is placed after the sidebar and below the ruler,
    // so localPosition is already relative to the grid area.
    return Offset(local.dx + _hScroll.offset, local.dy + _vScroll.offset);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);
    final playbackTick = ref.watch(
      pianoRollPlaybackProvider.select((playbackState) {
        return playbackState.status == PianoRollPlaybackStatus.playing
            ? playbackState.currentTick
            : null;
      }),
    );
    ref.listen(
      pianoRollPlaybackProvider.select((playbackState) {
        return playbackState.status == PianoRollPlaybackStatus.playing
            ? playbackState.currentTick
            : null;
      }),
      (_, tick) {
        if (tick == null || !_hScroll.hasClients) return;
        final targetX = tick * _cellW + (_cellW / 2);
        final viewport = _hScroll.position.viewportDimension;
        final leftBound = _hScroll.offset + viewport * 0.2;
        final rightBound = _hScroll.offset + viewport * 0.8;

        if (targetX < leftBound || targetX > rightBound) {
          final nextOffset = (targetX - viewport * 0.4).clamp(
            0.0,
            _hScroll.position.maxScrollExtent,
          );
          _hScroll.jumpTo(nextOffset);
        }
      },
    );
    ref.listen(pianoRollScrollToTickProvider, (_, tick) {
      if (tick == null || !_hScroll.hasClients) return;
      final targetX = tick * _cellW;
      if (targetX >
          _hScroll.offset + (_hScroll.position.viewportDimension / 2)) {
        _hScroll.animateTo(
          (targetX - _hScroll.position.viewportDimension / 4).clamp(
            0.0,
            _hScroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      ref.read(pianoRollScrollToTickProvider.notifier).state = null;
    });
    final rangeSize = state.pitchRangeEnd - state.pitchRangeStart + 1;
    final totalTicks = rules.totalTicks(
      state.config.timeSignature,
      state.config.totalMeasures,
    );
    final gridW = totalTicks * _cellW;
    final gridH = rangeSize * _rowH;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        LogicalKeySet(LogicalKeyboardKey.space): _togglePlayback,
        LogicalKeySet(LogicalKeyboardKey.delete): _deleteSelectedNotes,
        LogicalKeySet(LogicalKeyboardKey.backspace): _deleteSelectedNotes,
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: Container(
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
                    // Ruler (synced horizontally) — tap/drag to select column
                    Expanded(
                      child: GestureDetector(
                        key: const ValueKey('piano-roll-ruler-drag-area'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onRulerTap(d, state),
                        onHorizontalDragStart: _onRulerDragStart,
                        onHorizontalDragUpdate: (d) =>
                            _onRulerDragUpdate(d, state),
                        onHorizontalDragEnd: _onRulerDragEnd,
                        child: SingleChildScrollView(
                          controller: _rulerHScroll,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: CustomPaint(
                            key: const ValueKey('piano-roll-ruler-paint'),
                            size: Size(gridW, _rulerHeight),
                            painter: _RulerPainter(
                              timeSig: state.config.timeSignature,
                              totalTicks: totalTicks,
                              cellW: _cellW,
                              selectedColumnTick: state.selectedColumnTick,
                              playbackTick: playbackTick,
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

                    // Grid — raw Listener bypasses gesture arena
                    Expanded(
                      child: MouseRegion(
                        cursor: _cursor,
                        onHover: (e) => _onHover(e, state),
                        onExit: (_) {
                          if (_scissorsCursorX != null && mounted) {
                            setState(() => _scissorsCursorX = null);
                          }
                        },
                        child: Stack(
                          children: [
                            Listener(
                              key: const ValueKey('piano-roll-grid-listener'),
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: (e) => _onPointerDown(e, state),
                              onPointerMove: (e) => _onPointerMove(e, state),
                              onPointerUp: (e) => _onPointerUp(e, state),
                              onPointerSignal: (e) =>
                                  _onPointerSignal(e, state),
                              child: SingleChildScrollView(
                                controller: _vScroll,
                                physics: const NeverScrollableScrollPhysics(),
                                child: SingleChildScrollView(
                                  controller: _hScroll,
                                  scrollDirection: Axis.horizontal,
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      key: const ValueKey(
                                        'piano-roll-grid-paint',
                                      ),
                                      size: Size(gridW, gridH),
                                      painter: _GridPainter(
                                        state: state,
                                        totalTicks: totalTicks,
                                        timeSig: state.config.timeSignature,
                                        cellW: _cellW,
                                        rowH: _rowH,
                                        playbackTick: playbackTick,
                                        scissorsCursorX: _scissorsCursorX,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (state.selectedNoteIds.length > 1)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: MuzicianTheme.violet.withValues(
                                      alpha: 0.2,
                                    ),
                                    border: Border.all(
                                      color: MuzicianTheme.violet.withValues(
                                        alpha: 0.6,
                                      ),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${state.selectedNoteIds.length} selected',
                                        style: const TextStyle(
                                          color: MuzicianTheme.violet,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () {
                                          ref
                                              .read(pianoRollProvider.notifier)
                                              .clearSelection();
                                          HapticFeedback.selectionClick();
                                        },
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(64, 40),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        child: const Text(
                                          'Clear',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          _deleteSelectedNotes();
                                        },
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(64, 40),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        child: const Text(
                                          'Delete',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
