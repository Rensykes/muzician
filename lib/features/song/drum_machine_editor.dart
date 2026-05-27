/// Drum Machine Editor — step-sequencer grid for drum patterns.
///
/// A full-screen dialog that shows 8 drum lanes × N steps, where each step cell
/// is tappable to toggle.  Edits are applied immediately via [songProjectProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song_project.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';

class DrumMachineEditor extends ConsumerWidget {
  final String clipId;
  final String patternId;

  const DrumMachineEditor({
    super.key,
    required this.clipId,
    required this.patternId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songProjectProvider);
    final pattern = project.drumPatterns.firstWhere((p) => p.id == patternId);
    final usedCount = project.clips
        .where((clip) => clip.patternId == patternId)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(pattern.name),
        actions: [
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
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            alignment: Alignment.centerLeft,
            child: Text(
              'Used in $usedCount clips',
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: _DrumGrid(
              pattern: pattern,
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

class _DrumGrid extends StatelessWidget {
  final DrumPattern pattern;
  final void Function(DrumLaneId laneId, int tick) onToggle;

  const _DrumGrid({required this.pattern, required this.onToggle});

  static const _laneLabels = {
    DrumLaneId.kick: 'Kick',
    DrumLaneId.snare: 'Snare',
    DrumLaneId.closedHiHat: 'Closed HH',
    DrumLaneId.openHiHat: 'Open HH',
    DrumLaneId.clap: 'Clap',
    DrumLaneId.lowTom: 'Low Tom',
    DrumLaneId.highTom: 'High Tom',
    DrumLaneId.crash: 'Crash',
  };

  static const _laneColors = {
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: (pattern.lengthTicks * 40.0) + 100.0, // 100px for labels
        child: ListView.builder(
          itemCount: pattern.lanes.length,
          itemBuilder: (context, index) {
            final lane = pattern.lanes[index];
            final label = _laneLabels[lane.laneId] ?? lane.laneId.name;
            final color =
                _laneColors[lane.laneId] ?? MuzicianTheme.textSecondary;
            return _DrumLaneRow(
              label: label,
              color: color,
              lane: lane,
              stepCount: pattern.lengthTicks,
              onToggle: (tick) => onToggle(lane.laneId, tick),
            );
          },
        ),
      ),
    );
  }
}

class _DrumLaneRow extends StatelessWidget {
  final String label;
  final Color color;
  final DrumLaneSequence lane;
  final int stepCount;
  final void Function(int tick) onToggle;

  const _DrumLaneRow({
    required this.label,
    required this.color,
    required this.lane,
    required this.stepCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isEven = DrumLaneId.values.indexOf(lane.laneId) % 2 == 0;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          // Lane label
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Step cells
          Expanded(
            child: Row(
              children: [
                for (var tick = 0; tick < stepCount; tick++)
                  _StepCell(
                    active: lane.activeTicks.contains(tick),
                    color: color,
                    onTap: () => onToggle(tick),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCell extends StatelessWidget {
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _StepCell({
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
    );
  }
}
