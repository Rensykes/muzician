/// Piano Roll V2 — Adaptive landscape/portrait screen shell.
///
/// Landscape: grid on left, inspector/utility rail on right.
/// Portrait: grid as primary surface with collapsible expandable panels.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll.dart';
import '../../models/piano_roll_composer.dart';
import '../../models/piano_roll_playback.dart';
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../store/piano_roll_composer_store.dart';
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_store.dart';
import '../../theme/muzician_theme.dart';
import '../../utils/note_utils.dart';
import '../_mockup_shell.dart';
import 'piano_roll_detection_panel.dart';
import 'piano_roll_grid.dart';
import 'piano_roll_hum_recorder.dart';
import 'piano_roll_save_panel.dart';
import 'piano_roll_save_stack_loader.dart';
import 'piano_roll_scale_picker.dart';
import 'piano_roll_stack_selector.dart';

const _landscapeWidthThreshold = 600.0;
const _roots = <String>[
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
const _qualityLabels = <String>[
  '5th',
  'maj',
  'm',
  '7',
  'maj7',
  'm7',
  'dim',
  'aug',
  'sus2',
  'sus4',
  'm7b5',
  'add9',
  'maj9',
  '6',
  'm6',
  'dim7',
  '7sus4',
];
const _durationLabels = <String>[
  '1/16',
  '1/8',
  '3/16',
  '1/4',
  '3/8',
  '1/2',
  '3/4',
  '1/1',
];
const _snapOptions = <int>[1, 2, 4, 8, 16, 32];
const _snapLabels = <String>['1t', '2t', '4t', '8t', '16t', '32t'];

String _tickToBarBeatDisplay(int? tick, int beatsPerMeasure, int beatUnit) {
  if (tick == null) return '--.--.--';
  final beatTicks = beatUnit == 8 ? 2 : 4;
  final measureTicks = beatTicks * beatsPerMeasure;
  final bar = (tick ~/ measureTicks) + 1;
  final remainder = tick % measureTicks;
  final beat = (remainder ~/ beatTicks) + 1;
  final subTick = remainder % beatTicks;
  return '$bar.$beat.$subTick';
}

String _headerChipLabel(PianoRollState state) {
  final sc = state.selectedColumnTick;
  if (sc == null) return 'No column selected';
  final notes = rules.getNotesAtTick(state.notes, sc);
  if (notes.isEmpty) return 'Empty column';
  final pcs = notes.map((n) => n.pitchClass).toSet().toList();
  if (pcs.length == 1) return pcs.first;
  final r = detectChordsAndScales(pcs);
  if (r.chords.isNotEmpty) return r.chords.first;
  if (r.scales.isNotEmpty) return r.scales.first;
  return '${pcs.length} notes';
}

class PianoRollScreenV2 extends ConsumerStatefulWidget {
  const PianoRollScreenV2({super.key});

  @override
  ConsumerState<PianoRollScreenV2> createState() => _PianoRollScreenV2State();
}

class _PianoRollScreenV2State extends ConsumerState<PianoRollScreenV2> {
  String? _expandedPanel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > _landscapeWidthThreshold;

    return Theme(
      data: MuzicianTheme.dark(),
      child: MockupScaffold(
        activeNavLabel: 'Roll',
        child: isLandscape ? _buildLandscape() : _buildPortrait(),
      ),
    );
  }

  void _togglePanel(String key) {
    setState(() => _expandedPanel = _expandedPanel == key ? null : key);
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
    final barBeat = _tickToBarBeatDisplay(
      state.selectedColumnTick,
      state.config.timeSignature.beatsPerMeasure,
      state.config.timeSignature.beatUnit,
    );

    return Column(
      children: [
        CompactAppBar(
          title: 'Roll',
          chipLabel: _headerChipLabel(state),
          onClose: () => Navigator.of(context).maybePop(),
        ),
        _TransportStrip(
          bpm: state.config.tempo,
          barBeat: barBeat,
          timeSig:
              '${state.config.timeSignature.beatsPerMeasure}/${state.config.timeSignature.beatUnit}',
          onBpmChange: (d) => notifier.setTempo(state.config.tempo + d),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: GlassFrame(child: const PianoRollGrid()),
              ),
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
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      const _PanelSectionHeader('Composer'),
                      Divider(color: MuzicianTheme.glassBorder),
                      _InspectorField(
                        label: 'Root',
                        value: composerState.root,
                        onTap: () async {
                          final v = await showPickerSheet<String>(
                            context: context,
                            title: 'Root',
                            options: _roots,
                            current: composerState.root,
                          );
                          if (v != null) composerNotifier.setRoot(v);
                        },
                      ),
                      _InspectorField(
                        label: 'Quality',
                        value: qualityLabel,
                        onTap: () async {
                          final v = await showPickerSheet<String>(
                            context: context,
                            title: 'Quality',
                            options: _qualityLabels,
                            current: qualityLabel,
                          );
                          if (v != null) {
                            composerNotifier.setQuality(
                              qualitySymbolByLabel[v] ?? 'maj',
                            );
                          }
                        },
                      ),
                      _InspectorField(
                        label: 'Duration',
                        value: durationLabel,
                        onTap: () async {
                          final v = await showPickerSheet<String>(
                            context: context,
                            title: 'Duration',
                            options: _durationLabels,
                            current: durationLabel,
                          );
                          if (v != null) {
                            composerNotifier.setDuration(
                              labelToDurationTicks[v] ?? 4,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _AddStackButton(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          composerNotifier.addStack();
                        },
                      ),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Selection'),
                      Divider(color: MuzicianTheme.glassBorder),
                      _SelectionStatus(state: state),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Edit & Pitch'),
                      Divider(color: MuzicianTheme.glassBorder),
                      _EditPitchControls(state: state),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Stack Selector'),
                      Divider(color: MuzicianTheme.glassBorder),
                      const PianoRollStackSelector(),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Scale'),
                      Divider(color: MuzicianTheme.glassBorder),
                      const PianoRollScalePicker(),
                      if (state.selectedColumnTick != null) ...[
                        const SizedBox(height: 12),
                        const _PanelSectionHeader('Detection'),
                        Divider(color: MuzicianTheme.glassBorder),
                        const PianoRollDetectionPanel(),
                      ],
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Hum Recorder'),
                      Divider(color: MuzicianTheme.glassBorder),
                      const PianoRollHumRecorderPanel(),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Save / Load'),
                      Divider(color: MuzicianTheme.glassBorder),
                      const PianoRollSavePanel(),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Import from Saves'),
                      Divider(color: MuzicianTheme.glassBorder),
                      const PianoRollSaveStackLoader(),
                      const SizedBox(height: 24),
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
    final barBeat = _tickToBarBeatDisplay(
      state.selectedColumnTick,
      state.config.timeSignature.beatsPerMeasure,
      state.config.timeSignature.beatUnit,
    );

    return Column(
      children: [
        CompactAppBar(
          title: 'Roll',
          chipLabel: _headerChipLabel(state),
          onClose: () => Navigator.of(context).maybePop(),
        ),
        _TransportStrip(
          bpm: state.config.tempo,
          barBeat: barBeat,
          timeSig:
              '${state.config.timeSignature.beatsPerMeasure}/${state.config.timeSignature.beatUnit}',
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
              _SelectionStatus(state: state, compact: true),
              const SizedBox(height: 8),
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
                  const SizedBox(width: 6),
                  _QuickChip(
                    label: 'Scale',
                    icon: Icons.piano_rounded,
                    color: MuzicianTheme.teal,
                    onTap: () => _togglePanel('scale'),
                  ),
                  const SizedBox(width: 6),
                  _QuickChip(
                    label: 'Import',
                    icon: Icons.folder_open_rounded,
                    color: MuzicianTheme.emerald,
                    onTap: () => _togglePanel('import'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _QuickChip(
                    label: 'Record',
                    icon: Icons.mic_rounded,
                    color: MuzicianTheme.orange,
                    onTap: () => _togglePanel('hum'),
                  ),
                  const SizedBox(width: 6),
                  _QuickChip(
                    label: 'Save',
                    icon: Icons.save_rounded,
                    color: MuzicianTheme.sky,
                    onTap: () => _togglePanel('save'),
                  ),
                  const SizedBox(width: 6),
                  _QuickChip(
                    label: 'Compose',
                    icon: Icons.edit_rounded,
                    color: MuzicianTheme.violet,
                    onTap: () => _togglePanel('compose'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _PortraitExpander(
                key: const ValueKey('scale'),
                title: 'Scale Highlight',
                expanded: _expandedPanel == 'scale',
                onToggle: () => _togglePanel('scale'),
                child: const PianoRollScalePicker(),
              ),
              _PortraitExpander(
                key: const ValueKey('hum'),
                title: 'Hum Recorder',
                expanded: _expandedPanel == 'hum',
                onToggle: () => _togglePanel('hum'),
                child: const PianoRollHumRecorderPanel(),
              ),
              _PortraitExpander(
                key: const ValueKey('save'),
                title: 'Save / Load',
                expanded: _expandedPanel == 'save',
                onToggle: () => _togglePanel('save'),
                child: const PianoRollSavePanel(),
              ),
              _PortraitExpander(
                key: const ValueKey('import'),
                title: 'Import from Saves',
                expanded: _expandedPanel == 'import',
                onToggle: () => _togglePanel('import'),
                child: const PianoRollSaveStackLoader(),
              ),
              _PortraitExpander(
                key: const ValueKey('compose'),
                title: 'Stack Composer',
                expanded: _expandedPanel == 'compose',
                onToggle: () => _togglePanel('compose'),
                child: const PianoRollStackSelector(),
              ),
              if (state.selectedColumnTick != null)
                _PortraitExpander(
                  key: const ValueKey('detection'),
                  title: 'Detection',
                  expanded: _expandedPanel == 'detection',
                  onToggle: () => _togglePanel('detection'),
                  child: const PianoRollDetectionPanel(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Transport Strip ──────────────────────────────────────────────────────

class _TransportStrip extends ConsumerWidget {
  final int bpm;
  final String barBeat;
  final String timeSig;
  final ValueChanged<int> onBpmChange;

  const _TransportStrip({
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
    required this.onBpmChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(pianoRollPlaybackProvider);
    final playing = playback.status == PianoRollPlaybackStatus.playing;

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
          _PlayBtn(
            playing: playing,
            onTap: () {
              HapticFeedback.lightImpact();
              final notifier = ref.read(pianoRollPlaybackProvider.notifier);
              if (playing) {
                notifier.stopPlayback();
              } else {
                notifier.startPlayback();
              }
            },
          ),
          IconBtn(icon: Icons.stop_rounded, onTap: () {}),
          const SizedBox(width: 6),
          Container(width: 1, height: 20, color: MuzicianTheme.glassBorder),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) {
                if (d.delta.dy.abs() > 4) {
                  onBpmChange(d.delta.dy < 0 ? 1 : -1);
                }
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

// ── Selection Status ─────────────────────────────────────────────────────

class _SelectionStatus extends StatelessWidget {
  final PianoRollState state;
  final bool compact;
  const _SelectionStatus({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sc = state.selectedColumnTick;
    final barBeat = _tickToBarBeatDisplay(
      sc,
      state.config.timeSignature.beatsPerMeasure,
      state.config.timeSignature.beatUnit,
    );
    final noteCount = sc != null
        ? rules.getNotesAtTick(state.notes, sc).length
        : state.notes.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: compact
          ? Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 14,
                  color: MuzicianTheme.sky,
                ),
                const SizedBox(width: 4),
                Text(
                  'Col $barBeat  •  $noteCount notes',
                  style: const TextStyle(
                    color: MuzicianTheme.sky,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Column: $barBeat',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$noteCount note${noteCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: MuzicianTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Edit & Pitch Controls ────────────────────────────────────────────────

class _EditPitchControls extends ConsumerWidget {
  final PianoRollState state;
  const _EditPitchControls({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pianoRollProvider.notifier);
    final tool = state.activeTool;
    final snap = state.snapTicks;
    final prStart = state.pitchRangeStart;
    final prEnd = state.pitchRangeEnd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tool & Snap',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _ToolPill(
              label: '✏ Draw',
              active: tool == PianoRollTool.draw,
              onTap: () => notifier.setActiveTool(PianoRollTool.draw),
            ),
            const SizedBox(width: 6),
            _ToolPill(
              label: '✂ Scissors',
              active: tool == PianoRollTool.scissors,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setActiveTool(PianoRollTool.scissors);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _snapOptions.map((s) {
            final label = _snapLabels[_snapOptions.indexOf(s)];
            return _SnapPill(
              label: label,
              active: snap == s,
              onTap: () => notifier.setSnapTicks(s),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        const Text(
          'Pitch Range',
          style: TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _PitchShiftBtn(
              label: '−1 Oct',
              onTap: () => notifier.shiftPitchRange(-12),
            ),
            const SizedBox(width: 6),
            _PitchShiftBtn(
              label: '+1 Oct',
              onTap: () => notifier.shiftPitchRange(12),
            ),
            const SizedBox(width: 8),
            _PitchShiftBtn(
              label: 'Clear',
              onTap: () => notifier.setPitchRange(48, 84),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Range: C$prStart – C$prEnd',
          style: const TextStyle(
            color: MuzicianTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ToolPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToolPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? MuzicianTheme.sky.withValues(alpha: 0.45)
                : MuzicianTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.sky : MuzicianTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SnapPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SnapPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? MuzicianTheme.teal.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? MuzicianTheme.teal.withValues(alpha: 0.45)
                : MuzicianTheme.glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? MuzicianTheme.teal : MuzicianTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PitchShiftBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PitchShiftBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: MuzicianTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
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

class _AddStackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: MuzicianTheme.violet.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: MuzicianTheme.violet.withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 16, color: MuzicianTheme.violet),
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortraitExpander extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _PortraitExpander({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MuzicianTheme.glassBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: MuzicianTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: MuzicianTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 6),
            child,
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
