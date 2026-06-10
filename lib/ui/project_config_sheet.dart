library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_config.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/save_system_store.dart';
import '../theme/muzician_theme.dart';
import '../utils/note_utils.dart';

/// Edit a project's global key, tempo, and time signature.
///
/// All saves under the project inherit and stay locked to this config; saving
/// here prompts a confirmation that lists how many saves will be retuned /
/// retimed, then applies the change atomically via
/// SaveSystemNotifier.applyProjectConfig(retrofit: true).
class ProjectConfigSheet extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectConfigSheet({super.key, required this.projectId});

  static Future<void> show(BuildContext context, String projectId) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => ProjectConfigSheet(projectId: projectId),
      );

  @override
  ConsumerState<ProjectConfigSheet> createState() =>
      _ProjectConfigSheetState();
}

class _ProjectConfigSheetState extends ConsumerState<ProjectConfigSheet> {
  late ProjectConfig _draft;
  late TextEditingController _tempoCtrl;

  @override
  void initState() {
    super.initState();
    final folder = ref
        .read(saveSystemProvider)
        .folders
        .firstWhere((f) => f.id == widget.projectId);
    _draft = folder.projectConfig ?? const ProjectConfig();
    _tempoCtrl = TextEditingController(text: _draft.tempo.toString());
  }

  @override
  void dispose() {
    _tempoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = ref.read(saveSystemProvider);
    final folder = state.folders.firstWhere((f) => f.id == widget.projectId);
    final current = folder.projectConfig ?? const ProjectConfig();
    final changed = current.tempo != _draft.tempo ||
        current.beatsPerBar != _draft.beatsPerBar ||
        current.beatUnit != _draft.beatUnit ||
        current.keyRootPc != _draft.keyRootPc ||
        current.keyScaleName != _draft.keyScaleName;
    if (!changed) {
      Navigator.of(context).pop();
      return;
    }
    final affected =
        getSavesInSubtree(state.folders, state.saves, widget.projectId).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141826),
        title: const Text(
          'Apply project config?',
          style: TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          affected == 0
              ? 'No saves under this project yet — settings will apply going forward.'
              : '$affected save${affected == 1 ? '' : 's'} will be retuned / retimed. Continue?',
          style: const TextStyle(color: MuzicianTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: MuzicianTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Apply',
              style: TextStyle(color: MuzicianTheme.sky),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(saveSystemProvider.notifier)
        .applyProjectConfig(widget.projectId, _draft, retrofit: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final folder = ref
        .read(saveSystemProvider)
        .folders
        .firstWhere((f) => f.id == widget.projectId);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141826),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Color(0x33FFFFFF), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MuzicianTheme.textDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                folder.name,
                style: const TextStyle(
                  color: MuzicianTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'PROJECT CONFIG',
                style: TextStyle(
                  color: MuzicianTheme.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _Section(
                label: 'KEY',
                child: _KeyPicker(
                  rootPc: _draft.keyRootPc,
                  scaleName: _draft.keyScaleName,
                  onChanged: (root, scale) => setState(() {
                    if (root == null) {
                      _draft = _draft.copyWith(clearKey: true);
                    } else {
                      _draft = _draft.copyWith(
                        keyRootPc: root,
                        keyScaleName: scale,
                      );
                    }
                  }),
                ),
              ),
              const SizedBox(height: 14),
              _Section(
                label: 'TEMPO (BPM)',
                child: TextField(
                  controller: _tempoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: const TextStyle(
                    color: MuzicianTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: MuzicianTheme.textDim),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: MuzicianTheme.sky),
                    ),
                  ),
                  onChanged: (v) => setState(() {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      _draft = _draft.copyWith(tempo: parsed);
                    }
                  }),
                ),
              ),
              const SizedBox(height: 14),
              _Section(
                label: 'TIME SIGNATURE',
                child: Row(
                  children: [
                    Expanded(
                      child: _NumberDropdown(
                        label: 'beats',
                        value: _draft.beatsPerBar,
                        options: const [2, 3, 4, 5, 6, 7, 8, 9, 12],
                        onChanged: (v) => setState(() {
                          _draft = _draft.copyWith(beatsPerBar: v);
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberDropdown(
                        label: 'unit',
                        value: _draft.beatUnit,
                        options: const [2, 4, 8, 16],
                        onChanged: (v) => setState(() {
                          _draft = _draft.copyWith(beatUnit: v);
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: 'Cancel',
                      accent: MuzicianTheme.textSecondary,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetButton(
                      label: 'Apply',
                      accent: MuzicianTheme.sky,
                      filled: true,
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: MuzicianTheme.textDim,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _KeyPicker extends StatelessWidget {
  final int? rootPc;
  final String? scaleName;
  final void Function(int? rootPc, String? scaleName) onChanged;
  const _KeyPicker({
    required this.rootPc,
    required this.scaleName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scales = scaleIntervals.keys.toList();
    final scale = scaleName ?? (scales.isNotEmpty ? scales.first : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chromaticNotes.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                final selected = rootPc == null;
                return _Pill(
                  label: '—',
                  selected: selected,
                  onTap: () => onChanged(null, null),
                );
              }
              final pc = i - 1;
              final selected = rootPc == pc;
              return _Pill(
                label: chromaticNotes[pc],
                selected: selected,
                onTap: () => onChanged(pc, scale),
              );
            },
          ),
        ),
        if (rootPc != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: scales.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final selected = scaleName == scales[i];
                return _Pill(
                  label: scales[i],
                  selected: selected,
                  onTap: () => onChanged(rootPc, scales[i]),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final accent = selected ? MuzicianTheme.sky : MuzicianTheme.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: selected ? 0.18 : 0.06),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.55 : 0.18),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberDropdown extends StatelessWidget {
  final String label;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;
  const _NumberDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.6,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: options.contains(value) ? value : options.first,
          isExpanded: true,
          dropdownColor: const Color(0xFF141826),
          iconEnabledColor: MuzicianTheme.textMuted,
          style: const TextStyle(
            color: MuzicianTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text('$o $label')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final bool filled;
  const _SheetButton({
    required this.label,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: filled
                ? accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: filled
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.10),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
