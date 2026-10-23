/// Piano Roll V2 — Adaptive landscape/portrait screen shell.
///
/// Landscape: grid on left, inspector/utility rail on right.
/// Studio uses a bounded inspector; legacy hosts retain their existing shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/piano_roll.dart';
import '../../models/piano_roll_stack_builder.dart';
import '../../models/piano_roll_playback.dart';
import '../../models/save_system.dart' show AppSettings;
import '../../schema/rules/piano_roll_rules.dart' as rules;
import '../../store/piano_roll_playback_store.dart';
import '../../store/piano_roll_stack_builder_store.dart';
import '../../store/piano_roll_store.dart';
import '../../store/settings_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/project_chip.dart';
import '../../ui/transport_strip.dart' as transport;
import '../../ui/core/app_info_panel.dart';
import '../../utils/note_utils.dart';
import '../_mockup_shell.dart';
import '../instrument_shared/shared_scale_picker.dart';
import 'piano_roll_detection_panel.dart';
import 'piano_roll_grid.dart';
import 'piano_roll_hum_recorder.dart';
import 'piano_roll_save_panel.dart';
import 'piano_roll_save_stack_loader.dart';
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
  /// Whether to show the scale picker entry points (landscape section, portrait
  /// chip).  The Song workspace mounts this shell with [showScale] = false so
  /// the active scale is inherited from the song.
  final bool showScale;

  /// Whether to show the save/load and import-from-saves panels.  Disabled in
  /// embedded contexts (Song workspace) where loading would smash the host's
  /// pattern length and scale state.
  final bool showSavePanels;

  /// Whether to draw the outer SafeArea gradient background.  Disabled when
  /// the shell is mounted inside another scaffold that already provides one.
  final bool showBackground;

  const PianoRollScreenV2({
    super.key,
    this.showScale = true,
    this.showSavePanels = true,
    this.showBackground = true,
  });

  @override
  ConsumerState<PianoRollScreenV2> createState() => _PianoRollScreenV2State();
}

class _PianoRollScreenV2State extends ConsumerState<PianoRollScreenV2> {
  int _inspectorTab = 0;
  bool _inspectorExpanded = true;

