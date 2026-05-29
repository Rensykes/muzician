library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../schema/rules/song_rules.dart' as song_rules;
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import 'song_audio_actions.dart';
import 'song_track_header.dart';

const double _kTickWidth = 4.0;
const double _kRulerHeight = 32;
const double _kLaneHeight = 64;
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

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(songProjectProvider);
    final orderedTracks = [...project.tracks]
      ..sort((a, b) => a.order.compareTo(b.order));

    final clipLengths = <String, int>{};
    final patternRefCount = <String, int>{};
    for (final clip in project.clips) {
      final len = song_rules.patternLengthForClip(project, clip);
      if (len != null) clipLengths[clip.id] = len;
      patternRefCount.update(
        clip.patternId,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    final sharedPatternIds = <String>{
      for (final entry in patternRefCount.entries)
        if (entry.value > 1) entry.key,
    };

    final audioPatternById = {
      for (final p in project.audioPatterns) p.id: p,
    };
    final audioAssetById = {
      for (final a in project.audioAssets) a.id: a,
    };
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
        return Column(
          children: [
            _MeasureRuler(
              totalMeasures: project.config.totalMeasures,
              measureTicks: widget.measureTicks,
              timelineWidth: timelineWidth,
              gutterWidth: gutterWidth,
              hScroll: _hScroll,
              currentPlaybackTick: widget.currentPlaybackTick,
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
        );
      },
    );
  }
}

class _MeasureRuler extends StatelessWidget {
  final int totalMeasures;
  final int measureTicks;
  final double timelineWidth;
  final double gutterWidth;
  final ScrollController hScroll;
  final int? currentPlaybackTick;

  const _MeasureRuler({
    required this.totalMeasures,
    required this.measureTicks,
    required this.timelineWidth,
    required this.gutterWidth,
    required this.hScroll,
    required this.currentPlaybackTick,
  });

  @override
  Widget build(BuildContext context) {
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
          SizedBox(width: gutterWidth, child: const _GutterCorner()),
          _VerticalDivider(),
          Expanded(
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: timelineWidth,
                height: _kRulerHeight,
                child: CustomPaint(
                  painter: _RulerPainter(
                    totalMeasures: totalMeasures,
                    measureTicks: measureTicks,
                    currentPlaybackTick: currentPlaybackTick,
                  ),
                  size: Size(timelineWidth, _kRulerHeight),
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

  const _RulerPainter({
    required this.totalMeasures,
    required this.measureTicks,
    required this.currentPlaybackTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final measureWidth = measureTicks * _kTickWidth;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

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
      currentPlaybackTick != oldDelegate.currentPlaybackTick;
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

  int _tickAtDx(double dx) => (dx / _kTickWidth).round().clamp(
    0,
    widget.measureTicks * widget.totalMeasures,
  );

  int _snapToMeasure(int tick) =>
      (tick / widget.measureTicks).round() * widget.measureTicks;

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

    final start = _snapToMeasure(tick).clamp(
      0,
      widget.measureTicks * widget.totalMeasures - widget.measureTicks,
    );
    final ceiling =
        _nextClipStartAfter(start) ??
        widget.measureTicks * widget.totalMeasures;
    final defaultEnd = (start + widget.measureTicks).clamp(start + 1, ceiling);

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
    ).clamp(start + widget.measureTicks, ceiling);
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
      final clip = widget.clips.firstWhere(
        (c) => c.id == _pendingMove!.clipId,
      );
      final length = widget.clipLengths[clip.id] ?? widget.measureTicks;
      final grab = _grabOffsetTicks ?? 0;
      final rawStart = tick - grab;
      final maxStart =
          (widget.measureTicks * widget.totalMeasures) - length;
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
      final clip = project.clips.firstWhere((c) => c.id == pendingResize.clipId);
      if (clip.patternType == SongPatternType.note) {
        final pattern = project.notePatterns
            .firstWhere((p) => p.id == clip.patternId);
        if (pattern.lengthTicks != pendingResize.lengthTicks) {
          notifier.applyNotePattern(
            clip.patternId,
            pattern.copyWith(lengthTicks: pendingResize.lengthTicks),
          );
        }
      } else {
        final pattern = project.drumPatterns
            .firstWhere((p) => p.id == clip.patternId);
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
      final clip = widget.clips
          .firstWhere((c) => c.id == pendingMove.clipId);
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
              controller: widget.hScroll,
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
          ],
        );
      },
    );
  }

  String _lengthSummary(int lengthTicks) {
    final measures = lengthTicks ~/ widget.measureTicks;
    return measures == 1 ? '1 measure' : '$measures measures';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import picker not yet available')),
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
      totalMeasures != oldDelegate.totalMeasures ||
      trackColor != oldDelegate.trackColor ||
      currentPlaybackTick != oldDelegate.currentPlaybackTick ||
      showEmptyHint != oldDelegate.showEmptyHint;
}
