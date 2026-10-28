/// Shared playback transport strip + BPM editor sheet.
///
/// Used by the Piano Roll and Song workspaces so the rewind / play-pause /
/// stop / BPM / BAR / time-signature readouts stay visually consistent.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/piano_roll.dart' show TimeSignature;
import '../theme/studio_theme.dart';

const int kMinBpm = 40;
const int kMaxBpm = 300;

const List<String> kTimeSignatureOptions = <String>[
  '2/4',
  '3/4',
  '4/4',
  '5/4',
  '6/8',
  '7/8',
  '12/8',
];

/// Formats an absolute tick as `bar.beat.sub` (e.g. `1.1.0`).
///
/// Returns `--.--.--` when [tick] is null.
String tickToBarBeatDisplay(int? tick, TimeSignature ts) {
  if (tick == null) return '--.--.--';
  final beatTicks = ts.ticksPerBeat;
  final measureTicks = beatTicks * ts.beatsPerMeasure;
  final bar = (tick ~/ measureTicks) + 1;
  final remainder = tick % measureTicks;
  final beat = (remainder ~/ beatTicks) + 1;
  final subTick = remainder % beatTicks;
  return '$bar.$beat.$subTick';
}

/// Pure visual transport bar. All actions are routed through the supplied
/// callbacks; this widget does not depend on any specific store.
class TransportStrip extends StatelessWidget {
  final int bpm;
  final String barBeat;
  final TimeSignature timeSig;
  final bool playing;
  final VoidCallback onRewind;
  final VoidCallback onStop;
  final VoidCallback onPlayPause;
  final VoidCallback? onBpmTap;
  final VoidCallback? onSigTap;

  /// Whether to show the tappable time-signature readout. Hosts that must keep
  /// one fixed measure (Writer's melody Piano Roll) hide it.
  final bool showTimeSignature;

  /// Called when the user fine-tunes BPM via a vertical drag on the BPM
  /// readout. Receives `+1` for up-drag, `-1` for down-drag.
  final ValueChanged<int>? onBpmDelta;

  /// Extra controls rendered after the readouts (e.g. tempo-multiplier or
  /// metronome chips supplied by the hosting workspace).
  final List<Widget> extras;

  /// A control pinned to the right of the scrollable readouts.
  final Widget? trailing;

  /// Whether to draw the translucent card around the transport. Hosts that
  /// want a bare toolbar (Studio Piano Roll) pass `false`.
  final bool framed;

