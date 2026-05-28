/// Shared playback transport strip + BPM editor sheet.
///
/// Used by the Piano Roll and Song workspaces so the rewind / play-pause /
/// stop / BPM / BAR / time-signature readouts stay visually consistent.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/piano_roll.dart' show TimeSignature;
import '../theme/muzician_theme.dart';

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
  final beatTicks = ts.beatUnit == 8 ? 2 : 4;
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
  final VoidCallback onBpmTap;
  final VoidCallback onSigTap;

  /// Called when the user fine-tunes BPM via a vertical drag on the BPM
  /// readout. Receives `+1` for up-drag, `-1` for down-drag.
  final ValueChanged<int>? onBpmDelta;

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
    this.onBpmDelta,
  });

  @override
  Widget build(BuildContext context) {
    final timeSigLabel = '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}';
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            const SizedBox(width: 4),
            _IconBtn(icon: Icons.skip_previous_rounded, onTap: onRewind),
            _PlayBtn(playing: playing, onTap: onPlayPause),
            _IconBtn(icon: Icons.stop_rounded, onTap: onStop),
            const SizedBox(width: 6),
            Container(width: 1, height: 20, color: MuzicianTheme.glassBorder),
            const SizedBox(width: 10),
            Expanded(
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
                  const SizedBox(width: 8),
                  _Readout(label: 'SIG', value: timeSigLabel, onTap: onSigTap),
                ],
              ),
            ),
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
        child: Icon(icon, color: MuzicianTheme.textSecondary, size: 22),
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
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MuzicianTheme.sky,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: MuzicianTheme.scaffoldBg,
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
          style: const TextStyle(
            color: MuzicianTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: accent ? 14 : 12,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final tappable = onTap != null || onVerticalDragUpdate != null;
    return Expanded(
      child: tappable
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onVerticalDragUpdate: onVerticalDragUpdate,
              child: row,
            )
          : row,
    );
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
  final int minBpm;
  final int maxBpm;

  const BpmSheet({
    super.key,
    required this.currentBpm,
    required this.onChanged,
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
            cursorColor: MuzicianTheme.sky,
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
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
        const Text(
          'BPM',
          style: TextStyle(
            color: MuzicianTheme.textMuted,
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
            activeTrackColor: MuzicianTheme.sky,
            inactiveTrackColor: MuzicianTheme.glassBorder,
            thumbColor: MuzicianTheme.sky,
            overlayColor: MuzicianTheme.sky.withValues(alpha: 0.18),
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
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${widget.maxBpm}',
                style: const TextStyle(
                  color: MuzicianTheme.textMuted,
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
        constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
