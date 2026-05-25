/// Piano Roll V2 — Adaptive landscape/portrait screen shell.
///
/// Landscape: grid on left, inspector/utility rail on right.
/// Portrait: grid as primary surface with collapsible panels.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../_mockup_shell.dart';
import '../../models/piano_roll_composer.dart';
import '../../store/piano_roll_composer_store.dart';
import '../../store/piano_roll_store.dart';
import '../../theme/muzician_theme.dart';
import 'piano_roll_grid.dart';

// ── Breakpoint ───────────────────────────────────────────────────────────

const _kLandscapeWidthThreshold = 600.0;

// ── Screen ───────────────────────────────────────────────────────────────

class PianoRollScreenV2 extends ConsumerStatefulWidget {
  const PianoRollScreenV2({super.key});

  @override
  ConsumerState<PianoRollScreenV2> createState() => _PianoRollScreenV2State();
}

class _PianoRollScreenV2State extends ConsumerState<PianoRollScreenV2> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > _kLandscapeWidthThreshold;

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Roll',
        child: isLandscape ? _buildLandscape() : _buildPortrait(),
      ),
    );
  }

  // ── Landscape ──────────────────────────────────────────────────────────

  Widget _buildLandscape() {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);
    final composerState = ref.watch(pianoRollComposerProvider);
    final composerNotifier = ref.read(pianoRollComposerProvider.notifier);
    final qualityLabel = qualityLabelBySymbol[composerState.quality] ?? 'maj';
    final durationLabel =
        durationTicksToLabel[composerState.durationTicks] ?? '1/4';

    return Column(
      children: [
        CompactAppBar(
          title: 'Roll',
          chipLabel: '${composerState.root} ionian',
          onClose: () => Navigator.of(context).maybePop(),
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
          child: Row(
            children: [
              // Grid occupies most horizontal space
              Expanded(
                flex: 3,
                child: GlassFrame(child: const PianoRollGrid()),
              ),
              // Utility panel on the right
              Expanded(
                flex: 1,
                child: Container(
                  key: const ValueKey('v2-utility-panel'),
                  margin: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                  decoration: BoxDecoration(
                    color: MuzicianTheme.glassBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MuzicianTheme.glassBorder),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const _PanelSectionHeader('Composer'),
                      Divider(color: MuzicianTheme.glassBorder),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            _InspectorField(
                              label: 'Root',
                              value: composerState.root,
                              onTap: () {},
                            ),
                            _InspectorField(
                              label: 'Quality',
                              value: qualityLabel,
                              onTap: () {},
                            ),
                            _InspectorField(
                              label: 'Duration',
                              value: durationLabel,
                              onTap: () {},
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                composerNotifier.addStack();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: MuzicianTheme.violet.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: MuzicianTheme.violet.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                      color: MuzicianTheme.violet,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Add Stack',
                                      style: TextStyle(
                                        color: MuzicianTheme.violet,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Portrait ───────────────────────────────────────────────────────────

  Widget _buildPortrait() {
    final state = ref.watch(pianoRollProvider);
    final notifier = ref.read(pianoRollProvider.notifier);
    final composerState = ref.watch(pianoRollComposerProvider);

    return Column(
      children: [
        CompactAppBar(
          title: 'Roll',
          chipLabel: '${composerState.root} ionian',
          onClose: () => Navigator.of(context).maybePop(),
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
        Expanded(child: GlassFrame(child: const PianoRollGrid())),
        Container(
          key: const ValueKey('v2-portrait-panels'),
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: MuzicianTheme.glassBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MuzicianTheme.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PanelSectionHeader('Quick Actions'),
              const SizedBox(height: 6),
              Row(
                children: [
                  _QuickChip(
                    label: 'Add Stack',
                    icon: Icons.add_rounded,
                    color: MuzicianTheme.violet,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      ref.read(pianoRollComposerProvider.notifier).addStack();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Reusable sub-widgets ─────────────────────────────────────────────────

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
                  const SizedBox(width: 8),
                  _Readout(label: 'BAR', value: barBeat),
                  const SizedBox(width: 8),
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
  const _Readout({
    required this.label,
    required this.value,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
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
      ),
    );
  }
}

// ── Inspector/Utility panel sub-widgets ──────────────────────────────────

class _PanelSectionHeader extends StatelessWidget {
  final String label;
  const _PanelSectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: MuzicianTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InspectorField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InspectorField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MuzicianTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MuzicianTheme.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: MuzicianTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
