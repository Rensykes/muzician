import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../store/songwriter_store.dart';
import '../../utils/note_utils.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text(
            'Songwriter',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const Spacer(),
          _Chip(label: keyLabel, onTap: () => _editKey(context, ref)),
          const SizedBox(width: 8),
          _Chip(
            label: '${config.tempo} BPM',
            onTap: () => _editTempo(context, ref),
          ),
          IconButton(
            tooltip: 'New project',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => _confirmNew(context, notifier),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'saveload') onOpenSaveLoad?.call();
              if (v == 'structure') onOpenStructure?.call();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'saveload', child: Text('Save / Load')),
              PopupMenuItem(value: 'structure', child: Text('Edit structure')),
            ],
          ),
        ],
      ),
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
    showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          _TempoSheet(initial: current, onChanged: notifier.setTempo),
    );
  }

  void _editKey(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(songwriterProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _KeySheet(
        onPick: (root, scale) => notifier.setKey(root, scale),
        onClear: () => notifier.setKey(null, null),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      ActionChip(label: Text(label), onPressed: onTap);
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
