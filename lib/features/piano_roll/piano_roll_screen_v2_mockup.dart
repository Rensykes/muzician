/// Piano Roll V2 — UI/UX redesign mockup (iteration 2).
///
/// Embeds the real [PianoRollGrid] so the mockup shows actual cell density
/// and scroll behavior. The transport strip is UI-only; BPM updates real
/// [pianoRollProvider] state. Chord composer fields (root/qual/dur) are
/// local-only — wiring them to a real notifier API is Phase 4 work.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../store/piano_roll_store.dart';
import '../../theme/muzician_theme.dart';
import 'piano_roll_grid.dart';

class PianoRollScreenV2Mockup extends ConsumerStatefulWidget {
  const PianoRollScreenV2Mockup({super.key});

  @override
  ConsumerState<PianoRollScreenV2Mockup> createState() => _PianoRollScreenV2MockupState();
}

class _PianoRollScreenV2MockupState extends ConsumerState<PianoRollScreenV2Mockup> {
  bool _playing = false;
  String _root = 'C';
  String _quality = 'maj';
  String _duration = '1/4';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Roll',
        child: Column(
          children: [
            CompactAppBar(
              title: 'Roll',
              chipLabel: '$_root ionian',
              onClose: () => Navigator.of(context).pop(),
              actions: [
                IconBtn(icon: Icons.bookmark_border_rounded, onTap: () {}),
                IconBtn(icon: Icons.tune_rounded, onTap: () {}),
              ],
            ),
            _TransportStrip(
              playing: _playing,
              bpm: state.config.tempo,
              barBeat: '1.1.0',
              timeSig:
                  '${state.config.timeSignature.beatsPerMeasure}/${state.config.timeSignature.beatUnit}',
              onPlay: () {
                HapticFeedback.lightImpact();
                setState(() => _playing = !_playing);
              },
              onBpmChange: (d) => notifier.setTempo(state.config.tempo + d),
            ),
            Expanded(
              child: GlassFrame(child: const PianoRollGrid()),
            ),
            DockedToolbar(
              children: [
                DockField(
                  value: _root,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Root',
                      options: const [
                        'C', 'C#', 'D', 'D#', 'E', 'F',
                        'F#', 'G', 'G#', 'A', 'A#', 'B',
                      ],
                      current: _root,
                    );
                    if (picked != null) setState(() => _root = picked);
                  },
                ),
                DockField(
                  value: _quality,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Quality',
                      options: const [
                        '5th', 'maj', 'min', 'dom7', 'maj7', 'm7',
                        'sus2', 'sus4', 'dim', 'aug', 'm7♭5',
                        'add9', 'maj9', '6', 'm6', 'dim7', '7sus4',
                      ],
                      current: _quality,
                    );
                    if (picked != null) setState(() => _quality = picked);
                  },
                ),
                DockField(
                  value: _duration,
                  onTap: () async {
                    final picked = await showPickerSheet<String>(
                      context: context,
                      title: 'Duration',
                      options: const ['1/16', '1/8', '1/4', '1/2', '1/1'],
                      current: _duration,
                    );
                    if (picked != null) setState(() => _duration = picked);
                  },
                ),
                DockPrimaryButton(
                  icon: Icons.add_rounded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('+ Stack: $_root$_quality ($_duration)'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: MuzicianTheme.surface,
                        duration: const Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transport strip ─────────────────────────────────────────────────────────

class _TransportStrip extends StatelessWidget {
  final bool playing;
  final int bpm;
  final String barBeat;
  final String timeSig;
  final VoidCallback onPlay;
  final ValueChanged<int> onBpmChange;

  const _TransportStrip({
    required this.playing,
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
    required this.onPlay,
    required this.onBpmChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconBtn(icon: Icons.skip_previous_rounded, onTap: () {}),
          _PlayBtn(playing: playing, onTap: onPlay),
          IconBtn(icon: Icons.stop_rounded, onTap: () {}),
          const SizedBox(width: 6),
          Container(width: 1, height: 20, color: MuzicianTheme.glassBorder),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) {
                if (d.delta.dy.abs() > 4) onBpmChange(d.delta.dy < 0 ? 1 : -1);
              },
              child: Row(
                children: [
                  _Readout(label: 'BPM', value: '$bpm', accent: true),
                  const SizedBox(width: 16),
                  _Readout(label: 'BAR', value: barBeat),
                  const SizedBox(width: 16),
                  _Readout(label: 'SIG', value: timeSig),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
  const _Readout({required this.label, required this.value, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: const TextStyle(
              color: MuzicianTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            )),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: accent ? 16 : 14,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}
