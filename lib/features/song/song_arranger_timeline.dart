library;

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_playback.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/glass_snackbar.dart';
import 'song_audio_actions.dart';
import 'song_track_header.dart';

const double _kBaseTickWidth = 4.0;

/// Current tick width in dp — [_kBaseTickWidth] × the timeline zoom. Set by
/// the timeline root on every build so painters and hit-tests stay in sync.
double _kTickWidth = _kBaseTickWidth;
const double _kRulerHeight = 32;
const double _kLaneHeight = 64;

/// Pre-computed pattern content for in-clip thumbnails.
class NoteClipPreview {
  final List<NotePatternNote> notes;
  final int lengthTicks;
  final int minMidi;
  final int maxMidi;
  const NoteClipPreview({
    required this.notes,
    required this.lengthTicks,
    required this.minMidi,
    required this.maxMidi,
  });
}

class DrumClipPreview {
  final List<DrumLaneSequence> lanes;
  final int lengthTicks;
  const DrumClipPreview({required this.lanes, required this.lengthTicks});
}
const double _kGutterCompact = 140;
const double _kGutterTablet = 220;
const double _kTabletBreakpoint = 600;

class SongArrangerTimeline extends ConsumerStatefulWidget {
  final int measureTicks;
  final int? currentPlaybackTick;

  const SongArrangerTimeline({
    super.key,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  ConsumerState<SongArrangerTimeline> createState() =>
      _SongArrangerTimelineState();
}

class _SongArrangerTimelineState extends ConsumerState<SongArrangerTimeline> {
  late final ScrollController _hScroll;
  bool _userScrubbing = false;

  @override
  void initState() {
    super.initState();
    _hScroll = ScrollController();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  /// Keeps the playhead inside the visible window while playing.
  void _followPlayhead(int tick) {
    if (_userScrubbing || !_hScroll.hasClients) return;
    final position = _hScroll.position;
    final playheadDx = tick * _kTickWidth;
    final viewLeft = position.pixels;
    final viewRight = viewLeft + position.viewportDimension;
    const margin = 80.0;
    if (playheadDx > viewRight - margin || playheadDx < viewLeft) {
      final target = (playheadDx - position.viewportDimension * 0.3).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _hScroll.jumpTo(target);
    }
  }

  double _scaleBaseZoom = 1.0;

  @override
  Widget build(BuildContext context) {
    _kTickWidth = _kBaseTickWidth * ref.watch(songTimelineZoomProvider);
    ref.listen(songPlaybackProvider, (prev, next) {
      if (next.status == SongPlaybackStatus.playing &&
          next.currentTick != null) {
        _followPlayhead(next.currentTick!);
      }
      if (prev?.status == SongPlaybackStatus.idle &&
          next.status == SongPlaybackStatus.playing) {
        _userScrubbing = false; // re-arm follow on each new playback
      }
    });
    final project = ref.watch(songProjectProvider);
    final orderedTracks = [...project.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));

    final clipLengths = <String, int>{};
    final patternRefCount = <String, int>{};
    for (final clip in project.clips) {
      final len = song_rules.patternLengthForClip(project, clip);
      if (len != null) clipLengths[clip.id] = len;
      patternRefCount.update(clip.patternId, (v) => v + 1, ifAbsent: () => 1);
    }
    final sharedPatternIds = <String>{
      for (final entry in patternRefCount.entries)
        if (entry.value > 1) entry.key,
    };

    final notePatternById = {for (final p in project.notePatterns) p.id: p};
    final drumPatternById = {for (final p in project.drumPatterns) p.id: p};
    final notePreviewByClipId = <String, NoteClipPreview>{};
    final drumPreviewByClipId = <String, DrumClipPreview>{};
    final clipLabelById = <String, String>{};
    for (final clip in project.clips) {
      switch (clip.patternType) {
        case SongPatternType.note:
          final pattern = notePatternById[clip.patternId];
          if (pattern == null || pattern.notes.isEmpty) break;
          var minMidi = pattern.notes.first.midiNote;
          var maxMidi = minMidi;
          for (final n in pattern.notes) {
            if (n.midiNote < minMidi) minMidi = n.midiNote;
            if (n.midiNote > maxMidi) maxMidi = n.midiNote;
          }
          notePreviewByClipId[clip.id] = NoteClipPreview(
            notes: pattern.notes,
            lengthTicks: pattern.lengthTicks,
            minMidi: minMidi,
            maxMidi: maxMidi,
          );
          clipLabelById[clip.id] = pattern.name;
        case SongPatternType.drum:
          final pattern = drumPatternById[clip.patternId];
          if (pattern == null) break;
          if (pattern.lanes.any((l) => l.activeTicks.isNotEmpty)) {
            drumPreviewByClipId[clip.id] = DrumClipPreview(
              lanes: pattern.lanes,
              lengthTicks: pattern.lengthTicks,
            );
          }
          clipLabelById[clip.id] = pattern.name;
        case SongPatternType.audio:
          break;
      }
    }

    final audioPatternById = {for (final p in project.audioPatterns) p.id: p};
    final audioAssetById = {for (final a in project.audioAssets) a.id: a};
    final audioPeaksByClipId = <String, List<int>>{};
    final audioBrokenClipIds = <String>{};
    for (final clip in project.clips) {
      if (clip.patternType != SongPatternType.audio) continue;
      final pattern = audioPatternById[clip.patternId];
      if (pattern == null) {
        audioBrokenClipIds.add(clip.id);
        continue;
      }
      final asset = audioAssetById[pattern.assetId];
      if (asset == null) {
        audioBrokenClipIds.add(clip.id);
        continue;
      }
      audioPeaksByClipId[clip.id] = asset.peaks;
    }

    final totalTicks = widget.measureTicks * project.config.totalMeasures;
    final timelineWidth = totalTicks * _kTickWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutterWidth = constraints.maxWidth >= _kTabletBreakpoint
            ? _kGutterTablet
            : _kGutterCompact;
        return NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            // A user-initiated horizontal scroll pauses auto-follow until
            // the next playback starts.
            if (notification.metrics.axis == Axis.horizontal &&
                notification.direction != ScrollDirection.idle) {
              _userScrubbing = true;
            }
            return false;
          },
          child: GestureDetector(
            // Two-finger pinch zooms the timeline horizontally; single-finger
            // input falls through to the scroll views and clip gestures.
            onScaleStart: (details) {
              _scaleBaseZoom = ref.read(songTimelineZoomProvider);
            },
            onScaleUpdate: (details) {
              if (details.pointerCount < 2) return;
              ref.read(songTimelineZoomProvider.notifier).state =
                  (_scaleBaseZoom * details.horizontalScale).clamp(0.5, 3.0);
            },
            child: Column(
          children: [
            _MeasureRuler(
              totalMeasures: project.config.totalMeasures,
              measureTicks: widget.measureTicks,
              timelineWidth: timelineWidth,
              gutterWidth: gutterWidth,
              hScroll: _hScroll,
              currentPlaybackTick: widget.currentPlaybackTick,
              onSeekToDx: (dx) {
                final tick = (dx / _kTickWidth).round();
                HapticFeedback.selectionClick();
                ref.read(songPlaybackProvider.notifier).seek(tick);
              },
            ),
            Expanded(
              child: ListView.builder(
                itemCount: orderedTracks.length,
                itemBuilder: (context, index) {
                  final track = orderedTracks[index];
                  final trackClips = project.clips
                      .where((clip) => clip.trackId == track.id)
                      .toList();
                  return _TrackLane(
                    track: track,
                    clips: trackClips,
                    clipLengths: clipLengths,
                    sharedPatternIds: sharedPatternIds,
                    audioPeaksByClipId: audioPeaksByClipId,
                    audioBrokenClipIds: audioBrokenClipIds,
                    notePreviewByClipId: notePreviewByClipId,
                    drumPreviewByClipId: drumPreviewByClipId,
                    clipLabelById: clipLabelById,
                    measureTicks: widget.measureTicks,
                    totalMeasures: project.config.totalMeasures,
                    timelineWidth: timelineWidth,
                    gutterWidth: gutterWidth,
                    hScroll: _hScroll,
                    currentPlaybackTick: widget.currentPlaybackTick,
                  );
                },
              ),
            ),
          ],
            ),
          ),
        );
      },
    );
  }
}

