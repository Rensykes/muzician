import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import '../../store/settings_store.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../store/writer_save_binding_store.dart';
import '../../ui/project_picker_sheet.dart';
import '../../utils/note_utils.dart';
import '../_mockup_shell.dart';

class SongwriterHeader extends ConsumerWidget {
  const SongwriterHeader({
    super.key,
    this.onOpenSaveLoad,
    this.onOpenStructure,
    this.onStartTour,
    this.onSave,
  });

  final VoidCallback? onOpenSaveLoad;
  final VoidCallback? onOpenStructure;
  final VoidCallback? onStartTour;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(songwriterProvider);
    final config = project.config;
    final dirty = ref.watch(writerDirtyProvider);
    final keyLabel = config.keyRoot == null
        ? 'No key'
        : '${chromaticNotes[config.keyRoot!]} ${config.keyScaleName ?? ''}'
              .trim();
    // Landscape phones are height-starved: drop the title row and reach the
    // overflow menu from a trailing button on the config strip instead.
    final compact = MediaQuery.sizeOf(context).height < 500;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        if (!compact)
          SizedBox(
            height: 52,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 420;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 12 : 20,
                    0,
                    narrow ? 8 : 12,
                    0,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showOverflowMenu(context, ref),
                        child: const Text(
                          'Writer',
                          style: TextStyle(
                            color: MuzicianTheme.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      SizedBox(width: narrow ? 8 : 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _editProjectName(
                            context,
                            ref,
                            ref.read(songwriterProvider).name,
                          ),
                          child: Text(
                            project.name,
                            style: const TextStyle(
                              color: MuzicianTheme.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (dirty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Semantics(
                            label: 'Unsaved changes',
                            child: Container(
                              key: const Key('writerUnsavedBadge'),
                              child: narrow
                                  ? const Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: MuzicianTheme.orange,
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: MuzicianTheme.orange,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Unsaved',
                                          style: TextStyle(
                                            color: MuzicianTheme.orange,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      if (onSave != null)
                        IconBtn(
                          key: const Key('writerSaveButton'),
                          icon: Icons.save_rounded,
                          color: dirty
                              ? MuzicianTheme.orange
                              : MuzicianTheme.textDim,
                          onTap: onSave!,
                        ),
                      if (onStartTour != null)
                        IconBtn(
                          key: const Key('writerHelpButton'),
                          icon: Icons.help_outline_rounded,
                          onTap: onStartTour!,
                        ),
                      IconBtn(
                        icon: Icons.more_vert,
                        onTap: () => _showOverflowMenu(context, ref),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (!compact) const SizedBox(height: 4),
        _WriterConfigStrip(
          keyLabel: keyLabel,
          tempo: config.tempo,
          onKeyTap: () => _editKey(context, ref),
          onTempoTap: () => _editTempo(context, ref),
          onNewProject: () async {
            await showWriterProjectCreationFlow(context, ref);
          },
          onOverflow: compact ? () => _showOverflowMenu(context, ref) : null,
          onHelp: compact ? onStartTour : null,
        ),
      ],
    );
  }

  void _showOverflowMenu(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    showWidgetSheet(
      context: context,
      title: 'Writer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MuzicianTheme.sky.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MuzicianTheme.sky.withValues(alpha: 0.2),
              ),
            ),
            child: const Text(
              'Sketch sections with chords and lyrics. Send a Fretboard or Piano selection to place it in a Writer bar.',
              style: TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.undo_rounded,
            label: 'Undo',
            enabled: notifier.canUndo,
            keyboardAccessible: true,
            onTap: () {
              Navigator.pop(context);
              notifier.undo();
            },
          ),
          _MenuTile(
            icon: Icons.redo_rounded,
            label: 'Redo',
            enabled: notifier.canRedo,
            keyboardAccessible: true,
            onTap: () {
              Navigator.pop(context);
              notifier.redo();
            },
          ),
          _MenuTile(
            icon: Icons.save_rounded,
            label: 'Save',
            onTap: () {
              Navigator.pop(context);
              onSave?.call();
            },
          ),
          _MenuTile(
            icon: Icons.folder_open_rounded,
            label: 'Browse saves',
            onTap: () {
              Navigator.pop(context);
              onOpenSaveLoad?.call();
            },
          ),
          _MenuTile(
            icon: Icons.account_tree_rounded,
            label: 'Edit structure',
            onTap: () {
              Navigator.pop(context);
              onOpenStructure?.call();
            },
          ),
          _MenuTile(
            icon: Icons.edit_rounded,
            label: 'Rename project',
            onTap: () {
              Navigator.pop(context);
              _editProjectName(context, ref, ref.read(songwriterProvider).name);
            },
          ),
        ],
      ),
    );
  }

  void _editTempo(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    final current = ref.read(songwriterProvider).config.tempo;
    showWidgetSheet(
      context: context,
      title: 'Tempo',
      child: _TempoSheet(initial: current, onChanged: notifier.setTempo),
    );
  }

  void _editKey(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    showWidgetSheet(
      context: context,
      title: 'Key',
      child: _KeySheet(
        onPick: (root, scale) => notifier.setKey(root, scale),
        onClear: () => notifier.setKey(null, null),
      ),
    );
  }
}

class _WriterConfigStrip extends ConsumerWidget {
  const _WriterConfigStrip({
    required this.keyLabel,
    required this.tempo,
    required this.onKeyTap,
    required this.onTempoTap,
    required this.onNewProject,
    this.onOverflow,
    this.onHelp,
  });
  final String keyLabel;
  final int tempo;
  final VoidCallback onKeyTap;
  final VoidCallback onTempoTap;
  final VoidCallback onNewProject;

  /// Compact (landscape) mode: the title row is hidden, so the strip hosts
  /// the overflow-menu button.
  final VoidCallback? onOverflow;

  /// Compact mode: the strip also hosts the coach-tour help button.
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      songwriterPlaybackProvider.select(
        (s) => s.status == SongwriterPlaybackStatus.playing,
      ),
    );
    final metronomeOn = ref.watch(
      settingsProvider.select((s) => s.metronomeEnabled),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: MuzicianTheme.glassBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        child: Row(
          children: [
            Flexible(
              child: _ConfigReadout(
                label: 'KEY',
                value: keyLabel,
                onTap: onKeyTap,
              ),
            ),
            _stripDivider(),
            _ConfigReadout(label: 'BPM', value: '$tempo', onTap: onTempoTap),
            _stripDivider(),
            IconBtn(
              key: const Key('songwriterPlay'),
              icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              onTap: () {
                final t = ref.read(songwriterPlaybackProvider.notifier);
                if (playing) {
                  t.stopPlayback();
                } else {
                  t.startPlayback(
                    startTick: ref.read(songwriterStartTickProvider),
                  );
                }
              },
            ),
            IconBtn(
              icon: metronomeOn ? Icons.music_note : Icons.music_off,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .setMetronomeEnabled(!metronomeOn),
            ),
            _stripDivider(),
            Tooltip(
              message: 'Create Writer project',
              child: Semantics(
                button: true,
                label: 'Create Writer project',
                excludeSemantics: true,
                child: IconBtn(
                  key: const Key('writerNewProjectButton'),
                  icon: Icons.add_box_outlined,
                  onTap: onNewProject,
                ),
              ),
            ),
            if (onHelp != null)
              IconBtn(
                key: const Key('writerHelpButton'),
                icon: Icons.help_outline_rounded,
                onTap: onHelp!,
              ),
            if (onOverflow != null)
              IconBtn(icon: Icons.more_vert, onTap: onOverflow!),
          ],
        ),
      ),
    );
  }

  static Widget _stripDivider() =>
      Container(width: 1, height: 24, color: MuzicianTheme.glassBorder);
}

class _ConfigReadout extends StatelessWidget {
  const _ConfigReadout({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _editProjectName(BuildContext context, WidgetRef ref, String current) {
  final controller = TextEditingController(text: current);
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => MuzicianDialog(
      title: 'Project name',
      content: TextField(
        key: const Key('projectNameField'),
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: InputDecoration(
          labelText: 'Name',
          labelStyle: const TextStyle(color: MuzicianTheme.textMuted),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: MuzicianTheme.glassBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: MuzicianTheme.sky),
          ),
        ),
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.pop(dialogCtx),
        ),
        MuzicianDialogButton(
          'Save',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () {
            ref
                .read(songwriterProvider.notifier)
                .setProjectName(controller.text);
            Navigator.pop(dialogCtx);
          },
        ),
      ],
    ),
  );
}

