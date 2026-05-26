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
import '../../models/save_system.dart' show AppSettings;
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../store/piano_roll_composer_store.dart';
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/app_info_panel.dart';
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

const _timeSignatureOptions = <String>[
  '2/4',
  '3/4',
  '4/4',
  '5/4',
  '6/8',
  '7/8',
  '12/8',
];
const _minBpm = 40;
const _maxBpm = 300;

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
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > _landscapeWidthThreshold;

    // V2 is hosted as a top-level tab body — the parent app scaffold owns
    // the bottom navigation, so we render only the gradient surface here.
    return Theme(
      data: MuzicianTheme.dark(),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: MuzicianTheme.gradientColors,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: isLandscape ? _buildLandscape() : _buildPortrait(),
        ),
      ),
    );
  }

  void _openPanel(String key) {
    HapticFeedback.selectionClick();
    switch (key) {
      case 'scale':
        showWidgetSheet(
          context: context,
          title: 'Scale Highlight',
          child: const PianoRollScalePicker(),
        );
      case 'hum':
        showWidgetSheet(
          context: context,
          title: 'Hum Recorder',
          child: const PianoRollHumRecorderPanel(),
        );
      case 'save':
        showWidgetSheet(
          context: context,
          title: 'Save / Load',
          child: const PianoRollSavePanel(),
        );
      case 'import':
        showWidgetSheet(
          context: context,
          title: 'Import from Saves',
          child: const PianoRollSaveStackLoader(),
        );
      case 'compose':
        showWidgetSheet(
          context: context,
          title: 'Stack Composer',
          child: const _ComposerSheet(),
        );
      case 'detection':
        showWidgetSheet(
          context: context,
          title: 'Detection',
          child: const PianoRollDetectionPanel(),
        );
      case 'settings':
        showWidgetSheet(
          context: context,
          title: 'Roll Settings',
          child: const _SettingsSheet(),
        );
      case 'help':
        showAppInfoPanel(context, initialTab: 2);
    }
  }

  // ── Landscape ──────────────────────────────────────────────────────────

  Widget _buildLandscape() {
    final state = ref.watch(pianoRollProvider);
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
          actions: [
            IconBtn(
              icon: Icons.help_outline_rounded,
              onTap: () => _openPanel('help'),
            ),
            IconBtn(
              icon: Icons.settings_outlined,
              onTap: () => _openPanel('settings'),
            ),
          ],
        ),
        _TransportStrip(
          bpm: state.config.tempo,
          barBeat: barBeat,
          timeSig: state.config.timeSignature,
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
                      _SelectionActions(state: state),
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
          actions: [
            IconBtn(
              icon: Icons.help_outline_rounded,
              onTap: () => _openPanel('help'),
            ),
            IconBtn(
              icon: Icons.settings_outlined,
              onTap: () => _openPanel('settings'),
            ),
          ],
        ),
        _TransportStrip(
          bpm: state.config.tempo,
          barBeat: barBeat,
          timeSig: state.config.timeSignature,
        ),
        Expanded(child: GlassFrame(child: const PianoRollGrid())),
        _PortraitActionBar(
          state: state,
          hasSelection: state.selectedColumnTick != null,
          onAddStack: () {
            HapticFeedback.mediumImpact();
            ref.read(pianoRollComposerProvider.notifier).addStack();
          },
          onOpenPanel: _openPanel,
        ),
      ],
    );
  }
}

/// Slim action bar shown under the grid in portrait. Fixed height so the
/// [PianoRollGrid] above never shrinks when panels are opened — every panel
/// opens as a modal [showWidgetSheet] on-top instead.
class _PortraitActionBar extends ConsumerWidget {
  final PianoRollState state;
  final bool hasSelection;
  final VoidCallback onAddStack;
  final ValueChanged<String> onOpenPanel;