class _MeasureRuler extends ConsumerStatefulWidget {
  final int totalMeasures;
  final int measureTicks;
  final double timelineWidth;
  final double gutterWidth;
  final ScrollController hScroll;
  final int? currentPlaybackTick;

  /// Called with the local x-offset (in the timeline's coordinate space) when
  /// the user taps the ruler to move the playhead.
  final ValueChanged<double> onSeekToDx;

  const _MeasureRuler({
    required this.totalMeasures,
    required this.measureTicks,
    required this.timelineWidth,
    required this.gutterWidth,
    required this.hScroll,
    required this.currentPlaybackTick,
    required this.onSeekToDx,
  });

  @override
  ConsumerState<_MeasureRuler> createState() => _MeasureRulerState();
}

class _MeasureRulerState extends ConsumerState<_MeasureRuler> {
  int? _dragStartTick;
  int? _dragEndTick;

  int _snappedTick(double dx) {
    final tick = (dx / _kTickWidth).round();
    final snapped = (tick / widget.measureTicks).round() * widget.measureTicks;
    return snapped.clamp(0, widget.measureTicks * widget.totalMeasures);
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _dragStartTick = _snappedTick(details.localPosition.dx);
      _dragEndTick = null;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dragStartTick == null) return;
    final tick = _snappedTick(details.localPosition.dx);
    if (tick == _dragEndTick) return;
    setState(() => _dragEndTick = tick);
  }

  void _onDragEnd(DragEndDetails details) {
    final a = _dragStartTick;
    final b = _dragEndTick;
    setState(() {
      _dragStartTick = null;
      _dragEndTick = null;
    });
    if (a == null || b == null || a == b) return;
    HapticFeedback.mediumImpact();
    ref
        .read(songPlaybackProvider.notifier)
        .setLoopRegion(a < b ? a : b, a < b ? b : a);
  }

  Future<void> _addMarkerAt(int tick) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text(
          'Add Marker',
          style: TextStyle(color: MuzicianTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Verse, Chorus, …',
            hintStyle: TextStyle(color: MuzicianTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (label == null) return;
    ref.read(songProjectProvider.notifier).addMarker(tick, label.trim());
  }

  Future<void> _editMarker(SongMarker marker) async {
    final controller = TextEditingController(text: marker.label);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MuzicianTheme.surface,
        title: const Text(
          'Edit Marker',
          style: TextStyle(color: MuzicianTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: MuzicianTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text(
              'Delete',
              style: TextStyle(color: MuzicianTheme.red),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final notifier = ref.read(songProjectProvider.notifier);
    if (action == 'delete') {
      notifier.removeMarker(marker.id);
    } else if (action == 'save') {
      notifier.updateMarker(marker.id, label: controller.text.trim());
    }
  }

  /// Marker whose flag sits within 12 dp of [dx], or null.
  SongMarker? _markerNear(double dx, List<SongMarker> markers) {
    for (final m in markers) {
      if ((m.tick * _kTickWidth - dx).abs() < 12) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(songPlaybackProvider);
    final markers = ref.watch(songProjectProvider.select((p) => p.markers));
    final pendingStart = _dragStartTick;
    final pendingEnd = _dragEndTick;
    final (loopStart, loopEnd) =
        pendingStart != null && pendingEnd != null
        ? (
            pendingStart < pendingEnd ? pendingStart : pendingEnd,
            pendingStart < pendingEnd ? pendingEnd : pendingStart,
          )
        : (playback.loopStartTick, playback.loopEndTickExclusive);

    return Container(
      height: _kRulerHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: widget.gutterWidth, child: const _GutterCorner()),
          _VerticalDivider(),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: widget.timelineWidth,
                height: _kRulerHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final hit = _markerNear(details.localPosition.dx, markers);
                    if (hit != null) {
                      _editMarker(hit);
                      return;
                    }
                    widget.onSeekToDx(details.localPosition.dx);
                  },
                  onDoubleTapDown: (details) {
                    final tick = _snappedTick(details.localPosition.dx);
                    _addMarkerAt(tick);
                  },
                  onLongPressStart: (d) => _onDragStart(
                    DragStartDetails(localPosition: d.localPosition),
                  ),
                  onLongPressMoveUpdate: (d) => _onDragUpdate(
                    DragUpdateDetails(
                      globalPosition: d.globalPosition,
                      localPosition: d.localPosition,
                    ),
                  ),
                  onLongPressEnd: (d) => _onDragEnd(DragEndDetails()),
                  child: CustomPaint(
                    painter: _RulerPainter(
                      totalMeasures: widget.totalMeasures,
                      measureTicks: widget.measureTicks,
                      currentPlaybackTick: widget.currentPlaybackTick,
                      loopStartTick: loopStart,
                      loopEndTickExclusive: loopEnd,
                      markers: markers,
                    ),
                    size: Size(widget.timelineWidth, _kRulerHeight),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GutterCorner extends StatelessWidget {
  const _GutterCorner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'TRACKS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: MuzicianTheme.textMuted.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: Colors.white.withValues(alpha: 0.08));
  }
}

class _RulerPainter extends CustomPainter {
  final int totalMeasures;
  final int measureTicks;
  final int? currentPlaybackTick;
  final int? loopStartTick;
  final int? loopEndTickExclusive;
  final List<SongMarker> markers;

  const _RulerPainter({
    required this.totalMeasures,
    required this.measureTicks,
    required this.currentPlaybackTick,
    this.loopStartTick,
    this.loopEndTickExclusive,
    this.markers = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measureWidth = measureTicks * _kTickWidth;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Loop region band under the measure numbers.
    if (loopStartTick != null && loopEndTickExclusive != null) {
      final left = loopStartTick! * _kTickWidth;
      final right = loopEndTickExclusive! * _kTickWidth;
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()..color = MuzicianTheme.teal.withValues(alpha: 0.18),
      );
      final edgePaint = Paint()
        ..color = MuzicianTheme.teal
        ..strokeWidth = 2;
      canvas.drawLine(Offset(left, 0), Offset(left, size.height), edgePaint);
      canvas.drawLine(Offset(right, 0), Offset(right, size.height), edgePaint);
    }

    for (var m = 0; m <= totalMeasures; m++) {
      final x = m * measureWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      if (m < totalMeasures) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${m + 1}',
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final textY = (size.height - tp.height) / 2;
        tp.paint(canvas, Offset(x + 6, textY));
      }
    }

    // Marker flags.
    for (final marker in markers) {
      final mx = marker.tick * _kTickWidth;
      final flagPaint = Paint()..color = MuzicianTheme.orange;
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, size.height),
        Paint()
          ..color = MuzicianTheme.orange.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
      final path = Path()
        ..moveTo(mx, 2)
        ..lineTo(mx + 8, 6)
        ..lineTo(mx, 10)
        ..close();
      canvas.drawPath(path, flagPaint);
      if (marker.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: marker.label,
            style: const TextStyle(
              color: MuzicianTheme.orange,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 80);
        tp.paint(canvas, Offset(mx + 10, 2));
      }
    }

    if (currentPlaybackTick != null) {
      final cx = currentPlaybackTick! * _kTickWidth;
      final cursorPaint = Paint()
        ..color = MuzicianTheme.sky
        ..strokeWidth = 2;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), cursorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      totalMeasures != oldDelegate.totalMeasures ||
      currentPlaybackTick != oldDelegate.currentPlaybackTick ||
      loopStartTick != oldDelegate.loopStartTick ||
      loopEndTickExclusive != oldDelegate.loopEndTickExclusive ||
      markers != oldDelegate.markers;
}

/// Width (in ticks) of the right-edge resize handle hit zone.
/// At _kTickWidth = 4 dp/tick, 4 ticks = 16 dp — matches finger-friendly grab.
const int _kResizeHandleTicks = 4;

class _TrackLane extends ConsumerStatefulWidget {
  final SongTrack track;
  final List<SongClipInstance> clips;
  final Map<String, int> clipLengths;
  final Set<String> sharedPatternIds;
  final Map<String, List<int>> audioPeaksByClipId;
  final Set<String> audioBrokenClipIds;
  final Map<String, NoteClipPreview> notePreviewByClipId;
  final Map<String, DrumClipPreview> drumPreviewByClipId;
  final Map<String, String> clipLabelById;
  final int measureTicks;
  final int totalMeasures;
  final double timelineWidth;
  final double gutterWidth;
  final ScrollController hScroll;
  final int? currentPlaybackTick;

  const _TrackLane({
    required this.track,
    required this.clips,
    required this.clipLengths,
    required this.sharedPatternIds,
    required this.audioPeaksByClipId,
    required this.audioBrokenClipIds,
    required this.notePreviewByClipId,
    required this.drumPreviewByClipId,
    required this.clipLabelById,
    required this.measureTicks,
    required this.totalMeasures,
    required this.timelineWidth,
    required this.gutterWidth,
    required this.hScroll,
    required this.currentPlaybackTick,
  });

  @override
  ConsumerState<_TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends ConsumerState<_TrackLane> {
  // Long-press drag-to-size state (new clip creation).
  int? _pendingStartTick;
  int? _pendingEndTick;

  // Pan state for moving / resizing the selected clip.
  ({String clipId, int startTick})? _pendingMove;
  ({String clipId, int lengthTicks})? _pendingResize;
  int? _grabOffsetTicks;

  /// True while the active pan gesture is panning the timeline horizontally
  /// (i.e. neither moving nor resizing the selected clip).
  bool _isScrolling = false;

  /// This lane's own horizontal controller.  A single shared controller cannot
  /// be attached to the ruler *and* every lane scroll view at once — reading
  /// `.offset`/`.position` then trips `_positions.length == 1`.  Instead each
  /// lane owns a controller and mirrors the master ([widget.hScroll], attached
  /// only to the ruler) via a listener; lane pan-scroll drives the master.
  final ScrollController _laneScroll = ScrollController();

  void _syncFromMaster() {
    if (!_laneScroll.hasClients || !widget.hScroll.hasClients) return;
    final target = widget.hScroll.offset;
    if ((_laneScroll.offset - target).abs() > 0.01) {
      _laneScroll.jumpTo(target);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.hScroll.addListener(_syncFromMaster);
  }

  @override
  void didUpdateWidget(covariant _TrackLane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hScroll != widget.hScroll) {
      oldWidget.hScroll.removeListener(_syncFromMaster);
      widget.hScroll.addListener(_syncFromMaster);
    }
  }

  @override
  void dispose() {
    widget.hScroll.removeListener(_syncFromMaster);
    _laneScroll.dispose();
    super.dispose();
  }

  int _tickAtDx(double dx) => (dx / _kTickWidth).round().clamp(
    0,
    widget.measureTicks * widget.totalMeasures,
  );

  /// Snap unit: a measure by default, a beat when beat-snap is on.
  int get _snapTicks {
    if (!ref.read(songSnapToBeatProvider)) return widget.measureTicks;
    final ts = ref.read(songProjectProvider).config.timeSignature;
    final beatTicks = widget.measureTicks ~/ ts.beatsPerMeasure;
    return beatTicks > 0 ? beatTicks : widget.measureTicks;
  }

  int _snapToMeasure(int tick) {
    final unit = _snapTicks;
    return (tick / unit).round() * unit;
  }

  /// First clip on this track that starts strictly after [tick] (excluding
  /// the optionally-passed clip id), or null.
  int? _nextClipStartAfter(int tick, {String? excludingClipId}) {
    int? best;
    for (final clip in widget.clips) {
      if (clip.id == excludingClipId) continue;
      if (clip.startTick > tick) {
        if (best == null || clip.startTick < best) best = clip.startTick;
      }
    }
    return best;
  }

  SongClipInstance? _clipAt(int tapTick) {
    for (final clip in widget.clips) {
      final end =
          clip.startTick + (widget.clipLengths[clip.id] ?? widget.measureTicks);
      if (tapTick >= clip.startTick && tapTick < end) return clip;
    }
    return null;
  }

  bool _tickInRightHandle(SongClipInstance clip, int tick) {
    final length = widget.clipLengths[clip.id] ?? widget.measureTicks;
    final endTick = clip.startTick + length;
    return tick >= endTick - _kResizeHandleTicks && tick <= endTick + 1;
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final tick = _tickAtDx(details.localPosition.dx);
    if (_clipAt(tick) != null) return;

    final unit = _snapTicks;
    final start = _snapToMeasure(tick).clamp(
      0,
      widget.measureTicks * widget.totalMeasures - unit,
    );
    final ceiling =
        _nextClipStartAfter(start) ??
        widget.measureTicks * widget.totalMeasures;
    final defaultEnd = (start + unit).clamp(start + 1, ceiling);

    HapticFeedback.lightImpact();
    setState(() {
      _pendingStartTick = start;
      _pendingEndTick = defaultEnd;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final start = _pendingStartTick;
    if (start == null) return;
    final ceiling =
        _nextClipStartAfter(start) ??
        widget.measureTicks * widget.totalMeasures;
    final tick = _tickAtDx(details.localPosition.dx);
    final snapped = _snapToMeasure(
      tick,
    ).clamp(start + _snapTicks, ceiling);
    if (snapped == _pendingEndTick) return;
    setState(() => _pendingEndTick = snapped);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final start = _pendingStartTick;
    final end = _pendingEndTick;
    setState(() {
      _pendingStartTick = null;
      _pendingEndTick = null;
    });
    if (start == null || end == null) return;
    HapticFeedback.mediumImpact();
    _showAddClipSheet(context, ref, start, end - start);
  }

  void _onLongPressCancel() {
    if (_pendingStartTick == null && _pendingEndTick == null) return;
    setState(() {
      _pendingStartTick = null;
      _pendingEndTick = null;
    });
  }

  void _onTapDown(TapDownDetails details) {
    final tapTick = _tickAtDx(details.localPosition.dx);
    final tappedClip = _clipAt(tapTick);
    final selectedId = ref.read(songSelectedClipIdProvider);
    if (tappedClip == null) {
      // Tap on empty lane: clear any current selection.
      if (selectedId != null) {
        ref.read(songSelectedClipIdProvider.notifier).state = null;
      }
      return;
    }
    // Tap a clip → select it (or toggle off if already selected).
    final next = tappedClip.id == selectedId ? null : tappedClip.id;
    ref.read(songSelectedClipIdProvider.notifier).state = next;
    HapticFeedback.selectionClick();
  }

  void _onPanStart(DragStartDetails details) {
    final selectedId = ref.read(songSelectedClipIdProvider);
    final clip = selectedId == null
        ? null
        : widget.clips.where((c) => c.id == selectedId).firstOrNull;
    if (clip != null) {
      final tick = _tickAtDx(details.localPosition.dx);
      if (_tickInRightHandle(clip, tick)) {
        setState(() {
          _pendingResize = (
            clipId: clip.id,
            lengthTicks: widget.clipLengths[clip.id] ?? widget.measureTicks,
          );
        });
        HapticFeedback.selectionClick();
        return;
      }
      final length = widget.clipLengths[clip.id] ?? widget.measureTicks;
      if (tick >= clip.startTick &&
          tick < clip.startTick + length - _kResizeHandleTicks) {
        setState(() {
          _pendingMove = (clipId: clip.id, startTick: clip.startTick);
          _grabOffsetTicks = tick - clip.startTick;
        });
        HapticFeedback.selectionClick();
        return;
      }
    }
    // Default: treat the pan as a horizontal timeline scroll.
    _isScrolling = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isScrolling) {
      if (!widget.hScroll.hasClients) return;
      final next = (widget.hScroll.offset - details.delta.dx).clamp(
        0.0,
        widget.hScroll.position.maxScrollExtent,
      );
      widget.hScroll.jumpTo(next);
      return;
    }
    final tick = _tickAtDx(details.localPosition.dx);
    if (_pendingResize != null) {
      final clip = widget.clips.firstWhere(
        (c) => c.id == _pendingResize!.clipId,
      );
      final ceiling =
          _nextClipStartAfter(clip.startTick, excludingClipId: clip.id) ??
          (widget.measureTicks * widget.totalMeasures);
      final maxLen = ceiling - clip.startTick;
      final candidate = _snapToMeasure(
        tick - clip.startTick,
      ).clamp(widget.measureTicks, maxLen);
      if (candidate == _pendingResize!.lengthTicks) return;
      setState(() {
        _pendingResize = (clipId: clip.id, lengthTicks: candidate);
      });
      return;
    }
    if (_pendingMove != null) {
      final clip = widget.clips.firstWhere((c) => c.id == _pendingMove!.clipId);
      final length = widget.clipLengths[clip.id] ?? widget.measureTicks;
      final grab = _grabOffsetTicks ?? 0;
      final rawStart = tick - grab;
      final maxStart = (widget.measureTicks * widget.totalMeasures) - length;
      final snapped = _snapToMeasure(rawStart).clamp(0, maxStart);
      if (snapped == _pendingMove!.startTick) return;
      setState(() {
        _pendingMove = (clipId: clip.id, startTick: snapped);
      });
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final notifier = ref.read(songProjectProvider.notifier);
    if (_pendingResize != null) {
      final pendingResize = _pendingResize!;
      final project = ref.read(songProjectProvider);
      final clip = project.clips.firstWhere(
        (c) => c.id == pendingResize.clipId,
      );
      if (clip.patternType == SongPatternType.note) {
        final pattern = project.notePatterns.firstWhere(
          (p) => p.id == clip.patternId,
        );
        if (pattern.lengthTicks != pendingResize.lengthTicks) {
          notifier.applyNotePattern(
            clip.patternId,
            pattern.copyWith(lengthTicks: pendingResize.lengthTicks),
          );
        }
      } else {
        final pattern = project.drumPatterns.firstWhere(
          (p) => p.id == clip.patternId,
        );
        if (pattern.lengthTicks != pendingResize.lengthTicks) {
          notifier.applyDrumPattern(
            clip.patternId,
            pattern.copyWith(lengthTicks: pendingResize.lengthTicks),
          );
        }
      }
      HapticFeedback.mediumImpact();
    } else if (_pendingMove != null) {
      final pendingMove = _pendingMove!;
      final clip = widget.clips.firstWhere((c) => c.id == pendingMove.clipId);
      if (clip.startTick != pendingMove.startTick) {
        notifier.moveClip(pendingMove.clipId, pendingMove.startTick);
      }
      HapticFeedback.mediumImpact();
    }
    setState(() {
      _pendingMove = null;
      _pendingResize = null;
      _grabOffsetTicks = null;
      _isScrolling = false;
    });
  }

  void _onPanCancel() {
    if (_pendingMove == null && _pendingResize == null && !_isScrolling) {
      return;
    }
    setState(() {
      _pendingMove = null;
      _pendingResize = null;
      _grabOffsetTicks = null;
      _isScrolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedClipId = ref.watch(songSelectedClipIdProvider);
    // A lane recycled into view by the ListView must catch up to the master
    // scroll offset once it has a position.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromMaster());
    return Container(
      height: _kLaneHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: widget.gutterWidth,
            child: SongTrackHeader(track: widget.track),
          ),
          _VerticalDivider(),
          Expanded(
            child: SingleChildScrollView(
              controller: _laneScroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: widget.timelineWidth,
                height: _kLaneHeight,
                child: GestureDetector(
                  onTapDown: _onTapDown,
                  onLongPressStart: _onLongPressStart,
                  onLongPressMoveUpdate: _onLongPressMoveUpdate,
                  onLongPressEnd: _onLongPressEnd,
                  onLongPressCancel: _onLongPressCancel,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onPanCancel: _onPanCancel,
                  child: CustomPaint(
                    painter: _ClipLanePainter(
                      clips: widget.clips,
                      clipLengths: widget.clipLengths,
                      sharedPatternIds: widget.sharedPatternIds,
                      audioPeaksByClipId: widget.audioPeaksByClipId,
                      audioBrokenClipIds: widget.audioBrokenClipIds,
                      notePreviewByClipId: widget.notePreviewByClipId,
                      drumPreviewByClipId: widget.drumPreviewByClipId,
                      clipLabelById: widget.clipLabelById,
                      measureTicks: widget.measureTicks,
                      totalMeasures: widget.totalMeasures,
                      trackColor: switch (widget.track.type) {
                        SongTrackType.note => MuzicianTheme.sky,
                        SongTrackType.drum => MuzicianTheme.orange,
                        SongTrackType.audio => MuzicianTheme.teal,
                      },
                      currentPlaybackTick: widget.currentPlaybackTick,
                      showEmptyHint:
                          widget.clips.isEmpty && _pendingStartTick == null,
                      pendingStartTick: _pendingStartTick,
                      pendingEndTick: _pendingEndTick,
                      selectedClipId: selectedClipId,
                      pendingMove: _pendingMove,
                      pendingResize: _pendingResize,
                    ),
                    size: Size(widget.timelineWidth, _kLaneHeight),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddClipSheet(
    BuildContext context,
    WidgetRef ref,
    int startTick,
    int lengthTicks,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MuzicianTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (widget.track.type == SongTrackType.audio) {
          return _AddClipSheet(
            title: 'Add Audio Clip',
            subtitle: _audioStartSummary(startTick),
            options: [
              _AddClipOption(
                label: 'Record audio',
                icon: Icons.mic,
                color: MuzicianTheme.teal,
                onTap: () {
                  Navigator.pop(ctx);
                  openAudioRecorder(
                    context,
                    ref,
                    trackId: widget.track.id,
                    startTick: startTick,
                  );
                },
              ),
              _AddClipOption(
                label: 'Import audio file',
                icon: Icons.file_open,
                color: MuzicianTheme.teal,
                onTap: () {
                  Navigator.pop(ctx);
                  importAudioFile(
                    context,
                    ref,
                    trackId: widget.track.id,
                    startTick: startTick,
                  );
                },
              ),
            ],
          );
        }
        if (widget.track.type == SongTrackType.drum) {
          return _AddClipSheet(
            title: 'Add Drum Clip',
            subtitle: _lengthSummary(lengthTicks),
            options: [
              _AddClipOption(
                label: 'New empty drum pattern',
                icon: Icons.album,
                color: MuzicianTheme.orange,
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(songProjectProvider.notifier)
                      .createEmptyDrumPatternClip(
                        trackId: widget.track.id,
                        startTick: startTick,
                        lengthTicks: lengthTicks,
                      );
                },
              ),
              ?_pasteOption(ctx, startTick),
            ],
          );
        }
        return _AddClipSheet(
          title: 'Add Note Clip',
          subtitle: _lengthSummary(lengthTicks),
          options: [
            _AddClipOption(
              label: 'New empty pattern',
              icon: Icons.add_circle_outline,
              color: MuzicianTheme.sky,
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(songProjectProvider.notifier)
                    .createEmptyNotePatternClip(
                      trackId: widget.track.id,
                      startTick: startTick,
                      lengthTicks: lengthTicks,
                    );
              },
            ),
            _AddClipOption(
              label: 'Import from Piano Roll',
              icon: Icons.grid_on,
              color: MuzicianTheme.sky,
              onTap: () {
                Navigator.pop(ctx);
                _openImportPicker(context, 'piano_roll', startTick);
              },
            ),
            _AddClipOption(
              label: 'Import from Piano',
              icon: Icons.piano,
              color: MuzicianTheme.violet,
              onTap: () {
                Navigator.pop(ctx);
                _openImportPicker(context, 'piano', startTick);
              },
            ),
            _AddClipOption(
              label: 'Import from Fretboard',
              icon: Icons.straighten,
              color: MuzicianTheme.teal,
              onTap: () {
                Navigator.pop(ctx);
                _openImportPicker(context, 'fretboard', startTick);
              },
            ),
            ?_pasteOption(ctx, startTick),
          ],
        );
      },
    );
  }

  String _lengthSummary(int lengthTicks) {
    final measures = lengthTicks ~/ widget.measureTicks;
    return measures == 1 ? '1 measure' : '$measures measures';
  }

  /// "Paste copied clip" sheet option, or null when the clipboard is empty,
  /// the pattern type doesn't match this track, or the pattern was deleted.
  _AddClipOption? _pasteOption(BuildContext ctx, int startTick) {
    final clipboard = ref.read(songClipClipboardProvider);
    if (clipboard == null) return null;
    final matches = switch (clipboard.patternType) {
      SongPatternType.note => widget.track.type == SongTrackType.note,
      SongPatternType.drum => widget.track.type == SongTrackType.drum,
      SongPatternType.audio => widget.track.type == SongTrackType.audio,
    };
    if (!matches) return null;
    final project = ref.read(songProjectProvider);
    final exists = switch (clipboard.patternType) {
      SongPatternType.note =>
        project.notePatterns.any((p) => p.id == clipboard.patternId),
      SongPatternType.drum =>
        project.drumPatterns.any((p) => p.id == clipboard.patternId),
      SongPatternType.audio =>
        project.audioPatterns.any((p) => p.id == clipboard.patternId),
    };
    if (!exists) return null;
    return _AddClipOption(
      label: 'Paste copied clip',
      icon: Icons.content_paste,
      color: MuzicianTheme.sky,
      onTap: () {
        Navigator.pop(ctx);
        final id = ref
            .read(songProjectProvider.notifier)
            .addClipReference(
              patternId: clipboard.patternId,
              patternType: clipboard.patternType,
              trackId: widget.track.id,
              startTick: startTick,
            );
        if (id == null && mounted) {
          showGlassSnackbar(
            context,
            title: 'Paste failed',
            message: 'Target slot is occupied.',
            contentType: ContentType.warning,
          );
        }
      },
    );
  }

  String _audioStartSummary(int startTick) {
    final measure = (startTick ~/ widget.measureTicks) + 1;
    return 'Starts at measure $measure';
  }

  void _openImportPicker(
    BuildContext context,
    String instrumentFilter,
    int startTick,
  ) {
    SongImportPickerLauncher.open(
      context: context,
      trackId: widget.track.id,
      instrumentFilter: instrumentFilter,
      startTick: startTick,
    );
  }
}

class _AddClipOption {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _AddClipOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _AddClipSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<_AddClipOption> options;

  const _AddClipSheet({
    required this.title,
    this.subtitle,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final option in options)
              ListTile(
                leading: Icon(option.icon, color: option.color),
                title: Text(
                  option.label,
                  style: const TextStyle(color: MuzicianTheme.textPrimary),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: MuzicianTheme.textMuted,
                ),
                onTap: option.onTap,
              ),
          ],
        ),
      ),
    );
  }
}

/// Indirection so song_arranger_timeline.dart does not depend on the picker
/// implementation directly (it is created in a later task).
abstract final class SongImportPickerLauncher {
  static Future<void> Function({
    required BuildContext context,
    required String trackId,
    required String instrumentFilter,
    required int startTick,
  })?
  _open;

  static void register(
    Future<void> Function({
      required BuildContext context,
      required String trackId,
      required String instrumentFilter,
      required int startTick,
    })
    opener,
  ) {
    _open = opener;
  }

  static Future<void> open({
    required BuildContext context,
    required String trackId,
    required String instrumentFilter,
    required int startTick,
  }) async {
    final opener = _open;
    if (opener == null) {
      showGlassSnackbar(
        context,
        title: 'Not available',
        message: 'Import picker not yet available',
        contentType: ContentType.help,
      );
      return;
    }
    await opener(
      context: context,
      trackId: trackId,
      instrumentFilter: instrumentFilter,
      startTick: startTick,
    );
  }
}

class _ClipLanePainter extends CustomPainter {
  final List<SongClipInstance> clips;
  final Map<String, int> clipLengths;
  final Set<String> sharedPatternIds;
  final Map<String, List<int>> audioPeaksByClipId;
  final Set<String> audioBrokenClipIds;
  final Map<String, NoteClipPreview> notePreviewByClipId;
  final Map<String, DrumClipPreview> drumPreviewByClipId;
  final Map<String, String> clipLabelById;
  final int measureTicks;
  final int totalMeasures;
  final Color trackColor;
  final int? currentPlaybackTick;
  final bool showEmptyHint;
  final int? pendingStartTick;
  final int? pendingEndTick;
  final String? selectedClipId;
  final ({String clipId, int startTick})? pendingMove;
  final ({String clipId, int lengthTicks})? pendingResize;

  const _ClipLanePainter({
    required this.clips,
    required this.clipLengths,
    required this.sharedPatternIds,
    required this.audioPeaksByClipId,
    required this.audioBrokenClipIds,
    required this.notePreviewByClipId,
    required this.drumPreviewByClipId,
    required this.clipLabelById,
    required this.measureTicks,
    required this.totalMeasures,
    required this.trackColor,
    required this.currentPlaybackTick,
    required this.showEmptyHint,
    required this.pendingStartTick,
    required this.pendingEndTick,
    required this.selectedClipId,
    required this.pendingMove,
    required this.pendingResize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measureLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    for (var m = 0; m <= totalMeasures; m++) {
      final x = m * measureTicks * _kTickWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), measureLinePaint);
    }

    for (final clip in clips) {
      final isSelected = clip.id == selectedClipId;
      // Live preview: substitute pending start/length for the dragged clip.
      final startTick = (pendingMove != null && pendingMove!.clipId == clip.id)
          ? pendingMove!.startTick
          : clip.startTick;
      final length = (pendingResize != null && pendingResize!.clipId == clip.id)
          ? pendingResize!.lengthTicks
          : (clipLengths[clip.id] ?? measureTicks);
      final left = startTick * _kTickWidth;
      final right = left + length * _kTickWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left + 1, 6, right - 1, size.height - 6),
        const Radius.circular(6),
      );

      // Body fill.
      final fillAlpha = isSelected ? 0.38 : 0.28;
      final borderAlpha = isSelected ? 1.0 : 0.6;
      final borderWidth = isSelected ? 2.0 : 1.5;

      if (isSelected) {
        // Soft outer glow on the selected clip.
        canvas.drawRRect(
          rect,
          Paint()
            ..color = trackColor.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10),
        );
      }

      canvas.drawRRect(
        rect,
        Paint()
          ..color = trackColor.withValues(alpha: fillAlpha)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = trackColor.withValues(alpha: borderAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );

      // Right-edge resize handle on the selected clip.
      if (isSelected) {
        final handleW = _kResizeHandleTicks * _kTickWidth;
        final handleRect = Rect.fromLTRB(
          right - handleW - 1,
          10,
          right - 2,
          size.height - 10,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(handleRect, const Radius.circular(3)),
          Paint()..color = trackColor.withValues(alpha: 0.85),
        );
        // 3 horizontal grip lines.
        final gripPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..strokeWidth = 1;
        final gripCx = handleRect.left + handleRect.width / 2;
        final gripBaseY = handleRect.top + handleRect.height / 2 - 6;
        for (var i = 0; i < 3; i++) {
          final y = gripBaseY + i * 5;
          canvas.drawLine(
            Offset(gripCx - 3, y),
            Offset(gripCx + 3, y),
            gripPaint,
          );
        }
      }

      // Waveform overlay for audio clips.
      final peaks = audioPeaksByClipId[clip.id];
      if (peaks != null && peaks.isNotEmpty) {
        _paintAudioWaveform(canvas, rect, peaks);
      }
      if (audioBrokenClipIds.contains(clip.id)) {
        _paintBrokenStripes(canvas, rect);
      }

      // Pattern-content thumbnails.
      final notePreview = notePreviewByClipId[clip.id];
      if (notePreview != null) {
        _paintNotePreview(canvas, rect, notePreview);
      }
      final drumPreview = drumPreviewByClipId[clip.id];
      if (drumPreview != null) {
        _paintDrumPreview(canvas, rect, drumPreview);
      }

      // Pattern-name label (when the clip is wide enough).
      final label = clipLabelById[clip.id];
      if (label != null && label.isNotEmpty) {
        _paintClipLabel(canvas, rect.outerRect, label);
      }

      // Shared-pattern badge.
      if (sharedPatternIds.contains(clip.patternId)) {
        _paintSharedBadge(canvas, rect.outerRect);
      }
    }

    final pStart = pendingStartTick;
    final pEnd = pendingEndTick;
    if (pStart != null && pEnd != null && pEnd > pStart) {
      _paintPendingGlow(canvas, size, pStart, pEnd);
    } else if (showEmptyHint) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Long-press to add a clip',
          style: TextStyle(
            color: MuzicianTheme.textMuted.withValues(alpha: 0.8),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(12, (size.height - tp.height) / 2));
    }

    if (currentPlaybackTick != null) {
      final cx = currentPlaybackTick! * _kTickWidth;
      final cursorPaint = Paint()
        ..color = MuzicianTheme.sky
        ..strokeWidth = 2;
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), cursorPaint);
    }
  }

  void _paintPendingGlow(Canvas canvas, Size size, int startTick, int endTick) {
    final left = startTick * _kTickWidth;
    final right = endTick * _kTickWidth;
    final inner = Rect.fromLTRB(left + 1, 4, right - 1, size.height - 4);
    final rrect = RRect.fromRectAndRadius(inner, const Radius.circular(8));

    final glowOuter = Paint()
      ..color = trackColor.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 14);
    canvas.drawRRect(rrect, glowOuter);

    final fill = Paint()
      ..color = trackColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fill);

    final border = Paint()
      ..color = trackColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, border);

    final measures = (endTick - startTick) ~/ measureTicks;
    final label = measures <= 1 ? '1 measure' : '$measures measures';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: inner.width - 12);
    if (tp.width <= inner.width - 12) {
      tp.paint(
        canvas,
        Offset(
          inner.left + (inner.width - tp.width) / 2,
          inner.top + (inner.height - tp.height) / 2,
        ),
      );
    }
  }

  void _paintAudioWaveform(Canvas canvas, RRect rect, List<int> peaks) {
    final inner = rect.outerRect.deflate(4);
    if (inner.width <= 2 || inner.height <= 2) return;
    canvas.save();
    canvas.clipRRect(rect);
    final centerY = inner.center.dy;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.0;
    final width = inner.width.floor();
    for (var x = 0; x < width; x++) {
      final binIndex = ((x / inner.width) * peaks.length).floor();
      final peak = peaks[binIndex.clamp(0, peaks.length - 1)];
      final h = (peak / 255.0) * inner.height * 0.8;
      final xDp = inner.left + x;
      canvas.drawLine(
        Offset(xDp, centerY - h / 2),
        Offset(xDp, centerY + h / 2),
        paint,
      );
    }
    canvas.restore();
  }

  /// Mini piano-roll thumbnail: one rect per note, x scaled by tick, y by
  /// pitch within the pattern's own range.
  void _paintNotePreview(Canvas canvas, RRect rect, NoteClipPreview preview) {
    final inner = rect.outerRect.deflate(5);
    if (inner.width <= 4 || inner.height <= 6 || preview.lengthTicks <= 0) {
      return;
    }
    canvas.save();
    canvas.clipRRect(rect);
    final range = (preview.maxMidi - preview.minMidi + 1).clamp(1, 128);
    final rowH = (inner.height / range).clamp(2.0, 5.0);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final note in preview.notes) {
      final left =
          inner.left + (note.startTick / preview.lengthTicks) * inner.width;
      final w = ((note.durationTicks / preview.lengthTicks) * inner.width)
          .clamp(2.0, inner.width);
      // Higher pitch → higher on screen.
      final t = range == 1
          ? 0.5
          : 1.0 - (note.midiNote - preview.minMidi) / (range - 1);
      final top = inner.top + t * (inner.height - rowH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, rowH),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  /// Step-dot grid: one row per drum lane that has hits.
  void _paintDrumPreview(Canvas canvas, RRect rect, DrumClipPreview preview) {
    final inner = rect.outerRect.deflate(6);
    if (inner.width <= 4 || inner.height <= 6 || preview.lengthTicks <= 0) {
      return;
    }
    final activeLanes = [
      for (final lane in preview.lanes)
        if (lane.activeTicks.isNotEmpty) lane,
    ];
    if (activeLanes.isEmpty) return;
    canvas.save();
    canvas.clipRRect(rect);
    final rowH = inner.height / activeLanes.length;
    final dotR = (rowH / 2).clamp(1.5, 3.0);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var row = 0; row < activeLanes.length; row++) {
      final cy = inner.top + rowH * (row + 0.5);
      for (final tick in activeLanes[row].activeTicks) {
        final cx = inner.left + (tick / preview.lengthTicks) * inner.width;
        canvas.drawCircle(Offset(cx, cy), dotR, paint);
      }
    }
    canvas.restore();
  }

  /// Pattern name in the clip's top-left corner.
  void _paintClipLabel(Canvas canvas, Rect clipRect, String label) {
    if (clipRect.width < 60) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: clipRect.width - 28);
    tp.paint(canvas, Offset(clipRect.left + 6, clipRect.top + 3));
  }

  void _paintBrokenStripes(Canvas canvas, RRect rect) {
    final paint = Paint()
      ..color = const Color(0xCCB23A3A)
      ..strokeWidth = 2.0;
    final r = rect.outerRect;
    canvas.save();
    canvas.clipRRect(rect);
    for (var x = -r.height.toInt(); x < r.width; x += 12) {
      canvas.drawLine(
        Offset(r.left + x, r.top),
        Offset(r.left + x + r.height, r.bottom),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintSharedBadge(Canvas canvas, Rect clipRect) {
    // Skip the badge if the clip is too narrow to fit it cleanly.
    if (clipRect.width < 26) return;
    const padding = 4.0;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.link.codePoint),
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFamily: Icons.link.fontFamily,
          package: Icons.link.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final right = clipRect.right - padding;
    final top = clipRect.top + padding;
    final left = right - tp.width - 4;
    final bottom = top + tp.height + 2;
    final badgeRect = Rect.fromLTRB(left - 2, top, right, bottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    tp.paint(canvas, Offset(left, top + 1));
  }

  @override
  bool shouldRepaint(covariant _ClipLanePainter oldDelegate) =>
      pendingStartTick != oldDelegate.pendingStartTick ||
      pendingEndTick != oldDelegate.pendingEndTick ||
      selectedClipId != oldDelegate.selectedClipId ||
      pendingMove != oldDelegate.pendingMove ||
      pendingResize != oldDelegate.pendingResize ||
      sharedPatternIds != oldDelegate.sharedPatternIds ||
      clips != oldDelegate.clips ||
      clipLengths != oldDelegate.clipLengths ||
      audioPeaksByClipId != oldDelegate.audioPeaksByClipId ||
      audioBrokenClipIds != oldDelegate.audioBrokenClipIds ||
      notePreviewByClipId != oldDelegate.notePreviewByClipId ||
      drumPreviewByClipId != oldDelegate.drumPreviewByClipId ||
      clipLabelById != oldDelegate.clipLabelById ||
      totalMeasures != oldDelegate.totalMeasures ||
      trackColor != oldDelegate.trackColor ||
      currentPlaybackTick != oldDelegate.currentPlaybackTick ||
      showEmptyHint != oldDelegate.showEmptyHint;
}
