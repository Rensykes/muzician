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
import '../../schema/rules/drum_fill_rules.dart';
import '../../store/drum_pattern_playback_store.dart';
import '../../store/song_project_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import '../_mockup_shell.dart';

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
    // Guarded: in widget tests the enclosing ProviderScope container can be
    // torn down before this widget unmounts, which makes `ref` unusable.
    try {
      ref.read(drumPatternPlaybackProvider.notifier).stop();
    } catch (_) {
      // Provider container already disposed — nothing left to stop.
    }
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
            tooltip: 'Clear all',
            icon: const Icon(Icons.clear_all),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => MuzicianDialog(
                  title: 'Clear all steps?',
                  content: const Text('This empties every lane on this pattern.'),
                  actions: [
                    MuzicianDialogButton(
                      'Cancel',
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    MuzicianDialogButton(
                      'Clear',
                      emphasis: MuzicianDialogEmphasis.destructive,
                      onPressed: () => Navigator.pop(ctx, true),
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
            child: DrumMachineEditorBody(
              pattern: pattern,
              tempo: project.config.tempo,
              beatUnit: timeSig.beatUnit,
              onChanged: (updated) {
                ref
                    .read(songProjectProvider.notifier)
                    .applyDrumPattern(patternId, updated);
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

  int get _beatTicks => timeSig.ticksPerBeat;
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

/// Source-agnostic drum machine editor body.
///
/// Renders the same step grid + transport as [DrumMachineEditor] but reads
/// from [pattern] and emits the full updated pattern via [onChanged]. Has no
/// dependency on `songProjectProvider`, so it can be embedded by any feature
/// that owns its own pattern storage (Songwriter, ad-hoc dialogs, etc.).
class DrumMachineEditorBody extends ConsumerStatefulWidget {
  const DrumMachineEditorBody({
    super.key,
    required this.pattern,
    required this.tempo,
    required this.onChanged,
    this.beatUnit = 4,
    this.backing,
  });

  final DrumPattern pattern;
  final int tempo;
  final int beatUnit;
  final void Function(DrumPattern updated) onChanged;

  /// Optional looping chord bed for "audition with backing". When non-null the
  /// editor shows a Backing toggle; when the toggle is on, Play loops over
  /// [backing.loopTicks] with the chord stabs in [backing.notesByTick].
  final ({int loopTicks, Map<int, List<int>> notesByTick})? backing;

  @override
  ConsumerState<DrumMachineEditorBody> createState() =>
      _DrumMachineEditorBodyState();
}

class _DrumMachineEditorBodyState extends ConsumerState<DrumMachineEditorBody> {
  late DrumPattern _pattern;
  bool _backingOn = false;

  @override
  void initState() {
    super.initState();
    _pattern = widget.pattern;
  }

  @override
  void didUpdateWidget(covariant DrumMachineEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pattern.id != widget.pattern.id) {
      _pattern = widget.pattern;
    }
  }

  void _toggle(DrumLaneId laneId, int tick) {
    final lanes = _pattern.lanes.map((l) {
      if (l.laneId != laneId) return l;
      final ticks = [...l.activeTicks];
      if (ticks.contains(tick)) {
        ticks.remove(tick);
      } else {
        ticks.add(tick);
      }
      ticks.sort();
      return l.copyWith(activeTicks: ticks);
    }).toList();
    setState(() => _pattern = _pattern.copyWith(lanes: lanes));
    widget.onChanged(_pattern);
  }

  void _applyLaneTicks(DrumLaneId laneId, List<int> ticks) {
    final lanes = _pattern.lanes.map((l) {
      if (l.laneId != laneId) return l;
      return l.copyWith(activeTicks: ticks);
    }).toList();
    setState(() => _pattern = _pattern.copyWith(lanes: lanes));
    widget.onChanged(_pattern);
  }

  void _openLaneFill(DrumLaneId laneId) {
    showWidgetSheet(
      context: context,
      title: 'Fill lane',
      child: _LaneFillSheet(
        lengthTicks: _pattern.lengthTicks,
        ticksPerBeat: TimeSignature(
          beatsPerMeasure: 4,
          beatUnit: widget.beatUnit,
        ).ticksPerBeat,
        onApply: (ticks) => _applyLaneTicks(laneId, ticks),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(drumPatternPlaybackProvider);
    final playing = playback.status == DrumPatternPlaybackStatus.playing;
    final timeSig = TimeSignature(
      beatsPerMeasure: 4,
      beatUnit: widget.beatUnit,
    );

    void togglePlayback() {
      final notifier = ref.read(drumPatternPlaybackProvider.notifier);
      if (playing) {
        notifier.stop();
      } else {
        final backing = widget.backing;
        if (_backingOn && backing != null) {
          notifier.start(
            pattern: _pattern,
            tempo: widget.tempo,
            backingNotes: backing.notesByTick,
            loopTicks: backing.loopTicks,
          );
        } else {
          notifier.start(pattern: _pattern, tempo: widget.tempo);
        }
      }
      HapticFeedback.lightImpact();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Transport row
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: playing ? 'Stop' : 'Play',
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                color: MuzicianTheme.orange,
                onPressed: togglePlayback,
              ),
              if (widget.backing != null) ...[
                const SizedBox(width: 4),
                FilterChip(
                  key: const Key('backingToggle'),
                  label: const Text('Backing'),
                  selected: _backingOn,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _backingOn = v),
                  backgroundColor: MuzicianTheme.violet.withValues(alpha: 0.12),
                  selectedColor: MuzicianTheme.violet.withValues(alpha: 0.30),
                  side: BorderSide(
                    color: MuzicianTheme.violet.withValues(alpha: 0.5),
                  ),
                  labelStyle: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${widget.tempo} BPM',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: _DrumGrid(
            pattern: _pattern,
            timeSig: timeSig,
            playheadTick: playing ? playback.currentTick : null,
            onToggle: (laneId, tick) {
              HapticFeedback.lightImpact();
              _toggle(laneId, tick);
            },
            onLaneMenu: _openLaneFill,
          ),
        ),
      ],
    );
  }
}

class _DrumGrid extends StatefulWidget {
  final DrumPattern pattern;
  final TimeSignature timeSig;
  final int? playheadTick;
  final void Function(DrumLaneId laneId, int tick) onToggle;
  final void Function(DrumLaneId laneId) onLaneMenu;

  const _DrumGrid({
    required this.pattern,
    required this.timeSig,
    required this.playheadTick,
    required this.onToggle,
    required this.onLaneMenu,
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
    final beatTicks = widget.timeSig.ticksPerBeat;
    final totalGridWidth = _gridWidth(stepCount, beatTicks);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky labels column
        _LaneLabelsColumn(
          lanes: widget.pattern.lanes,
          labels: _laneLabels,
          colors: _laneColors,
          onLaneMenu: widget.onLaneMenu,
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
                  _BeatHeader(stepCount: stepCount, beatTicks: beatTicks),
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
  final void Function(DrumLaneId laneId) onLaneMenu;

  const _LaneLabelsColumn({
    required this.lanes,
    required this.labels,
    required this.colors,
    required this.onLaneMenu,
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
              menuKey: Key('laneFillMenu_${lanes[i].laneId.name}'),
              onMenu: () => onLaneMenu(lanes[i].laneId),
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
  final Key menuKey;
  final VoidCallback onMenu;

  const _LaneLabel({
    required this.label,
    required this.color,
    required this.activeCount,
    required this.isEven,
    required this.menuKey,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kLaneHeight,
      padding: const EdgeInsets.only(left: 10),
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
          IconButton(
            key: menuKey,
            tooltip: 'Fill lane',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
            color: MuzicianTheme.textMuted,
            icon: const Icon(Icons.tune),
            onPressed: onMenu,
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

/// Bottom-sheet controls for filling a single drum lane.
///
/// Offers musical "every-N" presets (derived from [ticksPerBeat]) with a start
/// offset, a Euclidean generator (hits + rotation), and clear-lane. Each action
/// emits the resulting tick list via [onApply] and closes the sheet.
class _LaneFillSheet extends StatefulWidget {
  final int lengthTicks;
  final int ticksPerBeat;
  final void Function(List<int> ticks) onApply;

  const _LaneFillSheet({
    required this.lengthTicks,
    required this.ticksPerBeat,
    required this.onApply,
  });

  @override
  State<_LaneFillSheet> createState() => _LaneFillSheetState();
}

class _LaneFillSheetState extends State<_LaneFillSheet> {
  int _offset = 0;
  late int _hits;
  int _rotation = 0;

  @override
  void initState() {
    super.initState();
    // Default to one hit per beat, clamped to the pattern length.
    final beats = (widget.lengthTicks / widget.ticksPerBeat).floor();
    _hits = beats < 1 ? 1 : beats;
  }

  /// Distinct, ascending every-N step options derived from the beat size.
  List<int> get _stepOptions {
    final beat = widget.ticksPerBeat;
    final raw = <int>{
      1,
      if (beat ~/ 2 >= 1) beat ~/ 2,
      beat,
      beat * 2,
    }.where((s) => s <= widget.lengthTicks).toList()
      ..sort();
    return raw;
  }

  String _stepLabel(int step) {
    final beat = widget.ticksPerBeat;
    if (step == 1) return 'Every step';
    if (step == beat ~/ 2) return 'Every ½ beat';
    if (step == beat) return 'Every beat';
    if (step == beat * 2) return 'Every 2 beats';
    return 'Every $step steps';
  }

  void _applyAndClose(List<int> ticks) {
    widget.onApply(ticks);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FillSectionLabel('Every'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in _stepOptions)
                ActionChip(
                  key: Key('fillEvery_$step'),
                  label: Text(_stepLabel(step)),
                  backgroundColor: MuzicianTheme.orange.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: MuzicianTheme.orange.withValues(alpha: 0.5),
                  ),
                  labelStyle: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  onPressed: () =>
                      _applyAndClose(everyN(widget.lengthTicks, step,
                          offset: _offset)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _StepperRow(
            label: 'Offset',
            value: _offset,
            minusKey: const Key('offsetMinus'),
            plusKey: const Key('offsetPlus'),
            onMinus: _offset > 0 ? () => setState(() => _offset--) : null,
            onPlus: _offset < widget.lengthTicks - 1
                ? () => setState(() => _offset++)
                : null,
          ),
          const Divider(height: 28, color: Colors.white24),
          const _FillSectionLabel('Euclidean'),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Hits',
            value: _hits,
            minusKey: const Key('euclidHitsMinus'),
            plusKey: const Key('euclidHitsPlus'),
            onMinus: _hits > 1 ? () => setState(() => _hits--) : null,
            onPlus: _hits < widget.lengthTicks
                ? () => setState(() => _hits++)
                : null,
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Rotate',
            value: _rotation,
            minusKey: const Key('euclidRotMinus'),
            plusKey: const Key('euclidRotPlus'),
            onMinus: _rotation > 0 ? () => setState(() => _rotation--) : null,
            onPlus: _rotation < widget.lengthTicks - 1
                ? () => setState(() => _rotation++)
                : null,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('fillEuclidApply'),
              style: FilledButton.styleFrom(
                backgroundColor: MuzicianTheme.orange,
              ),
              onPressed: () => _applyAndClose(
                euclid(widget.lengthTicks, _hits, rotation: _rotation),
              ),
              child: const Text('Apply Euclidean'),
            ),
          ),
          const Divider(height: 28, color: Colors.white24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('fillClear'),
              onPressed: () => _applyAndClose(const []),
              child: const Text('Clear lane'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FillSectionLabel extends StatelessWidget {
  final String text;
  const _FillSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: MuzicianTheme.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final Key minusKey;
  final Key plusKey;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.minusKey,
    required this.plusKey,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          key: minusKey,
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline),
          color: MuzicianTheme.textSecondary,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          key: plusKey,
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
          color: MuzicianTheme.textSecondary,
        ),
      ],
    );
  }
}