  const _PortraitActionBar({
    required this.state,
    required this.hasSelection,
    required this.onAddStack,
    required this.onOpenPanel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composerState = ref.watch(pianoRollComposerProvider);
    final qualityLabel = qualityLabelBySymbol[composerState.quality] ?? 'maj';
    final durationLabel =
        durationTicksToLabel[composerState.durationTicks] ?? '1/4';
    final presetLabel = '${composerState.root}$qualityLabel $durationLabel';

    return Container(
      key: const ValueKey('v2-portrait-actionbar'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status (left, ellipsis-safe) + tool segment (right, fixed width).
          // Sharing the row keeps the action bar at 3 rows total and the grid
          // height untouched.
          Row(
            children: [
              Expanded(child: _SelectionStatus(state: state, compact: true)),
              _SelectionActions(state: state, compact: true),
              const SizedBox(width: 8),
              const _ToolModeSegment(),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _AddPresetSplitChip(
                presetLabel: presetLabel,
                onAdd: onAddStack,
                onCompose: () => onOpenPanel('compose'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Scale',
                icon: Icons.piano_rounded,
                color: MuzicianTheme.teal,
                onTap: () => onOpenPanel('scale'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Detect',
                icon: Icons.graphic_eq_rounded,
                color: hasSelection
                    ? MuzicianTheme.sky
                    : MuzicianTheme.textMuted,
                onTap: hasSelection ? () => onOpenPanel('detection') : null,
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
                onTap: () => onOpenPanel('hum'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Save',
                icon: Icons.save_rounded,
                color: MuzicianTheme.sky,
                onTap: () => onOpenPanel('save'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Import',
                icon: Icons.folder_open_rounded,
                color: MuzicianTheme.emerald,
                onTap: () => onOpenPanel('import'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Split CTA chip combining the primary "Add stack with current preset"
/// action with a chevron that opens the [_ComposerSheet] to edit the preset
/// or pick from the stack library.
///
/// Layout (single chip):
///   [ +  Cmaj 1/4 ][ ⌄ ]
///   |  main tap  | chevron tap |
class _AddPresetSplitChip extends StatelessWidget {
  final String presetLabel;
  final VoidCallback onAdd;
  final VoidCallback onCompose;

  const _AddPresetSplitChip({
    required this.presetLabel,
    required this.onAdd,
    required this.onCompose,
  });

  @override
  Widget build(BuildContext context) {
    const accent = MuzicianTheme.violet;
    return Expanded(
      flex: 2,
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAdd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            presetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: accent.withValues(alpha: 0.35)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onCompose();
                },
                child: const SizedBox(
                  width: 32,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: accent,
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

/// Bottom-sheet body that bundles composer fields + add stack + stack list.
/// Used by the 'compose' / 'Stacks' chip in portrait so users can configure
/// chord parameters without crowding the action bar.
class _ComposerSheet extends ConsumerWidget {
  const _ComposerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composerState = ref.watch(pianoRollComposerProvider);
    final composerNotifier = ref.read(pianoRollComposerProvider.notifier);
    final qualityLabel = qualityLabelBySymbol[composerState.quality] ?? 'maj';
    final durationLabel =
        durationTicksToLabel[composerState.durationTicks] ?? '1/4';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _InspectorField(
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
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InspectorField(
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
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InspectorField(
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
                    composerNotifier.setDuration(labelToDurationTicks[v] ?? 4);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _AddStackButton(
          onTap: () {
            HapticFeedback.mediumImpact();
            composerNotifier.addStack();
          },
        ),
        const SizedBox(height: 16),
        const _PanelSectionHeader('Stacks'),
        Divider(color: MuzicianTheme.glassBorder, height: 8),
        const PianoRollStackSelector(),
      ],
    );
  }
}

// ── Tempo / Settings sheets ───────────────────────────────────────────────

/// Bottom-sheet for editing the playback tempo. Combines a numeric text input,
/// ±1 / ±10 step buttons and a slider. All controls write live to the piano
/// roll provider; the sheet has no separate "apply" step.
class _BpmSheet extends ConsumerStatefulWidget {
  const _BpmSheet();

  @override
  ConsumerState<_BpmSheet> createState() => _BpmSheetState();
}

class _BpmSheetState extends ConsumerState<_BpmSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final tempo = ref.read(pianoRollProvider).config.tempo;
    _controller = TextEditingController(text: tempo.toString());
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _commit(int value) {
    final clamped = value.clamp(_minBpm, _maxBpm);
    ref.read(pianoRollProvider.notifier).setTempo(clamped);
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
      // Restore to current valid value on bad input.
      _commit(ref.read(pianoRollProvider).config.tempo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tempo = ref.watch(pianoRollProvider.select((s) => s.config.tempo));
    // Sync controller when tempo changes externally (e.g. via step button),
    // but skip while the user is actively composing input.
    if (!_focusNode.hasFocus && _controller.text != tempo.toString()) {
      _controller.text = tempo.toString();
    }

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
            _StepBtn(label: '−10', onTap: () => _commit(tempo - 10)),
            const SizedBox(width: 8),
            _StepBtn(label: '−1', onTap: () => _commit(tempo - 1)),
            const SizedBox(width: 16),
            _StepBtn(label: '+1', onTap: () => _commit(tempo + 1)),
            const SizedBox(width: 8),
            _StepBtn(label: '+10', onTap: () => _commit(tempo + 10)),
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
            value: tempo.toDouble().clamp(
              _minBpm.toDouble(),
              _maxBpm.toDouble(),
            ),
            min: _minBpm.toDouble(),
            max: _maxBpm.toDouble(),
            divisions: _maxBpm - _minBpm,
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
            children: const [
              Text(
                '$_minBpm',
                style: TextStyle(
                  color: MuzicianTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$_maxBpm',
                style: TextStyle(
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

/// Bottom-sheet for page-level Roll settings (currently: metronome toggle).
class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToggleRow(
          icon: Icons.timer_outlined,
          label: 'Metronome',
          value: settings.metronomeEnabled,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            settingsNotifier.setMetronomeEnabled(v);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Plays a click on every beat during playback. Accent on the '
          'downbeat (beat 1).',
          style: TextStyle(
            color: MuzicianTheme.textMuted,
            fontSize: 11,
            height: 1.4,
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
  final TimeSignature timeSig;

  const _TransportStrip({
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(pianoRollPlaybackProvider);
    final playing = playback.status == PianoRollPlaybackStatus.playing;
    final playbackNotifier = ref.read(pianoRollPlaybackProvider.notifier);
    final prNotifier = ref.read(pianoRollProvider.notifier);
    final timeSigLabel = '${timeSig.beatsPerMeasure}/${timeSig.beatUnit}';

    void onRewind() {
      HapticFeedback.selectionClick();
      playbackNotifier.stopPlayback();
      prNotifier.selectColumn(0);
    }

    void onStop() {
      HapticFeedback.lightImpact();
      playbackNotifier.stopPlayback();
      prNotifier.selectColumn(null);
    }

    void onPlayPause() {
      HapticFeedback.lightImpact();
      if (playing) {
        playbackNotifier.stopPlayback();
      } else {
        playbackNotifier.startPlayback();
      }
    }

    Future<void> onBpmTap() async {
      HapticFeedback.selectionClick();
      await showWidgetSheet(
        context: context,
        title: 'Tempo',
        child: const _BpmSheet(),
      );
    }

    Future<void> onSigTap() async {
      HapticFeedback.selectionClick();
      final picked = await showPickerSheet<String>(
        context: context,
        title: 'Time Signature',
        options: _timeSignatureOptions,
        current: timeSigLabel,
      );
      if (picked == null) return;
      final parts = picked.split('/');
      prNotifier.setTimeSignature(
        TimeSignature(
          beatsPerMeasure: int.parse(parts[0]),
          beatUnit: int.parse(parts[1]),
        ),
      );
    }

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
          IconBtn(icon: Icons.skip_previous_rounded, onTap: onRewind),
          _PlayBtn(playing: playing, onTap: onPlayPause),
          IconBtn(icon: Icons.stop_rounded, onTap: onStop),
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
                  // Vertical-drag fine-tune retained for quick adjustment
                  // (±1 BPM per ~4px of vertical drag).
                  onVerticalDragUpdate: (d) {
                    if (d.delta.dy.abs() > 4) {
                      prNotifier.setTempo(bpm + (d.delta.dy < 0 ? 1 : -1));
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

// ── Selection Status ─────────────────────────────────────────────────────

class _SelectionStatus extends StatelessWidget {
  final PianoRollState state;
  final bool compact;
  const _SelectionStatus({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final sc = state.selectedColumnTick;
    final selectedCount = state.selectedNoteIds.length;
    final hasSelectedNotes = selectedCount > 0;
    final barBeat = _tickToBarBeatDisplay(
      sc,
      state.config.timeSignature.beatsPerMeasure,
      state.config.timeSignature.beatUnit,
    );
    final noteCount = hasSelectedNotes
        ? selectedCount
        : sc != null
        ? rules.getNotesAtTick(state.notes, sc).length
        : state.notes.length;
    final statusLabel = hasSelectedNotes
        ? 'Selected  •  $noteCount note${noteCount == 1 ? '' : 's'}'
        : 'Col $barBeat  •  $noteCount notes';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: compact
          ? LayoutBuilder(
              builder: (context, constraints) {
                final showLeadingIcon = constraints.maxWidth >= 28;
                return Row(
                  children: [
                    if (showLeadingIcon) ...[
                      Icon(
                        Icons.my_location_rounded,
                        size: 14,
                        color: MuzicianTheme.sky,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MuzicianTheme.sky,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSelectedNotes ? 'Selection' : 'Column: $barBeat',
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

class _SelectionActions extends ConsumerWidget {
  final PianoRollState state;
  final bool compact;
  const _SelectionActions({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pianoRollProvider.notifier);
    final columnTick = state.selectedColumnTick;
    final hasSelectedNotes = state.selectedNoteIds.isNotEmpty;
    final hasColumnNotes =
        columnTick != null &&
        rules.getNotesAtTick(state.notes, columnTick).isNotEmpty;

    void selectColumnNotes() {
      if (columnTick == null) return;
      notifier.selectNotesAtTick(columnTick);
    }

    if (!hasSelectedNotes && !hasColumnNotes) return const SizedBox.shrink();

    if (compact) {
      final showSelectColumnAction = hasColumnNotes && !hasSelectedNotes;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSelectColumnAction)
            _SelectionActionIcon(
              icon: Icons.select_all_rounded,
              label: 'Select notes at column',
              color: MuzicianTheme.sky,
              onTap: selectColumnNotes,
            ),
          if (hasSelectedNotes)
            _SelectionActionIcon(
              icon: Icons.deselect_rounded,
              label: 'Clear note selection',
              color: MuzicianTheme.teal,
              onTap: notifier.clearSelection,
            ),
          if (hasSelectedNotes)
            _SelectionActionIcon(
              icon: Icons.delete_outline_rounded,
              label: 'Delete selected notes',
              color: MuzicianTheme.orange,
              onTap: notifier.deleteSelectedNotes,
            ),
          const SizedBox(width: 8),
        ],
      );
    }

    return Row(
      children: [
        if (hasColumnNotes)
          _QuickChip(
            label: 'Select @ Col',
            icon: Icons.select_all_rounded,
            color: MuzicianTheme.sky,
            onTap: selectColumnNotes,
          ),
        if (hasColumnNotes && hasSelectedNotes) const SizedBox(width: 6),
        if (hasSelectedNotes)
          _QuickChip(
            label: 'Clear',
            icon: Icons.deselect_rounded,
            color: MuzicianTheme.teal,
            onTap: notifier.clearSelection,
          ),
        if (hasSelectedNotes) const SizedBox(width: 6),
        if (hasSelectedNotes)
          _QuickChip(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            color: MuzicianTheme.orange,
            onTap: notifier.deleteSelectedNotes,
          ),
      ],
    );
  }
}

class _SelectionActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SelectionActionIcon({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkResponse(
              onTap: onTap,
              radius: 20,
              child: Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ),
          ),
        ),
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

/// Icon-only segmented control for the four piano-roll tap modes.
///
/// Sits inside the action bar's status row (left = status, right = segment)
/// so the grid height is not affected. Stays in sync with
/// [PianoRollState.activeTool] — selection persists across panel sheets.
///
/// Grid wiring currently honours only Draw and Split; Paint and Delete are
/// surfaced here so the placement can be reviewed before binding them to
/// gesture handlers in `piano_roll_grid.dart`.
class _ToolModeSegment extends ConsumerWidget {
  const _ToolModeSegment();

  static const _entries = <(PianoRollTool, IconData, String)>[
    (PianoRollTool.draw, Icons.edit_rounded, 'Draw'),
    (PianoRollTool.scissors, Icons.content_cut_rounded, 'Split'),
    (PianoRollTool.paint, Icons.brush_rounded, 'Paint'),
    (PianoRollTool.delete, Icons.delete_outline_rounded, 'Delete'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(pianoRollProvider.select((s) => s.activeTool));
    final notifier = ref.read(pianoRollProvider.notifier);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _entries.length; i++) ...[
              if (i > 0) Container(width: 1, color: MuzicianTheme.glassBorder),
              _ToolSegmentItem(
                icon: _entries[i].$2,
                label: _entries[i].$3,
                active: tool == _entries[i].$1,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.setActiveTool(_entries[i].$1);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolSegmentItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolSegmentItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: active
              ? MuzicianTheme.sky.withValues(alpha: 0.18)
              : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: active ? MuzicianTheme.sky : MuzicianTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _QuickChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
