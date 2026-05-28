/// Piano Roll V2 — Adaptive landscape/portrait screen shell.
///
/// Landscape: grid on left, inspector/utility rail on right.
/// Portrait: grid as primary surface with collapsible expandable panels.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll.dart';
import '../../models/piano_roll_playback.dart';
import '../../models/save_system.dart' show AppSettings;
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_stack_builder_store.dart';
import '../../store/piano_roll_store.dart';
import '../../store/settings_store.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/transport_strip.dart' as transport;
import '../../ui/core/app_info_panel.dart';
import '../../utils/note_utils.dart';
import '../_mockup_shell.dart';
import 'piano_roll_detection_panel.dart';
import 'piano_roll_grid.dart';
import 'piano_roll_hum_recorder.dart';
import 'piano_roll_save_panel.dart';
import 'piano_roll_save_stack_loader.dart';
import 'piano_roll_scale_picker.dart';
import 'piano_roll_stack_builder.dart';

const _landscapeWidthThreshold = 600.0;

const _snapOptions = <int>[1, 2, 4, 8, 16, 32];
const _snapLabels = <String>['1t', '2t', '4t', '8t', '16t', '32t'];

// TransportStrip helpers (kTimeSignatureOptions, tickToBarBeatDisplay,
// kMinBpm/kMaxBpm) live in lib/ui/transport_strip.dart and are imported as
// `transport`.

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
      case 'stack_builder':
        showWidgetSheet(
          context: context,
          title: 'Stack Builder',
          child: const PianoRollStackBuilder(dismissOnAdd: true),
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
    final barBeat = transport.tickToBarBeatDisplay(
      state.selectedColumnTick,
      state.config.timeSignature,
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
                      const _PanelSectionHeader('Stack Builder'),
                      const SizedBox(height: 4),
                      const PianoRollStackBuilder(),
                      const SizedBox(height: 8),
                      _QuickButton(),
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
    final barBeat = transport.tickToBarBeatDisplay(
      state.selectedColumnTick,
      state.config.timeSignature,
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
  final ValueChanged<String> onOpenPanel;

  const _PortraitActionBar({
    required this.state,
    required this.hasSelection,
    required this.onOpenPanel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              _QuickChip(
                label: 'Stack Builder',
                icon: Icons.add_rounded,
                color: MuzicianTheme.violet,
                onTap: () => onOpenPanel('stack_builder'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Quick',
                icon: Icons.content_paste_rounded,
                color: MuzicianTheme.emerald,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref
                      .read(pianoRollStackBuilderProvider.notifier)
                      .quickAddStack();
                },
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

// ── Tempo / Settings sheets ───────────────────────────────────────────────
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
        child: Consumer(
          builder: (_, sheetRef, _) {
            final tempo = sheetRef.watch(
              pianoRollProvider.select((s) => s.config.tempo),
            );
            return transport.BpmSheet(
              currentBpm: tempo,
              onChanged: (v) =>
                  sheetRef.read(pianoRollProvider.notifier).setTempo(v),
            );
          },
        ),
      );
    }

    Future<void> onSigTap() async {
      HapticFeedback.selectionClick();
      final picked = await showPickerSheet<String>(
        context: context,
        title: 'Time Signature',
        options: transport.kTimeSignatureOptions,
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

    return transport.TransportStrip(
      bpm: bpm,
      barBeat: barBeat,
      timeSig: timeSig,
      playing: playing,
      onRewind: onRewind,
      onStop: onStop,
      onPlayPause: onPlayPause,
      onBpmTap: onBpmTap,
      onSigTap: onSigTap,
      onBpmDelta: (delta) => prNotifier.setTempo(bpm + delta),
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
    final barBeat = transport.tickToBarBeatDisplay(
      sc,
      state.config.timeSignature,
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
              label: 'Select column',
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
            label: 'Select column',
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
              label: '▭ Select',
              active: tool == PianoRollTool.select,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setActiveTool(PianoRollTool.select);
              },
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
    (PianoRollTool.select, Icons.select_all_rounded, 'Select'),
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

/// Landscape quick-add button. Renders as a compact bar below the stack
/// builder section in the utility panel.
class _QuickButton extends ConsumerWidget {
  const _QuickButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        ref.read(pianoRollStackBuilderProvider.notifier).quickAddStack();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MuzicianTheme.emerald.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: MuzicianTheme.emerald.withValues(alpha: 0.35),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_paste_rounded,
              size: 14,
              color: MuzicianTheme.emerald,
            ),
            SizedBox(width: 6),
            Text(
              'Quick — paste selected or repeat last stack',
              style: TextStyle(
                color: MuzicianTheme.emerald,
                fontSize: 11,
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
