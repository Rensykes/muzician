/// Drum Machine Editor — step-sequencer grid for drum patterns.
///
/// A full-screen dialog with sticky lane labels, a scrollable step grid
/// grouped by beat, and a beat-number header. Each step cell is tappable to
/// toggle. Edits are applied immediately via [songProjectProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/piano_roll.dart' show TimeSignature;
import '../../models/song_project.dart';
import '../../store/drum_pattern_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';

const double _kCellSize = 32;
const double _kCellMargin = 2;
const double _kLaneHeight = 40;
const double _kBeatGap = 4;
const double _kLabelColumnWidth = 110;

class DrumMachineEditor extends ConsumerStatefulWidget {
  final String clipId;
  final String patternId;

  const DrumMachineEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  ConsumerState<DrumMachineEditor> createState() => _DrumMachineEditorState();
}

class _DrumMachineEditorState extends ConsumerState<DrumMachineEditor> {
  @override
  void dispose() {
    // Stop the audition loop so it does not keep playing after the editor pops.
    ref.read(drumPatternPlaybackProvider.notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patternId = widget.patternId;
    final clipId = widget.clipId;
    final project = ref.watch(songProjectProvider);
    final pattern = project.drumPatterns.firstWhere((p) => p.id == patternId);
    final usedCount = project.clips
        .where((clip) => clip.patternId == patternId)
        .length;
    final timeSig = project.config.timeSignature;
    final playback = ref.watch(drumPatternPlaybackProvider);
    final playing = playback.status == DrumPatternPlaybackStatus.playing;

    void togglePlayback() {
      final notifier = ref.read(drumPatternPlaybackProvider.notifier);
      if (playing) {
        notifier.stop();
      } else {
        notifier.start(pattern: pattern, tempo: project.config.tempo);
      }
      HapticFeedback.lightImpact();
    }

    void clearAll() {
      ref
          .read(songProjectProvider.notifier)
          .applyDrumPattern(
            patternId,
            pattern.copyWith(
              lanes: [
                for (final lane in pattern.lanes)
                  lane.copyWith(activeTicks: const []),
              ],
            ),
          );
      HapticFeedback.mediumImpact();
    }

    return Scaffold(
      backgroundColor: MuzicianTheme.scaffoldBg,
      appBar: AppBar(
        title: Text(pattern.name),
        actions: [
          IconButton(
            tooltip: playing ? 'Stop' : 'Play',
            icon: Icon(playing ? Icons.stop : Icons.play_arrow),
            color: MuzicianTheme.sky,
            onPressed: togglePlayback,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.clear_all),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: MuzicianTheme.surface,
                  title: const Text(
                    'Clear all steps?',
                    style: TextStyle(color: MuzicianTheme.textPrimary),
                  ),
                  content: const Text(
                    'This empties every lane on this pattern.',
                    style: TextStyle(color: MuzicianTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: MuzicianTheme.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Clear',
                        style: TextStyle(color: MuzicianTheme.red),
                      ),
                    ),
                  ],
                ),
              );
              if (ok == true) clearAll();
            },
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(songProjectProvider.notifier)
                  .makeClipPatternUnique(clipId);
              Navigator.pop(context);
            },
            child: const Text(
              'Make unique',
              style: TextStyle(color: MuzicianTheme.sky),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _MetaRow(
            usedCount: usedCount,
            stepCount: pattern.lengthTicks,
            timeSig: timeSig,
          ),
          Expanded(
            child: _DrumGrid(
              pattern: pattern,
              timeSig: timeSig,
              playheadTick: playing ? playback.currentTick : null,
              onToggle: (laneId, tick) {
                HapticFeedback.lightImpact();
                ref
                    .read(songProjectProvider.notifier)
                    .toggleDrumStep(
                      patternId: patternId,
                      laneId: laneId,
                      tick: tick,
                    );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final int usedCount;
  final int stepCount;
  final TimeSignature timeSig;

  const _MetaRow({
    required this.usedCount,
    required this.stepCount,
    required this.timeSig,
  });

  int get _beatTicks => timeSig.beatUnit == 8 ? 2 : 4;
  int get _measureTicks => _beatTicks * timeSig.beatsPerMeasure;
  String get _lengthLabel {
    final measures = stepCount ~/ _measureTicks;
    if (measures < 1) return '$stepCount steps';
    if (measures == 1) return '1 measure';
    return '$measures measures';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _MetaChip(
            icon: Icons.straighten,
            label: _lengthLabel,
            color: MuzicianTheme.sky,
          ),
          const SizedBox(width: 8),
          _MetaChip(
            icon: Icons.music_note,
            label: '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}',
            color: MuzicianTheme.teal,
          ),
          const Spacer(),
          Text(
            'Used in $usedCount clips',
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrumGrid extends StatefulWidget {
  final DrumPattern pattern;
  final TimeSignature timeSig;
  final int? playheadTick;
  final void Function(DrumLaneId laneId, int tick) onToggle;

  const _DrumGrid({
    required this.pattern,
    required this.timeSig,
    required this.playheadTick,
    required this.onToggle,
  });

  @override
  State<_DrumGrid> createState() => _DrumGridState();
}

class _DrumGridState extends State<_DrumGrid> {
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

  static const Map<DrumLaneId, String> _laneLabels = {
    DrumLaneId.kick: 'Kick',
    DrumLaneId.snare: 'Snare',
    DrumLaneId.closedHiHat: 'Closed HH',
    DrumLaneId.openHiHat: 'Open HH',
    DrumLaneId.clap: 'Clap',
    DrumLaneId.lowTom: 'Low Tom',
    DrumLaneId.highTom: 'High Tom',
    DrumLaneId.crash: 'Crash',
  };

  static const Map<DrumLaneId, Color> _laneColors = {
    DrumLaneId.kick: MuzicianTheme.orange,
    DrumLaneId.snare: MuzicianTheme.sky,
    DrumLaneId.closedHiHat: MuzicianTheme.teal,
    DrumLaneId.openHiHat: MuzicianTheme.violet,
    DrumLaneId.clap: MuzicianTheme.emerald,
    DrumLaneId.lowTom: MuzicianTheme.purple,
    DrumLaneId.highTom: MuzicianTheme.red,
    DrumLaneId.crash: MuzicianTheme.sky,
  };

  @override
  Widget build(BuildContext context) {
    final stepCount = widget.pattern.lengthTicks;
    final beatTicks = widget.timeSig.beatUnit == 8 ? 2 : 4;
    final totalGridWidth = _gridWidth(stepCount, beatTicks);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky labels column
        _LaneLabelsColumn(
          lanes: widget.pattern.lanes,
          labels: _laneLabels,
          colors: _laneColors,
        ),
        // Scrollable grid: beat header + 8 lane rows
        Expanded(
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalGridWidth,
              child: Column(
                children: [
                  _BeatHeader(
                    stepCount: stepCount,
                    beatTicks: beatTicks,
                  ),
                  for (final lane in widget.pattern.lanes)
                    _DrumLaneRow(
                      lane: lane,
                      color: _laneColors[lane.laneId] ?? MuzicianTheme.sky,
                      stepCount: stepCount,
                      beatTicks: beatTicks,
                      onToggle: (tick) => widget.onToggle(lane.laneId, tick),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static double _gridWidth(int stepCount, int beatTicks) {
    final beats = (stepCount / beatTicks).ceil();
    final beatWidth = beatTicks * (_kCellSize + _kCellMargin * 2);
    return beats * beatWidth + (beats - 1) * _kBeatGap + _kCellMargin * 2;
  }
}

class _LaneLabelsColumn extends StatelessWidget {
  final List<DrumLaneSequence> lanes;
  final Map<DrumLaneId, String> labels;
  final Map<DrumLaneId, Color> colors;

  const _LaneLabelsColumn({
    required this.lanes,
    required this.labels,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kLabelColumnWidth,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          // Spacer aligned with beat header.
          const SizedBox(height: 22),
          for (var i = 0; i < lanes.length; i++)
            _LaneLabel(
              label: labels[lanes[i].laneId] ?? lanes[i].laneId.name,
              color: colors[lanes[i].laneId] ?? MuzicianTheme.textSecondary,
              activeCount: lanes[i].activeTicks.length,
              isEven: i % 2 == 0,
            ),
        ],
      ),
    );
  }
}

class _LaneLabel extends StatelessWidget {
  final String label;
  final Color color;
  final int activeCount;
  final bool isEven;

  const _LaneLabel({
    required this.label,
    required this.color,
    required this.activeCount,
    required this.isEven,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kLaneHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (activeCount > 0)
            Text(
              '$activeCount',
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _BeatHeader extends StatelessWidget {
  final int stepCount;
  final int beatTicks;

  const _BeatHeader({required this.stepCount, required this.beatTicks});

  @override
  Widget build(BuildContext context) {
    final beats = (stepCount / beatTicks).ceil();
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (var b = 0; b < beats; b++) ...[
            if (b > 0) const SizedBox(width: _kBeatGap),
            _BeatNumber(beatIndex: b, beatTicks: beatTicks),
          ],
        ],
      ),
    );
  }
}

class _BeatNumber extends StatelessWidget {
  final int beatIndex;
  final int beatTicks;

  const _BeatNumber({required this.beatIndex, required this.beatTicks});

  @override
  Widget build(BuildContext context) {
    final width = beatTicks * (_kCellSize + _kCellMargin * 2);
    final isDownbeat = beatIndex == 0;
    return SizedBox(
      width: width,
      child: Center(
        child: Text(
          '${beatIndex + 1}',
          style: TextStyle(
            color: isDownbeat
                ? MuzicianTheme.textPrimary
                : MuzicianTheme.textMuted,
            fontSize: 11,
            fontWeight: isDownbeat ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _DrumLaneRow extends StatelessWidget {
  final DrumLaneSequence lane;
  final Color color;
  final int stepCount;
  final int beatTicks;
  final void Function(int tick) onToggle;

  const _DrumLaneRow({
    required this.lane,
    required this.color,
    required this.stepCount,
    required this.beatTicks,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isEven = DrumLaneId.values.indexOf(lane.laneId) % 2 == 0;
    final activeTicks = lane.activeTicks.toSet();
    final beats = (stepCount / beatTicks).ceil();
    return Container(
      height: _kLaneHeight,
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          for (var b = 0; b < beats; b++) ...[
            if (b > 0) const SizedBox(width: _kBeatGap),
            for (var i = 0; i < beatTicks; i++)
              () {
                final tick = b * beatTicks + i;
                if (tick >= stepCount) {
                  return const SizedBox(width: _kCellSize + _kCellMargin * 2);
                }
                return _StepCell(
                  active: activeTicks.contains(tick),
                  color: color,
                  isDownbeat: i == 0,
                  onTap: () => onToggle(tick),
                );
              }(),
          ],
        ],
      ),
    );
  }
}

class _StepCell extends StatelessWidget {
  final bool active;
  final Color color;
  final bool isDownbeat;
  final VoidCallback onTap;

  const _StepCell({
    required this.active,
    required this.color,
    required this.isDownbeat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final restingFill = isDownbeat
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.04);
    final restingBorder = isDownbeat
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.08);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: _kCellSize,
        height: _kCellSize,
        margin: const EdgeInsets.all(_kCellMargin),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.85) : restingFill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : restingBorder,
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