class _TempoSheet extends StatefulWidget {
  const _TempoSheet({required this.initial, required this.onChanged});
  final int initial;
  final ValueChanged<int> onChanged;
  @override
  State<_TempoSheet> createState() => _TempoSheetState();
}

class _TempoSheetState extends State<_TempoSheet> {
  late double _bpm = widget.initial.toDouble().clamp(40, 240).toDouble();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_bpm.round()} BPM'),
          Slider(
            min: 40,
            max: 240,
            value: _bpm.clamp(40, 240).toDouble(),
            onChanged: (v) => setState(() => _bpm = v),
            onChangeEnd: (v) => widget.onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

class _KeySheet extends StatelessWidget {
  const _KeySheet({required this.onPick, required this.onClear});
  final void Function(int root, String scale) onPick;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    const scales = ['major', 'minor'];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final scale in scales) ...[
            Text(
              scale.isEmpty
                  ? scale
                  : scale[0].toUpperCase() + scale.substring(1),
              style: const TextStyle(
                color: MuzicianTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var pc = 0; pc < 12; pc++)
                  _GlassPill(
                    key: ValueKey('keyPill_${scale}_$pc'),
                    label: chromaticNotes[pc],
                    onTap: () {
                      onPick(pc, scale);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _GlassTextButton(
            label: 'Clear key',
            onTap: () {
              onClear();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MuzicianTheme.glassBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GlassTextButton extends StatelessWidget {
  const _GlassTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: MuzicianTheme.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MenuTile extends StatefulWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.keyboardAccessible = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool keyboardAccessible;

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _showFocusHighlight = false;

  @override
  Widget build(BuildContext context) {
    final tile = GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: Container(
        key: widget.keyboardAccessible
            ? Key('writerMenuTile_${widget.label.toLowerCase()}')
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _showFocusHighlight
              ? MuzicianTheme.sky.withValues(alpha: 0.08)
              : null,
          border: _showFocusHighlight
              ? Border.all(color: MuzicianTheme.sky, width: 1.5)
              : Border(bottom: BorderSide(color: MuzicianTheme.glassBorder)),
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 20,
              color: widget.enabled
                  ? MuzicianTheme.textSecondary
                  : MuzicianTheme.textDim,
            ),
            const SizedBox(width: 14),
            Text(
              widget.label,
              style: TextStyle(
                color: widget.enabled
                    ? MuzicianTheme.textPrimary
                    : MuzicianTheme.textDim,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.keyboardAccessible) return tile;

    return FocusableActionDetector(
      enabled: widget.enabled,
      onShowFocusHighlight: (show) {
        if (_showFocusHighlight != show) {
          setState(() => _showFocusHighlight = show);
        }
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        enabled: widget.enabled,
        focusable: widget.enabled,
        focused: _showFocusHighlight,
        label: widget.label,
        onTap: widget.enabled ? widget.onTap : null,
        child: tile,
      ),
    );
  }
}