  @override
  Widget build(BuildContext context) {
    final palette = StudioPalette.of(context);
    final body = LayoutBuilder(
      builder: (context, constraints) {
        if (palette.isStudio) return _buildStudio(constraints);
        return constraints.maxWidth > _landscapeWidthThreshold
            ? _buildLandscape()
            : _buildPortrait();
      },
    );
    if (!widget.showBackground) return body;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.gradientColors,
        ),
      ),
      child: SafeArea(bottom: false, child: body),
    );
  }

  Widget _buildStudio(BoxConstraints constraints) {
    final state = ref.watch(pianoRollProvider);
    final palette = StudioPalette.of(context);
    final wide = constraints.maxWidth >= 700;
    final short = constraints.maxHeight < 500;
    final inspectorHeight = (constraints.maxHeight * .33).clamp(80.0, 220.0);
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: PianoRollGrid()),
        if (!short &&
            constraints.maxHeight >= 650 &&
            _inspectorTab != 1 &&
            (state.selectedColumnTick != null ||
                state.selectedNoteIds.isNotEmpty))
          Container(
            key: const ValueKey('studio-column-summary'),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.glassBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Column ${transport.tickToBarBeatDisplay(state.selectedColumnTick, state.config.timeSignature)} · ${_headerChipLabel(state)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                _SelectionActions(state: state, compact: true),
              ],
            ),
          ),
      ],
    );
    final inspector = _StudioInspector(
      state: state,
      tab: _inspectorTab,
      expanded: _inspectorExpanded,
      onTab: (index) => setState(() {
        _inspectorTab = index;
        _inspectorExpanded = true;
      }),
      onToggle: () => setState(() => _inspectorExpanded = !_inspectorExpanded),
    );
    return Column(
      key: const ValueKey('studio-piano-roll'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (short)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Piano Roll',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...[
                  const ProjectChip(),
                  IconButton(
                    tooltip: 'Piano Roll help',
                    icon: const Icon(Icons.help_outline_rounded),
                    onPressed: () => _openPanel('help'),
                  ),
                  IconButton(
                    tooltip: 'Roll Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _openPanel('settings'),
                  ),
                ],
              ],
            ),
          )
        else
          WorkspaceHeader(
            title: 'Piano Roll',
            actions: [
              const ProjectChip(),
              IconButton(
                tooltip: 'Piano Roll help',
                icon: const Icon(Icons.help_outline_rounded),
                onPressed: () => _openPanel('help'),
              ),
              IconButton(
                tooltip: 'Roll Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _openPanel('settings'),
              ),
            ],
          ),
        _TransportStrip(
          bpm: state.config.tempo,
          barBeat: transport.tickToBarBeatDisplay(
            state.selectedColumnTick,
            state.config.timeSignature,
          ),
          timeSig: state.config.timeSignature,
          framed: false,
        ),
        _StudioToolRow(
          allowWrap: constraints.maxHeight >= 800,
          trailing: short ? _studioUtilityActions() : const [],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: grid),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: _inspectorExpanded ? 320 : 56,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  _inspectorTab == 0 &&
                                      ref
                                              .watch(
                                                pianoRollStackBuilderProvider,
                                              )
                                              .activeView ==
                                          PianoRollStackBuilderView.canonical
                                  ? 260
                                  : double.infinity,
                            ),
                            child: inspector,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: grid),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: _inspectorExpanded ? inspectorHeight : 48,
                        child: inspector,
                      ),
                    ],
                  ),
          ),
        ),
        if (!short)
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.glassBorder)),
            ),
            child: LayoutBuilder(
              builder: (context, bounds) {
                final fit =
                    bounds.maxWidth >= 390 &&
                    bounds.maxWidth < 700 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 15;
                final actions = _studioUtilityActions(compact: fit);
                if (fit) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        for (final action in actions) Expanded(child: action),
                      ],
                    ),
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: actions),
                );
              },
            ),
          ),
      ],
    );
  }

  List<Widget> _studioUtilityActions({bool compact = false}) => [
    _StudioAction(
      label: 'Quick',
      compact: compact,
      stacked: compact,
      icon: Icons.content_paste_rounded,
      onTap: () =>
          ref.read(pianoRollStackBuilderProvider.notifier).quickAddStack(),
    ),
    if (widget.showScale)
      _StudioAction(
        label: 'Scale',
        compact: compact,
        stacked: compact,
        icon: Icons.piano_rounded,
        onTap: () => _openPanel('scale'),
      ),
    _StudioAction(
      label: 'Hum recorder',
      compact: compact,
      stacked: compact,
      compactLabel: 'Hum',
      icon: Icons.mic_rounded,
      onTap: () => _openPanel('hum'),
    ),
    if (widget.showSavePanels) ...[
      _StudioAction(
        label: 'Save',
        compact: compact,
        stacked: compact,
        icon: Icons.save_outlined,
        onTap: () => _openPanel('save'),
      ),
      _StudioAction(
        label: 'Import',
        compact: compact,
        stacked: compact,
        icon: Icons.folder_open_rounded,
        onTap: () => _openPanel('import'),
      ),
    ],
  ];

  Future<void> _showPanel(String title, Widget panel) => showWidgetSheet(
    context: context,
    title: title,
    child: UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: panel,
    ),
  );

  void _openPanel(String key) {
    HapticFeedback.selectionClick();
    switch (key) {
      case 'scale':
        if (!widget.showScale) return;
        _showPanel(
          'Scale Highlight',
          SharedScalePicker(binding: pianoRollScaleBinding),
        );
      case 'hum':
        _showPanel('Hum Recorder', const PianoRollHumRecorderPanel());
      case 'save':
        if (!widget.showSavePanels) return;
        _showPanel('Save / Load', const PianoRollSavePanel());
      case 'import':
        if (!widget.showSavePanels) return;
        _showPanel('Import from Saves', const PianoRollSaveStackLoader());
      case 'stack_builder':
        _showPanel(
          'Stack Builder',
          const PianoRollStackBuilder(dismissOnAdd: true),
        );
      case 'detection':
        _showPanel('Detection', const PianoRollDetectionPanel());
      case 'settings':
        _showPanel('Roll Settings', const _SettingsSheet());
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
            const ProjectChip(),
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
                    color: StudioPalette.of(context).glassBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: StudioPalette.of(context).glassBorder,
                    ),
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
                      Divider(color: StudioPalette.of(context).glassBorder),
                      _SelectionStatus(state: state),
                      _SelectionActions(state: state),
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Edit & Pitch'),
                      Divider(color: StudioPalette.of(context).glassBorder),
                      _EditPitchControls(state: state),
                      const SizedBox(height: 12),
                      if (widget.showScale) ...[
                        const _PanelSectionHeader('Scale'),
                        Divider(color: StudioPalette.of(context).glassBorder),
                        SharedScalePicker(binding: pianoRollScaleBinding),
                      ],
                      if (state.selectedColumnTick != null) ...[
                        const SizedBox(height: 12),
                        const _PanelSectionHeader('Detection'),
                        Divider(color: StudioPalette.of(context).glassBorder),
                        const PianoRollDetectionPanel(),
                      ],
                      const SizedBox(height: 12),
                      const _PanelSectionHeader('Hum Recorder'),
                      Divider(color: StudioPalette.of(context).glassBorder),
                      const PianoRollHumRecorderPanel(),
                      if (widget.showSavePanels) ...[
                        const SizedBox(height: 12),
                        const _PanelSectionHeader('Save / Load'),
                        Divider(color: StudioPalette.of(context).glassBorder),
                        const PianoRollSavePanel(),
                        const SizedBox(height: 12),
                        const _PanelSectionHeader('Import from Saves'),
                        Divider(color: StudioPalette.of(context).glassBorder),
                        const PianoRollSaveStackLoader(),
                      ],
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
            const ProjectChip(),
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
          showScale: widget.showScale,
          showSavePanels: widget.showSavePanels,
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
  final bool showScale;
  final bool showSavePanels;

  const _PortraitActionBar({
    required this.state,
    required this.hasSelection,
    required this.onOpenPanel,
    this.showScale = true,
    this.showSavePanels = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: const ValueKey('v2-portrait-actionbar'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: StudioPalette.of(context).glassBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioPalette.of(context).glassBorder),
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
                color: StudioPalette.of(context).violet,
                onTap: () => onOpenPanel('stack_builder'),
              ),
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Quick',
                icon: Icons.content_paste_rounded,
                color: StudioPalette.of(context).emerald,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref
                      .read(pianoRollStackBuilderProvider.notifier)
                      .quickAddStack();
                },
              ),
              if (showScale) ...[
                const SizedBox(width: 6),
                _QuickChip(
                  label: 'Scale',
                  icon: Icons.piano_rounded,
                  color: StudioPalette.of(context).teal,
                  onTap: () => onOpenPanel('scale'),
                ),
              ],
              const SizedBox(width: 6),
              _QuickChip(
                label: 'Detect',
                icon: Icons.graphic_eq_rounded,
                color: hasSelection
                    ? StudioPalette.of(context).sky
                    : StudioPalette.of(context).textMuted,
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
                color: StudioPalette.of(context).orange,
                onTap: () => onOpenPanel('hum'),
              ),
              if (showSavePanels) ...[
                const SizedBox(width: 6),
                _QuickChip(
                  label: 'Save',
                  icon: Icons.save_rounded,
                  color: StudioPalette.of(context).sky,
                  onTap: () => onOpenPanel('save'),
                ),
                const SizedBox(width: 6),
                _QuickChip(
                  label: 'Import',
                  icon: Icons.folder_open_rounded,
                  color: StudioPalette.of(context).emerald,
                  onTap: () => onOpenPanel('import'),
                ),
              ],
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
        Text(
          'Plays a click on every beat during playback. Accent on the '
          'downbeat (beat 1).',
          style: TextStyle(
            color: StudioPalette.of(context).textMuted,
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
  final bool framed;

  const _TransportStrip({
    required this.bpm,
    required this.barBeat,
    required this.timeSig,
    this.framed = true,
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
        child: UncontrolledProviderScope(
          container: ProviderScope.containerOf(context),
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
      framed: framed,
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
                        color: StudioPalette.of(context).sky,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: StudioPalette.of(context).sky,
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
                  style: TextStyle(
                    color: StudioPalette.of(context).textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$noteCount note${noteCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: StudioPalette.of(context).textMuted,
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
              color: StudioPalette.of(context).sky,
              onTap: selectColumnNotes,
            ),
          if (hasSelectedNotes)
            _SelectionActionIcon(
              icon: Icons.deselect_rounded,
              label: 'Clear note selection',
              color: StudioPalette.of(context).teal,
              onTap: notifier.clearSelection,
            ),
          if (hasSelectedNotes)
            _SelectionActionIcon(
              icon: Icons.delete_outline_rounded,
              label: 'Delete selected notes',
              color: StudioPalette.of(context).orange,
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
            color: StudioPalette.of(context).sky,
            onTap: selectColumnNotes,
          ),
        if (hasColumnNotes && hasSelectedNotes) const SizedBox(width: 6),
        if (hasSelectedNotes)
          _QuickChip(
            label: 'Clear',
            icon: Icons.deselect_rounded,
            color: StudioPalette.of(context).teal,
            onTap: notifier.clearSelection,
          ),
        if (hasSelectedNotes) const SizedBox(width: 6),
        if (hasSelectedNotes)
          _QuickChip(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            color: StudioPalette.of(context).orange,
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
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final tool = state.activeTool;
    final snap = state.snapTicks;
    final prStart = state.pitchRangeStart;
    final prEnd = state.pitchRangeEnd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tool & Snap',
          style: TextStyle(
            color: StudioPalette.of(context).textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ToolPill(
              label: '✏ Draw',
              active: tool == PianoRollTool.draw,
              onTap: () => notifier.setActiveTool(PianoRollTool.draw),
            ),
            _ToolPill(
              label: '▭ Select',
              active: tool == PianoRollTool.select,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setActiveTool(PianoRollTool.select);
              },
            ),
            _ToolPill(
              label: '✂ Scissors',
              active: tool == PianoRollTool.scissors,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setActiveTool(PianoRollTool.scissors);
              },
            ),
            if (StudioPalette.of(context).isStudio) ...[
              _ToolPill(
                label: 'Paint',
                active: tool == PianoRollTool.paint,
                onTap: () => notifier.setActiveTool(PianoRollTool.paint),
              ),
              _ToolPill(
                label: 'Delete',
                active: tool == PianoRollTool.delete,
                onTap: () => notifier.setActiveTool(PianoRollTool.delete),
              ),
            ],
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
        Text(
          'Pitch Range',
          style: TextStyle(
            color: StudioPalette.of(context).textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PitchShiftBtn(
              label: '−1 Oct',
              onTap: () => notifier.shiftPitchRange(-12),
            ),
            _PitchShiftBtn(
              label: '+1 Oct',
              onTap: () => notifier.shiftPitchRange(12),
            ),
            _PitchShiftBtn(
              label: 'Clear',
              onTap: () => notifier.setPitchRange(48, 84),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          StudioPalette.of(context).isStudio
              ? '${formatMidiNoteLabel(prStart, spelling: spelling)} – ${formatMidiNoteLabel(prEnd, spelling: spelling)}'
              : 'Range: C$prStart – C$prEnd',
          style: TextStyle(
            color: StudioPalette.of(context).textMuted,
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
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
          minWidth: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? StudioPalette.of(context).sky.withValues(alpha: 0.16)
              : (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).textPrimary
                        : Colors.white)
                    .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? StudioPalette.of(context).sky.withValues(alpha: 0.45)
                : StudioPalette.of(context).glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? StudioPalette.of(context).sky
                : StudioPalette.of(context).textSecondary,
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
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
          minWidth: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? StudioPalette.of(context).teal.withValues(alpha: 0.16)
              : (StudioPalette.of(context).isStudio
                        ? StudioPalette.of(context).textPrimary
                        : Colors.white)
                    .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? StudioPalette.of(context).teal.withValues(alpha: 0.45)
                : StudioPalette.of(context).glassBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? StudioPalette.of(context).teal
                : StudioPalette.of(context).textSecondary,
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
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
          minWidth: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              (StudioPalette.of(context).isStudio
                      ? StudioPalette.of(context).textPrimary
                      : Colors.white)
                  .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioPalette.of(context).glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: StudioPalette.of(context).textSecondary,
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
        style: TextStyle(
          color: StudioPalette.of(context).textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Legacy icon-only segmented control for the five piano-roll tools.
///
/// Sits inside the action bar's status row (left = status, right = segment)
/// so the grid height is not affected. Stays in sync with
/// [PianoRollState.activeTool] — selection persists across panel sheets.
///
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
      height: StudioPalette.of(context).isStudio ? 44 : 36,
      decoration: BoxDecoration(
        color:
            (StudioPalette.of(context).isStudio
                    ? StudioPalette.of(context).textPrimary
                    : Colors.white)
                .withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: StudioPalette.of(context).glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _entries.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  color: StudioPalette.of(context).glassBorder,
                ),
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
              ? StudioPalette.of(context).sky.withValues(alpha: 0.18)
              : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: active
                ? StudioPalette.of(context).sky
                : StudioPalette.of(context).textMuted,
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
          color: StudioPalette.of(context).emerald.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: StudioPalette.of(context).emerald.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.content_paste_rounded,
              size: 14,
              color: StudioPalette.of(context).emerald,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Quick — paste selected or repeat last stack',
                textAlign: TextAlign.center,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: StudioPalette.of(context).emerald,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
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

const _studioTools = <(PianoRollTool, IconData, String)>[
  (PianoRollTool.draw, Icons.edit_rounded, 'Draw'),
  (PianoRollTool.select, Icons.select_all_rounded, 'Select'),
  (PianoRollTool.scissors, Icons.content_cut_rounded, 'Split'),
  (PianoRollTool.paint, Icons.brush_rounded, 'Paint'),
  (PianoRollTool.delete, Icons.delete_outline_rounded, 'Delete'),
];

class _StudioToolRow extends ConsumerWidget {
  const _StudioToolRow({this.trailing = const [], this.allowWrap = false});
  final List<Widget> trailing;

  /// Wraps onto a second line only when the host has vertical room. Short
  /// viewports keep the original single scrollable row so the grid survives.
  final bool allowWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pianoRollProvider);
    final p = StudioPalette.of(context);
    final spelling = ref.watch(
      settingsProvider.select((settings) => settings.noteSpelling),
    );
    final rangeLabel =
        '${formatMidiNoteLabel(state.pitchRangeStart, spelling: spelling)}'
        '–'
        '${formatMidiNoteLabel(state.pitchRangeEnd, spelling: spelling)}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final children = <Widget>[
          for (final (tool, icon, label) in _studioTools)
            SizedBox(
              width: compact && MediaQuery.textScalerOf(context).scale(12) <= 13
                  ? (state.activeTool == tool ? 88 : 44)
                  : null,
              child: _StudioAction(
                key: ValueKey('studio-tool-${tool.name}'),
                label: label,
                icon: icon,
                showLabel: !compact || state.activeTool == tool,
                compact: compact,
                selected: state.activeTool == tool,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(pianoRollProvider.notifier).setActiveTool(tool);
                },
              ),
            ),
          SizedBox(
            width: compact && MediaQuery.textScalerOf(context).scale(12) <= 13
                ? 84
                : null,
            child: TextButton(
              key: const ValueKey('studio-roll-snap'),
              onPressed: () async {
                final snap = await showStudioDialog<int>(
                  context: context,
                  builder: (dialogContext) => SimpleDialog(
                    title: Row(
                      children: [
                        const Expanded(child: Text('Snap')),
                        IconButton(
                          tooltip: 'Close Snap',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    children: [
                      for (final ticks in _snapOptions)
                        SimpleDialogOption(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(ticks),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          child: Text('${ticks}t'),
                        ),
                    ],
                  ),
                );
                if (context.mounted && snap != null) {
                  ref.read(pianoRollProvider.notifier).setSnapTicks(snap);
                }
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: p.textPrimary,
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Snap ${state.snapTicks}t',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.expand_more_rounded, size: 16),
                ],
              ),
            ),
          ),
          Text(
            rangeLabel,
            key: const ValueKey('studio-roll-pitch-range'),
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          _PitchTextAction(
            key: const ValueKey('studio-roll-pitch-down'),
            label: '−1 Oct',
            tooltip: 'Shift pitch range down one octave',
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(pianoRollProvider.notifier).shiftPitchRange(-12);
            },
          ),
          _PitchTextAction(
            key: const ValueKey('studio-roll-pitch-up'),
            label: '+1 Oct',
            tooltip: 'Shift pitch range up one octave',
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(pianoRollProvider.notifier).shiftPitchRange(12);
            },
          ),
          _PitchTextAction(
            key: const ValueKey('studio-roll-pitch-clear'),
            label: 'Clear',
            tooltip: 'Reset pitch range to C3–C6',
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(pianoRollProvider.notifier).setPitchRange(48, 84);
            },
          ),
          if (trailing.isNotEmpty) const SizedBox(width: 8),
          ...trailing,
        ];
        final row = allowWrap
            ? Wrap(
                spacing: 4,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: children,
              )
            : Row(spacing: 4, children: children);
        return Padding(
          key: const ValueKey('studio-roll-tools'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: allowWrap
              ? row
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: row,
                ),
        );
      },
    );
  }
}

class _PitchTextAction extends StatelessWidget {
  const _PitchTextAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: p.textSecondary,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _StudioAction extends StatelessWidget {
  const _StudioAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.showLabel = true,
    this.compact = false,
    this.stacked = false,
    this.compactLabel,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool showLabel;
  final bool compact;
  final bool stacked;
  final String? compactLabel;

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    final style = TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: selected ? p.onAccent : p.textSecondary,
      backgroundColor: selected ? p.sky : Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10),
      textStyle: TextStyle(fontSize: compact ? 12 : 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Padding(
      padding: EdgeInsets.only(right: compact ? 0 : 4),
      child: Tooltip(
        message: label,
        child: Semantics(
          label: showLabel ? null : label,
          selected: selected,
          child: TextButton(
            onPressed: onTap,
            style: style,
            child: stacked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18),
                      const SizedBox(height: 2),
                      Text(
                        compactLabel ?? label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18),
                      if (showLabel) ...[
                        SizedBox(width: compact ? 4 : 8),
                        Flexible(
                          child: Text(
                            compact ? compactLabel ?? label : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _StudioInspector extends ConsumerWidget {
  const _StudioInspector({
    required this.state,
    required this.tab,
    required this.expanded,
    required this.onTab,
    required this.onToggle,
  });
  final PianoRollState state;
  final int tab;
  final bool expanded;
  final ValueChanged<int> onTab;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = StudioPalette.of(context);
    return DecoratedBox(
      key: const ValueKey('studio-roll-inspector'),
      decoration: BoxDecoration(
        color: p.dialogBg,
        border: Border.all(color: p.glassBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 100) {
            return Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                tooltip: 'Expand inspector',
                onPressed: onToggle,
                icon: const Icon(Icons.tune_rounded),
              ),
            );
          }
          return Column(
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (i, label) in [
                              'Stack Builder',
                              'Selection',
                            ].indexed)
                              TextButton(
                                key: ValueKey('studio-inspector-$i'),
                                onPressed: () => onTab(i),
                                style: TextButton.styleFrom(
                                  foregroundColor: tab == i
                                      ? p.sky
                                      : p.textSecondary,
                                  minimumSize: const Size(44, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  shape: const RoundedRectangleBorder(),
                                  textStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: tab == i
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: tab == i
                                            ? p.sky
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(label),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: expanded
                          ? 'Collapse inspector'
                          : 'Expand inspector',
                      onPressed: onToggle,
                      icon: Icon(
                        expanded ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                  ],
                ),
              ),
              if (expanded) ...[
                Divider(height: 1, color: p.glassBorder),
                Expanded(
                  child: IndexedStack(
                    index: tab.clamp(0, 1),
                    children: [
                      const PianoRollStackBuilder(),
                      SingleChildScrollView(
                        key: const ValueKey('studio-roll-selection'),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SelectionStatus(state: state),
                            Text(
                              state.selectedColumnTick == null
                                  ? 'Tap the ruler to choose a time column. Use Select to choose notes.'
                                  : 'Column ${transport.tickToBarBeatDisplay(state.selectedColumnTick, state.config.timeSignature)}',
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                _StudioAction(
                                  label: 'Select column',
                                  icon: Icons.select_all_rounded,
                                  onTap: state.selectedColumnTick == null
                                      ? null
                                      : () => ref
                                            .read(pianoRollProvider.notifier)
                                            .selectNotesAtTick(
                                              state.selectedColumnTick!,
                                            ),
                                ),
                                _StudioAction(
                                  label: 'Clear selection',
                                  icon: Icons.deselect_rounded,
                                  onTap: state.selectedNoteIds.isEmpty
                                      ? null
                                      : ref
                                            .read(pianoRollProvider.notifier)
                                            .clearSelection,
                                ),
                                _StudioAction(
                                  label: 'Delete selection',
                                  icon: Icons.delete_outline_rounded,
                                  onTap: state.selectedNoteIds.isEmpty
                                      ? null
                                      : ref
                                            .read(pianoRollProvider.notifier)
                                            .deleteSelectedNotes,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const PianoRollDetectionPanel(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
