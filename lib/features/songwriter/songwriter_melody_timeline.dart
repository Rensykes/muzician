import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/songwriter.dart';
import '../../schema/rules/songwriter_rules.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../theme/studio_theme.dart';

/// Bar-aligned Melody placements; repeated occurrences retain their source.
class SongwriterMelodyTimeline extends ConsumerStatefulWidget {
  const SongwriterMelodyTimeline({
    super.key,
    required this.section,
    required this.lane,
    required this.instanceIndex,
    required this.patternNames,
    required this.onEdit,
    required this.onCreate,
  });

  final SongSection section;
  final SongLane lane;
  final int instanceIndex;
  final Map<String, String> patternNames;
  final ValueChanged<SongBlock> onEdit;
  final ValueChanged<int> onCreate;

  @override
  ConsumerState<SongwriterMelodyTimeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<SongwriterMelodyTimeline>
    with SingleTickerProviderStateMixin {
  final _rowKeys = <int, GlobalKey>{};
  SongBlock? _dragBlock;
  int? _dragPointer;
  int? _previewSpan;
  double _edgeOffset = 0;
  late final Ticker _scrollTicker;
  ScrollableState? _scrollable;
  Offset? _pointerPosition;
  Duration? _lastScrollTick;

  @override
  void initState() {
    super.initState();
    _scrollTicker = createTicker(_autoScroll);
  }

  int _barsInRow(int start) => (widget.section.lengthBars - start).clamp(1, 4);

  void _start(SongBlock block, PointerDownEvent event, int rowStart) {
    if (_dragPointer != null) return;
    final box =
        _rowKeys[rowStart]!.currentContext!.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(event.position);
    final edge =
        (block.endBar - rowStart) * box.size.width / _barsInRow(rowStart);
    _edgeOffset = edge - local.dx;
    _scrollable = Scrollable.maybeOf(context);
    setState(() {
      _dragPointer = event.pointer;
      _dragBlock = block;
      _previewSpan = block.spanBars;
    });
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _dragPointer) return;
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
    for (final entry in _rowKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final p = box.globalToLocal(pointer);
      final d = p.dy < 0
          ? -p.dy
          : (p.dy > box.size.height ? p.dy - box.size.height : 0.0);
      if (d < distance) {
        distance = d;
        nearestRow = entry.key;
      }
    }
    if (nearestRow == null) return;
    final box =
        _rowKeys[nearestRow]!.currentContext!.findRenderObject()! as RenderBox;
    final x = box.globalToLocal(pointer).dx + _edgeOffset;
    final desired =
        (nearestRow +
                (x / (box.size.width / _barsInRow(nearestRow))).round() -
                block.startBar)
            .clamp(1, widget.section.lengthBars - block.startBar);
    // Walk from the original extent toward the pointer: do not jump over an
    // invalid extent or a repeat conflict to reach a later valid one.
    var span = block.spanBars;
    final step = desired >= span ? 1 : -1;
    while (span != desired) {
      final next = span + step;
      if (!isValidMelodyPlacement(
        section: widget.section,
        lane: widget.lane,
        candidate: block.copyWith(spanBars: next),
      )) {
        break;
      }
      span = next;
    }
    setState(() => _previewSpan = span);
  }

  void _end(PointerUpEvent event) {
    if (event.pointer != _dragPointer) return;
    _stopScrolling();
    _pointerPosition = null;
    _scrollable = null;
    final block = _dragBlock;
    final span = _previewSpan;
    setState(() {
      _dragBlock = null;
      _dragPointer = null;
      _previewSpan = null;
    });
    if (block == null || span == null || span == block.spanBars) return;
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

  @override
  void dispose() {
    _scrollTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  height: 48,
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
        final automatic = occurrence.repeatIndex > 0;
        final finalEdge = !automatic && end == occurrence.endBar;
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
                border: Border.all(
                  color: highlighted ? palette.orange : palette.sky,
                  width: highlighted ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Semantics(
                      label: automatic
                          ? 'Automatic repeat of ${widget.patternNames[block.patternId] ?? 'Missing pattern'}, bars ${occurrence.startBar + 1} through ${occurrence.endBar}'
                          : null,
                      child: InkWell(
                        key: Key(
                          'sheetMelodyTile_${block.patternId ?? block.id}_${widget.instanceIndex}_$segmentStart',
                        ),
                        onTap: () => widget.onEdit(block),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            key: Key(
                              'writerBlockName_${block.id}_${widget.instanceIndex}_$segmentStart',
                            ),
                            '${widget.patternNames[block.patternId] ?? 'Missing pattern'}${automatic
                                ? ' · repeat'
                                : segmentStart > occurrence.startBar
                                ? ' · continued'
                                : ''}',
                            maxLines: 2,
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
                        onPointerDown: (event) => _start(block, event, start),
                        onPointerMove: _move,
                        onPointerUp: _end,
                        onPointerCancel: (event) {
                          if (event.pointer != _dragPointer) return;
                          _stopScrolling();
                          _pointerPosition = null;
                          _scrollable = null;
                          setState(() {
                            _dragPointer = null;
                            _dragBlock = null;
                            _previewSpan = null;
                          });
                        },
                        child: Semantics(
                          label:
                              'Resize melody, ${block.spanBars} bars. Use Adjust placement for precise changes.',
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
                  height: 48,
                  child: Row(children: cellsForRow(start)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