  const TransportStrip({
    super.key,
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
    required this.playing,
    required this.onRewind,
    required this.onStop,
    required this.onPlayPause,
    required this.onBpmTap,
    required this.onSigTap,
    this.showTimeSignature = true,
    this.onBpmDelta,
    this.extras = const [],
    this.trailing,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final timeSigLabel = '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}';
    return Container(
      height: 48,
      margin: framed
          ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
          : EdgeInsets.zero,
      decoration: framed
          ? BoxDecoration(
              color: palette.glassBg,
              borderRadius: BorderRadius.circular(palette.isStudio ? 6 : 12),
              border: Border.all(color: palette.glassBorder),
            )
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            const SizedBox(width: 4),
            _IconBtn(icon: Icons.skip_previous_rounded, onTap: onRewind),
            _PlayBtn(playing: playing, onTap: onPlayPause),
            _IconBtn(icon: Icons.stop_rounded, onTap: onStop),
            const SizedBox(width: 6),
            Container(
              width: 1,
              height: 20,
              color: StudioPalette.of(context).glassBorder,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Readout(
                      label: 'BPM',
                      value: '$bpm',
                      accent: true,
                      onTap: onBpmTap,
                      onVerticalDragUpdate: onBpmDelta == null
                          ? null
                          : (d) {
                              if (d.delta.dy.abs() > 4) {
                                onBpmDelta!(d.delta.dy < 0 ? 1 : -1);
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    _Readout(label: 'BAR', value: barBeat),
                    if (showTimeSignature) ...[
                      const SizedBox(width: 8),
                      _Readout(
                        label: 'SIG',
                        value: timeSigLabel,
                        onTap: onSigTap,
                      ),
                    ],
                    for (final extra in extras) ...[
                      const SizedBox(width: 8),
                      extra,
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              Container(width: 1, height: 20, color: palette.glassBorder),
              const SizedBox(width: 8),
              trailing!,
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Icon(
          icon,
          color: StudioPalette.of(context).textSecondary,
          size: 22,
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayBtn({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: StudioPalette.of(context).isStudio ? 44 : 38,
          height: StudioPalette.of(context).isStudio ? 44 : 38,
          decoration: BoxDecoration(
            shape: StudioPalette.of(context).isStudio
                ? BoxShape.rectangle
                : BoxShape.circle,
            borderRadius: StudioPalette.of(context).isStudio
                ? BorderRadius.circular(6)
                : null,
            color: StudioPalette.of(context).isStudio
                ? Colors.transparent
                : StudioPalette.of(context).sky,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: StudioPalette.of(context).isStudio
                ? StudioPalette.of(context).sky
                : StudioPalette.of(context).onAccent,
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  const _Readout({
    required this.label,
    required this.value,
    this.accent = false,
    this.onTap,
    this.onVerticalDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: TextStyle(
            color: StudioPalette.of(context).textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: StudioPalette.of(context).textPrimary,
            fontSize: accent ? 14 : 12,
            fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    final tappable = onTap != null || onVerticalDragUpdate != null;
    // Intrinsic width: the readout row lives inside a horizontal scroll view,
    // so it must shrink-wrap rather than expand.
    return tappable
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onVerticalDragUpdate: onVerticalDragUpdate,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
              ),
              child: Center(child: row),
            ),
          )
        : row;
  }
}

/// Numeric BPM editor sheet — text field + ±1 / ±10 step buttons + slider.
///
/// The sheet keeps its text input in sync with [currentBpm] (so external
/// changes propagate while the sheet is open) and writes every change via
/// [onChanged].
class BpmSheet extends StatefulWidget {
  final int currentBpm;
  final ValueChanged<int> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;
  final int minBpm;
  final int maxBpm;

  const BpmSheet({
    super.key,
    required this.currentBpm,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.minBpm = kMinBpm,
    this.maxBpm = kMaxBpm,
  });

  @override
  State<BpmSheet> createState() => _BpmSheetState();
}

class _BpmSheetState extends State<BpmSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentBpm.toString());
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant BpmSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        _controller.text != widget.currentBpm.toString()) {
      _controller.text = widget.currentBpm.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit(int value) {
    final clamped = value.clamp(widget.minBpm, widget.maxBpm);
    widget.onChanged(clamped);
    final text = clamped.toString();
    if (_controller.text != text) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  void _commitFromText() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed != null) {
      _commit(parsed);
    } else {
      _commit(widget.currentBpm);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            maxLength: 3,
            cursorColor: StudioPalette.of(context).sky,
            style: TextStyle(
              color: StudioPalette.of(context).textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              counterText: '',
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            onSubmitted: (_) {
              _commitFromText();
              _focusNode.unfocus();
            },
            onTapOutside: (_) {
              _commitFromText();
              _focusNode.unfocus();
            },
          ),
        ),
        Text(
          'BPM',
          style: TextStyle(
            color: StudioPalette.of(context).textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepBtn(
              label: '−10',
              onTap: () => _commit(widget.currentBpm - 10),
            ),
            const SizedBox(width: 8),
            _StepBtn(label: '−1', onTap: () => _commit(widget.currentBpm - 1)),
            const SizedBox(width: 16),
            _StepBtn(label: '+1', onTap: () => _commit(widget.currentBpm + 1)),
            const SizedBox(width: 8),
            _StepBtn(
              label: '+10',
              onTap: () => _commit(widget.currentBpm + 10),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: StudioPalette.of(context).sky,
            inactiveTrackColor: StudioPalette.of(context).glassBorder,
            thumbColor: StudioPalette.of(context).sky,
            overlayColor: StudioPalette.of(context).sky.withValues(alpha: 0.18),
            trackHeight: 3,
          ),
          child: Slider(
            value: widget.currentBpm.toDouble().clamp(
              widget.minBpm.toDouble(),
              widget.maxBpm.toDouble(),
            ),
            min: widget.minBpm.toDouble(),
            max: widget.maxBpm.toDouble(),
            divisions: widget.maxBpm - widget.minBpm,
            onChangeStart: (_) => widget.onChangeStart?.call(),
            onChangeEnd: (_) => widget.onChangeEnd?.call(),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _commit(v.round());
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.minBpm}',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${widget.maxBpm}',
                style: TextStyle(
                  color: StudioPalette.of(context).textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: BoxConstraints(
          minWidth: 48,
          minHeight: StudioPalette.of(context).isStudio ? 44 : 36,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: (StudioPalette.of(context).isStudio
              ? StudioPalette.of(context).glassBg
              : Colors.white.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioPalette.of(context).glassBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: StudioPalette.of(context).textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
