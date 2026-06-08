import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/muzician_theme.dart';
import '../../store/settings_store.dart';
import '../../store/songwriter_playback_store.dart';
import '../../store/songwriter_store.dart';
import '../../utils/note_utils.dart';
import '../_mockup_shell.dart';

class SongwriterHeader extends ConsumerWidget {
  const SongwriterHeader({
    super.key,
    this.onOpenSaveLoad,
    this.onOpenStructure,
  });

  final VoidCallback? onOpenSaveLoad;
  final VoidCallback? onOpenStructure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(songwriterProvider.select((p) => p.config));
    final notifier = ref.read(songwriterProvider.notifier);
    final keyLabel = config.keyRoot == null
        ? 'No key'
        : '${chromaticNotes[config.keyRoot!]} ${config.keyScaleName ?? ''}'
              .trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompactAppBar(
          title: 'Writer',
          chipLabel: ref.watch(songwriterProvider.select((p) => p.name)),
          actions: [
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(
                Icons.more_vert,
                color: MuzicianTheme.textSecondary,
                size: 22,
              ),
              onSelected: (v) {
                if (v == 'saveload') {
                  onOpenSaveLoad?.call();
                }
                if (v == 'structure') {
                  onOpenStructure?.call();
                }
                if (v == 'rename') {
                  _editProjectName(
                    context,
                    ref,
                    ref.read(songwriterProvider).name,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'saveload', child: Text('Save / Load')),
                PopupMenuItem(
                  value: 'structure',
                  child: Text('Edit structure'),
                ),
                PopupMenuItem(value: 'rename', child: Text('Rename project')),
              ],
            ),
          ],
        ),
        _WriterConfigStrip(
          keyLabel: keyLabel,
          tempo: config.tempo,
          onKeyTap: () => _editKey(context, ref),
          onTempoTap: () => _editTempo(context, ref),
          onNewProject: () => _confirmNew(context, notifier),
        ),
      ],
    );
  }

  Future<void> _confirmNew(
    BuildContext context,
    SongwriterNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New project?'),
        content: const Text('This clears the current songwriter session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('New project'),
          ),
        ],
      ),
    );
    if (ok == true) await notifier.newProject();
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
  });
  final String keyLabel;
  final int tempo;
  final VoidCallback onKeyTap;
  final VoidCallback onTempoTap;
  final VoidCallback onNewProject;

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
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: MuzicianTheme.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuzicianTheme.glassBorder),
      ),
      child: Row(
        children: [
          _ConfigReadout(label: 'KEY', value: keyLabel, onTap: onKeyTap),
          _stripDivider(),
          _ConfigReadout(label: 'BPM', value: '$tempo', onTap: onTempoTap),
          _stripDivider(),
          IconBtn(
            icon: playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            onTap: () {
              final t = ref.read(songwriterPlaybackProvider.notifier);
              playing ? t.stopPlayback() : t.startPlayback();
            },
          ),
          IconBtn(
            icon: metronomeOn ? Icons.music_note : Icons.music_off,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .setMetronomeEnabled(!metronomeOn),
          ),
          _stripDivider(),
          IconBtn(icon: Icons.add_box_outlined, onTap: onNewProject),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: MuzicianTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: MuzicianTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Project name'),
      content: TextField(
        key: const Key('projectNameField'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            ref
                .read(songwriterProvider.notifier)
                .setProjectName(controller.text);
            Navigator.pop(dialogCtx);
          },
          child: const Text('Save'),
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
            ),
            Wrap(
              spacing: 6,
              children: [
                for (var pc = 0; pc < 12; pc++)
                  ActionChip(
                    label: Text(chromaticNotes[pc]),
                    onPressed: () {
                      onPick(pc, scale);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () {
              onClear();
              Navigator.pop(context);
            },
            child: const Text('Clear key'),
          ),
        ],
      ),
    );
  }
}
