import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../models/song_project.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/studio_theme.dart';
import 'songwriter_melody_preview.dart';

/// Bar-aligned Melody placements; repeated occurrences retain their source.
class SongwriterMelodyTimeline extends ConsumerStatefulWidget {
  const SongwriterMelodyTimeline({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    required this.patternNames,
    required this.patterns,
    required this.measureTicks,
    required this.onEdit,
    required this.onCreate,
    required this.canEdit,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final Map<String, String> patternNames;
  final Map<String, NotePattern> patterns;
  final int measureTicks;
  final ValueChanged<SongBlock> onEdit;
  final ValueChanged<int> onCreate;
  final bool Function(SongBlock) canEdit;

  @override
  ConsumerState<SongwriterMelodyTimeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<SongwriterMelodyTimeline>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _rowKeys = <int, GlobalKey>{};
  SongBlock? _dragBlock;
  int? _dragPointer;
  int? _previewSpan;
  double _edgeOffset = 0;
  late final Ticker _scrollTicker;
  ScrollableState? _scrollable;
  Offset? _pointerPosition;
  Duration? _lastScrollTick;
  final _dragRowRects = <int, Rect>{};
  double _dragScrollOrigin = 0;

  @override
  bool get wantKeepAlive => _dragPointer != null;

  @override
  void initState() {
    super.initState();
    _scrollTicker = createTicker(_autoScroll);
  }

  int _barsInRow(int start) => (widget.section.lengthBars - start).clamp(1, 4);

  int? _melodyBarsFor(SongBlock block) {
    final pattern = widget.patterns[block.patternId];
    if (pattern == null) return null;
    return melodyPlacementBarLimit(pattern, widget.measureTicks);
  }

  void _start(SongBlock block, PointerDownEvent event, int rowStart) {
    if (!mounted || _dragPointer != null) return;
    final box =
        _rowKeys[rowStart]!.currentContext!.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(event.position);
    final edge =
        (block.endBar.clamp(0, widget.section.lengthBars) - rowStart) *
        box.size.width /
        _barsInRow(rowStart);
    _edgeOffset = edge - local.dx;
    _scrollable = Scrollable.maybeOf(context);
    _dragScrollOrigin = _scrollable?.position.pixels ?? 0;
    // Rows have fixed geometry during a drag. Capture it while the section is
    // laid out; kept-alive sliver children may no longer have a paint transform.
    _dragRowRects.clear();
    for (final entry in _rowKeys.entries) {
      final row = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (row == null || !row.attached || !row.hasSize) continue;
      _dragRowRects[entry.key] = row.localToGlobal(Offset.zero) & row.size;
    }
    setState(() {
      _dragPointer = event.pointer;
      _dragBlock = block;
      _previewSpan = block.spanBars;
    });
    updateKeepAlive();
  }

  void _move(PointerMoveEvent event) {
    if (!mounted || event.pointer != _dragPointer) return;
    _pointerPosition = event.position;
    _updatePreview(event.position);
    if (_scrollSpeed(event.position) != 0) {
      if (!_scrollTicker.isActive) {
        _lastScrollTick = null;
        _scrollTicker.start();
      }
    } else {
      _stopScrolling();
    }
  }

  double _scrollSpeed(Offset pointer) {
    final scrollable = _scrollable;
    final box = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || box == null || !box.attached) return 0;
    final local = box.globalToLocal(pointer);
    const edge = 48.0;
    if (local.dy < edge &&
        scrollable.position.pixels > scrollable.position.minScrollExtent) {
      return -480 * ((edge - local.dy) / edge).clamp(0.0, 1.0);
    }
    if (local.dy > box.size.height - edge &&
        scrollable.position.pixels < scrollable.position.maxScrollExtent) {
      return 480 * ((local.dy - box.size.height + edge) / edge).clamp(0.0, 1.0);
    }
    return 0;
  }

  void _autoScroll(Duration elapsed) {
    final pointer = _pointerPosition;
    final scrollable = _scrollable;
    if (pointer == null || scrollable == null || _dragPointer == null) {
      _stopScrolling();
      return;
    }
    final speed = _scrollSpeed(pointer);
    if (speed == 0) {
      _stopScrolling();
      return;
    }
    final last = _lastScrollTick;
    _lastScrollTick = elapsed;
    if (last == null) return;
    final seconds =
        (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    final position = scrollable.position;
    position.jumpTo(
      (position.pixels + speed * seconds.clamp(0.0, 0.05)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _updatePreview(pointer);
  }

  void _stopScrolling() {
    if (_scrollTicker.isActive) _scrollTicker.stop();
    _lastScrollTick = null;
  }

  void _updatePreview(Offset pointer) {
    final block = _dragBlock;
    if (block == null) return;
    int? nearestRow;
    double distance = double.infinity;
    final scrollDelta =
        (_scrollable?.position.pixels ?? _dragScrollOrigin) - _dragScrollOrigin;
    for (final entry in _dragRowRects.entries) {
      final rect = entry.value.shift(Offset(0, -scrollDelta));
      final d = pointer.dy < rect.top
          ? rect.top - pointer.dy
          : (pointer.dy > rect.bottom ? pointer.dy - rect.bottom : 0.0);
      if (d < distance) {
        distance = d;
        nearestRow = entry.key;
      }
    }
    if (nearestRow == null) return;
    final rect = _dragRowRects[nearestRow]!;
    final x = pointer.dx - rect.left + _edgeOffset;
    final desired =
        (nearestRow +
                (x / (rect.width / _barsInRow(nearestRow))).round() -
                block.startBar)
            .clamp(1, widget.section.lengthBars - block.startBar);
    // Walk from the original extent toward the pointer: do not jump over an
    // invalid extent or a repeat conflict to reach a later valid one.
    var span = block.spanBars;
    final melodyBars = _melodyBarsFor(block);
    if (block.endBar > widget.section.lengthBars) {
      if (isValidMelodyPlacement(
        section: widget.section,
        lane: widget.lane,
        candidate: block.copyWith(spanBars: desired),
        melodyBars: melodyBars,
      )) {
        setState(() => _previewSpan = desired);
      }
      return;
    }
    // Shrinking may jump straight to the pointer. This is required when a
    // legacy placement is longer than its melody: intermediate spans can be
    // over the limit even though a smaller valid span exists.
    if (desired < span &&
        isValidMelodyPlacement(
          section: widget.section,
          lane: widget.lane,
          candidate: block.copyWith(spanBars: desired),
          melodyBars: melodyBars,
        )) {
      setState(() => _previewSpan = desired);
      return;
    }
    final step = desired >= span ? 1 : -1;
    while (span != desired) {
      final next = span + step;
      if (!isValidMelodyPlacement(
        section: widget.section,
        lane: widget.lane,
        candidate: block.copyWith(spanBars: next),
        melodyBars: melodyBars,
      )) {
        break;
      }
      span = next;
    }
    setState(() => _previewSpan = span);
  }

  void _end(PointerUpEvent event) {
    if (!mounted || event.pointer != _dragPointer) return;
    _stopScrolling();
    _pointerPosition = null;
    _scrollable = null;
    _dragRowRects.clear();
    final block = _dragBlock;
    final span = _previewSpan;
    setState(() {
      _dragBlock = null;
      _dragPointer = null;
      _previewSpan = null;
    });
    if (block != null && span != null && span != block.spanBars) {
      // The store revalidates against the current project at commit time.
      ref
          .read(songwriterProvider.notifier)
          .setBlockPlacement(
            sectionId: widget.section.id,
            laneId: widget.lane.id,
            blockId: block.id,
            startBar: block.startBar,
            spanBars: span,
          );
    }
    if (mounted) updateKeepAlive();
  }

  @override
  void dispose() {
    _scrollTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = StudioPalette.of(context);
    final lane = _dragBlock == null
        ? widget.lane
        : widget.lane.copyWith(
            blocks: [
              for (final block in widget.lane.blocks)
                if (block.id == _dragBlock!.id)
                  block.copyWith(spanBars: _previewSpan)
                else
                  block,
            ],
          );
    final occurrences = melodyOccurrences(
      lane: lane,
      sectionLengthBars: widget.section.lengthBars,
    );
    final active = ref.watch(songwriterActivePositionProvider);
    final bars = widget.section.lengthBars.clamp(1, 64);
    final labelHeight = math.max(
      16.0,
      MediaQuery.textScalerOf(context).scale(14),
    );
    final rowHeight = math.max(48.0, labelHeight + 24);
    List<Widget> cellsForRow(int start) {
      final cells = <Widget>[];
      var bar = start;
      while (bar < (start + 4).clamp(0, bars)) {
        final occurrence = occurrences
            .where((o) => o.startBar <= bar && o.endBar > bar)
            .firstOrNull;
        if (occurrence == null) {
          final emptyBar = bar++;
          cells.add(
            Expanded(
              child: InkWell(
                key: Key(
                  'emptyMelodyBar_${widget.lane.id}_${widget.instanceIndex}_$emptyBar',
                ),
                onTap: () => widget.onCreate(emptyBar),
                child: Container(
                  height: rowHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.glassBorder),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.add,
                    color: palette.textMuted,
                    semanticLabel: 'Create melody at bar ${emptyBar + 1}',
                  ),
                ),
              ),
            ),
          );
          continue;
        }
        final segmentStart = bar;
        final end = occurrence.endBar.clamp(
          bar + 1,
          (start + 4).clamp(0, bars),
        );
        bar = end;
        final block = occurrence.source;
        final editable = widget.canEdit(block);
        final pattern = editable ? widget.patterns[block.patternId] : null;
        final name = widget.patternNames[block.patternId];
        final displayName = name == null
            ? 'Missing pattern'
            : editable
            ? name
            : 'Unresolved melody';
        final automatic = occurrence.repeatIndex > 0;
        final finalEdge = !automatic && end == occurrence.endBar;
        final melodyBars = pattern == null
            ? null
            : melodyPlacementBarLimit(pattern, widget.measureTicks);
        final silentTailStart = melodyBars == null
            ? null
            : occurrence.startBar + melodyBars;
        final cueBar = silentTailStart == null
            ? segmentStart
            : math.max(silentTailStart, segmentStart);
        final hasSilentTail = silentTailStart != null && cueBar < end;
        final silentTailBars = silentTailStart == null
            ? 0
            : math.max(
                0,
                occurrence.endBar -
                    math.max(silentTailStart, occurrence.startBar),
              );
        final tailSemantics = silentTailBars > 0
            ? ', silent tail ${silentTailBars == 1 ? 'bar' : 'bars'} '
                  '${cueBar + 1} through ${occurrence.endBar}'
            : '';
        final highlighted =
            active != null &&
            active.sectionId == widget.section.id &&
            active.instanceIndex == widget.instanceIndex &&
            active.localBar >= segmentStart &&
            active.localBar < end;
        cells.add(
          Expanded(
            flex: end - segmentStart,
            child: Container(
              key: Key(
                'melodySegment_${block.id}_${widget.instanceIndex}_${occurrence.repeatIndex}_$segmentStart',
              ),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: palette.sky.withValues(alpha: automatic ? .07 : .18),
                border: Border.all(color: palette.sky),
                borderRadius: BorderRadius.circular(6),
              ),
              foregroundDecoration: highlighted
                  ? BoxDecoration(
                      border: Border.all(color: palette.orange, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (pattern != null)
                    Positioned(
                      top: labelHeight,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: IgnorePointer(
                          child: SongwriterMelodyPreview(
                            pattern: pattern,
                            segmentStartTick:
                                (segmentStart - occurrence.startBar) *
                                widget.measureTicks,
                            segmentEndTick:
                                (end - occurrence.startBar) *
                                widget.measureTicks,
                          ),
                        ),
                      ),
                    ),
                  if (!editable)
                    Positioned(
                      left: 2,
                      top: 1,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: palette.orange,
                          ),
                        ),
                      ),
                    ),
                  if (hasSilentTail)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            key: Key(
                              'melodySilentTail_${block.id}_${widget.instanceIndex}_$cueBar',
                            ),
                            painter: _SilentTailPainter(
                              startFraction:
                                  ((cueBar - segmentStart) /
                                          (end - segmentStart))
                                      .clamp(0.0, 1.0),
                              palette: palette,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Semantics(
                          label:
                              '${automatic ? 'Automatic repeat of ' : ''}$displayName${name != null && !editable ? ' content' : ''}, bars ${occurrence.startBar + 1} through ${occurrence.endBar}$tailSemantics',
                          child: InkWell(
                            key: Key(
                              'sheetMelodyTile_${block.patternId ?? block.id}_${widget.instanceIndex}_$segmentStart',
                            ),
                            onTap: editable ? () => widget.onEdit(block) : null,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: editable ? 4 : 18,
                                right: 4,
                              ),
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: SizedBox(
                                  height: labelHeight,
                                  child: Text(
                                    key: Key(
                                      'writerBlockName_${block.id}_${widget.instanceIndex}_$segmentStart',
                                    ),
                                    '$displayName${automatic
                                        ? ' · repeat'
                                        : segmentStart > occurrence.startBar
                                        ? ' · continued'
                                        : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (finalEdge)
                        RawGestureDetector(
                          key: Key(
                            'melodyResize_${block.id}_${widget.instanceIndex}',
                          ),
                          gestures: {
                            EagerGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  EagerGestureRecognizer
                                >(EagerGestureRecognizer.new, (_) {}),
                          },
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) =>
                                _start(block, event, start),
                            onPointerMove: _move,
                            onPointerUp: _end,
                            onPointerCancel: (event) {
                              if (!mounted || event.pointer != _dragPointer) {
                                return;
                              }
                              _stopScrolling();
                              _pointerPosition = null;
                              _scrollable = null;
                              _dragRowRects.clear();
                              setState(() {
                                _dragPointer = null;
                                _dragBlock = null;
                                _previewSpan = null;
                              });
                              updateKeepAlive();
                            },
                            child: Semantics(
                              label:
                                  'Resize melody, ${block.spanBars} bars${melodyBars != null && block.spanBars > melodyBars ? ', with a silent tail after $melodyBars bars' : ''}. Use Adjust placement for precise changes.',
                              child: SizedBox(
                                width: 44,
                                height: 46,
                                child: Icon(
                                  Icons.drag_handle,
                                  size: 18,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return cells;
    }

    return Column(
      children: [
        for (var start = 0; start < bars; start += 4)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var col = 0; col < _barsInRow(start); col++)
                      Expanded(
                        child: Text(
                          'Bar ${start + col + 1}',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(
                  key: _rowKeys.putIfAbsent(start, GlobalKey.new),
                  height: rowHeight,
                  child: Row(children: cellsForRow(start)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Diagonal shading over the part of a placement after its melody ends.
class _SilentTailPainter extends CustomPainter {
  const _SilentTailPainter({
    required this.startFraction,
    required this.palette,
  });

  final double startFraction;
  final StudioPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || startFraction >= 1) return;
    final left = size.width * startFraction.clamp(0.0, 1.0);
    final area = Rect.fromLTRB(left, 0, size.width, size.height);
    if (area.isEmpty) return;
    canvas.save();
    canvas.clipRect(area);
    final line = Paint()
      ..color = palette.textMuted.withValues(alpha: .22)
      ..strokeWidth = 1;
    const gap = 8.0;
    for (var x = area.left - size.height; x < area.right; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SilentTailPainter oldDelegate) =>
      oldDelegate.startFraction != startFraction ||
      oldDelegate.palette != palette;
}
