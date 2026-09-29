library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/harmony_lane_instrument.dart';
import '../models/project_config.dart';
import '../models/save_system.dart';
import '../schema/rules/save_system_rules.dart';
import '../store/save_system_store.dart';
import '../store/settings_store.dart';
import '../store/songwriter_store.dart';
import '../theme/muzician_theme.dart';
import 'core/muzician_dialog.dart';
import '../utils/note_utils.dart';
import 'project_config_sheet.dart';

/// Bottom-sheet project picker.
///
/// Sections:
///   - PROJECTS (with "+ New project" inline)
///   - SPARE (Dump tile, or "Use Dump" if missing) — hidden when allowDump=false
///   - EDIT CONFIG row when a project is currently active
class ProjectPickerSheet extends ConsumerWidget {
  final bool allowDump;
  const ProjectPickerSheet({super.key, this.allowDump = true});

  static Future<void> show(BuildContext context, {bool allowDump = true}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProjectPickerSheet(allowDump: allowDump),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsListProvider);
    final dump = ref.watch(dumpFolderProvider);
    final selectedId = ref.watch(
      saveSystemProvider.select((s) => s.selectedProjectId),
    );
    final activeProjectFolder = selectedId == null
        ? null
        : ref
              .read(saveSystemProvider)
              .folders
              .where(
                (f) => f.id == selectedId && f.kind == SaveFolderKind.project,
              )
              .firstOrNull;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141826),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0x33FFFFFF), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DragHandle(),
              const SizedBox(height: 8),
              _SectionHeader(label: 'PROJECTS'),
              const SizedBox(height: 8),
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No projects yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MuzicianTheme.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ProjectTile(
                    folder: p,
                    isActive: p.id == selectedId,
                    onTap: () {
                      ref.read(saveSystemProvider.notifier).selectProject(p.id);
                      Navigator.of(context).pop();
                    },
                    onDelete: () => _confirmDeleteProject(context, ref, p),
                  ),
                ),
              const SizedBox(height: 4),
              _PrimaryAction(
                icon: Icons.add,
                label: 'New project',
                accent: MuzicianTheme.sky,
                onTap: () async {
                  final name = await _promptName(context, title: 'New project');
                  if (name == null || name.isEmpty || !context.mounted) return;
                  var instrument = ref
                      .read(settingsProvider)
                      .defaultNewProjectHarmonyInstrument;
                  if (instrument == null) {
                    instrument = await _promptHarmonyInstrument(context);
                    if (instrument == null || !context.mounted) return;
                    await ref
                        .read(settingsProvider.notifier)
                        .setDefaultNewProjectHarmonyInstrument(instrument);
                  }
                  final id = ref
                      .read(saveSystemProvider.notifier)
                      .createProject(
                        name,
                        ProjectConfig(defaultHarmonyInstrument: instrument),
                      );
                  if (id != null) {
                    ref.read(saveSystemProvider.notifier).selectProject(id);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              if (activeProjectFolder != null) ...[
                const SizedBox(height: 6),
                _PrimaryAction(
                  icon: Icons.tune,
                  label: 'Edit project config',
                  accent: MuzicianTheme.violet,
                  onTap: () {
                    Navigator.of(context).pop();
                    ProjectConfigSheet.show(context, activeProjectFolder.id);
                  },
                ),
              ],
              if (allowDump) ...[
                const SizedBox(height: 14),
                _SectionHeader(label: 'SPARE'),
                const SizedBox(height: 8),
                if (dump != null)
                  _ProjectTile(
                    folder: dump,
                    isActive: dump.id == selectedId,
                    onTap: () {
                      ref
                          .read(saveSystemProvider.notifier)
                          .selectProject(dump.id);
                      Navigator.of(context).pop();
                    },
                  )
                else
                  _PrimaryAction(
                    icon: Icons.archive_outlined,
                    label: 'Use Dump',
                    accent: MuzicianTheme.textSecondary,
                    onTap: () {
                      final id = ref
                          .read(saveSystemProvider.notifier)
                          .ensureDumpFolder();
                      ref.read(saveSystemProvider.notifier).selectProject(id);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs the Writer-only project creation flow without changing the behavior of
/// project creation from the other instrument screens.
Future<WriterProjectCreationResult?> showWriterProjectCreationFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final details = await showDialog<_WriterProjectDetails>(
    context: context,
    builder: (_) => const _WriterProjectDetailsDialog(),
  );
  if (details == null || !context.mounted) return null;

  final notifier = ref.read(songwriterProvider.notifier);
  var result = await notifier.createSaveProject(
    name: details.name,
    defaultHarmonyInstrument: details.instrument,
    disposition: null,
  );
  if (!context.mounted) return result;
  if (result.status == WriterProjectCreationStatus.dispositionRequired) {
    final disposition = await showDialog<WriterProjectCreationDisposition>(
      context: context,
      builder: (_) => const _WriterProjectDispositionDialog(),
    );
    if (!context.mounted) return result;
    result = await notifier.createSaveProject(
      name: details.name,
      defaultHarmonyInstrument: details.instrument,
      disposition: disposition ?? WriterProjectCreationDisposition.cancel,
    );
  }
  if (!context.mounted ||
      result.succeeded ||
      result.status == WriterProjectCreationStatus.cancelled) {
    return result;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => MuzicianDialog(
      title: 'Could not create Writer project',
      content: Text(_writerProjectCreationError(result.status)),
      actions: [
        MuzicianDialogButton(
          'OK',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
  return result;
}

String _writerProjectCreationError(
  WriterProjectCreationStatus status,
) => switch (status) {
  WriterProjectCreationStatus.created => '',
  WriterProjectCreationStatus.cancelled => 'Creation was cancelled.',
  WriterProjectCreationStatus.dispositionRequired =>
    'Choose what to do with the current Writer session.',
  WriterProjectCreationStatus.invalidName =>
    'Enter a project name with 1 to 60 characters.',
  WriterProjectCreationStatus.noSelectedProject =>
    'Select a Save System project before creating a Writer project.',
  WriterProjectCreationStatus.busy =>
    'Another project change is in progress. Try again.',
  WriterProjectCreationStatus.storageFailure =>
    'The project could not be saved. Your current Writer project remains open.',
  WriterProjectCreationStatus.recoveryRequired =>
    'Writer save recovery is required before another project can be created.',
};

class _WriterProjectDetails {
  const _WriterProjectDetails({required this.name, required this.instrument});

  final String name;
  final HarmonyLaneInstrument instrument;
}

class _WriterProjectDetailsDialog extends StatefulWidget {
  const _WriterProjectDetailsDialog();

  @override
  State<_WriterProjectDetailsDialog> createState() =>
      _WriterProjectDetailsDialogState();
}

class _WriterProjectDetailsDialogState
    extends State<_WriterProjectDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  HarmonyLaneInstrument? _instrument;
  bool _showInstrumentError = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final validName = _formKey.currentState?.validate() ?? false;
    if (_instrument == null) {
      setState(() => _showInstrumentError = true);
    }
    if (!validName || _instrument == null) return;
    Navigator.of(context).pop(
      _WriterProjectDetails(
        name: _nameController.text.trim(),
        instrument: _instrument!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return MuzicianDialog(
      title: 'New Writer project',
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('writerProjectNameField'),
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: MuzicianTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Project name',
                    hintText: 'Name this project',
                  ),
                  validator: (value) => isValidFolderName(value ?? '')
                      ? null
                      : 'Enter a name with 1 to 60 characters.',
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Starting Harmony instrument',
                  style: TextStyle(
                    color: MuzicianTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                RadioGroup<HarmonyLaneInstrument>(
                  groupValue: _instrument,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _instrument = value;
                      _showInstrumentError = false;
                    });
                  },
                  child: Column(
                    children: [
                      for (final instrument in HarmonyLaneInstrument.values)
                        RadioListTile<HarmonyLaneInstrument>(
                          key: Key(
                            'writerProjectInstrument_${instrument.name}',
                          ),
                          value: instrument,
                          title: Text(
                            instrument == HarmonyLaneInstrument.fretboard
                                ? 'Fretboard'
                                : 'Piano',
                          ),
                          secondary: Icon(
                            instrument == HarmonyLaneInstrument.fretboard
                                ? Icons.music_note
                                : Icons.piano,
                            color: MuzicianTheme.sky,
                          ),
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.standard,
                        ),
                    ],
                  ),
                ),
                if (_showInstrumentError)
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 2),
                    child: Text(
                      'Choose Piano or Fretboard to continue.',
                      style: TextStyle(color: MuzicianTheme.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          buttonKey: const Key('writerProjectDetailsCancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        MuzicianDialogButton(
          'Continue',
          buttonKey: const Key('writerProjectDetailsContinue'),
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _WriterProjectDispositionDialog extends StatelessWidget {
  const _WriterProjectDispositionDialog();

  @override
  Widget build(BuildContext context) => MuzicianDialog(
    title: 'Changes in this Writer session',
    content: const Text(
      'Choose what to do before opening the new project. Keep saves this '
      'Writer session. Discard restores its active Writer Save, if available, '
      'or clears the session. Cancel stays in the current project.',
    ),
    actions: [
      MuzicianDialogButton(
        'Cancel',
        buttonKey: const Key('writerProjectDispositionCancel'),
        onPressed: () =>
            Navigator.of(context).pop(WriterProjectCreationDisposition.cancel),
      ),
      MuzicianDialogButton(
        'Discard',
        buttonKey: const Key('writerProjectDispositionDiscard'),
        emphasis: MuzicianDialogEmphasis.destructive,
        onPressed: () =>
            Navigator.of(context).pop(WriterProjectCreationDisposition.discard),
      ),
      MuzicianDialogButton(
        'Keep',
        buttonKey: const Key('writerProjectDispositionKeep'),
        emphasis: MuzicianDialogEmphasis.primary,
        onPressed: () =>
            Navigator.of(context).pop(WriterProjectCreationDisposition.keep),
      ),
    ],
  );
}

Future<HarmonyLaneInstrument?> _promptHarmonyInstrument(
  BuildContext context,
) => showModalBottomSheet<HarmonyLaneInstrument>(
  context: context,
  backgroundColor: const Color(0xFF141826),
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose your first instrument',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'New sections in this project will start with this Harmony instrument.',
            style: TextStyle(color: MuzicianTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          for (final instrument in HarmonyLaneInstrument.values)
            ListTile(
              leading: Icon(
                instrument == HarmonyLaneInstrument.fretboard
                    ? Icons.music_note
                    : Icons.piano,
                color: MuzicianTheme.sky,
              ),
              title: Text(
                instrument == HarmonyLaneInstrument.fretboard
                    ? 'Fretboard'
                    : 'Piano',
              ),
              onTap: () => Navigator.of(context).pop(instrument),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  ),
);

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: MuzicianTheme.textDim,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: MuzicianTheme.textDim,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final SaveFolder folder;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _ProjectTile({
    required this.folder,
    required this.isActive,
    required this.onTap,
    this.onDelete,
  });

  String? _subtitle() {
    final cfg = folder.projectConfig;
    if (cfg == null) return null;
    final parts = <String>[];
    if (cfg.keyRootPc != null) {
      parts.add(
        '${chromaticNotes[cfg.keyRootPc!]} ${cfg.keyScaleName ?? ""}'.trim(),
      );
    }
    parts.add('${cfg.tempo} bpm');
    parts.add('${cfg.beatsPerBar}/${cfg.beatUnit}');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isDump = folder.kind == SaveFolderKind.dump;
    final accent = isDump ? MuzicianTheme.textSecondary : MuzicianTheme.emerald;
    final subtitle = _subtitle();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: isActive
                  ? accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.08),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isDump ? Icons.archive_outlined : Icons.music_note,
                  color: accent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MuzicianTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MuzicianTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'active',
                    style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              if (!isDump && onDelete != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Delete project',
                  icon: Icon(
                    Icons.delete_outline,
                    color: MuzicianTheme.red.withValues(alpha: 0.85),
                  ),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteProject(
  BuildContext context,
  WidgetRef ref,
  SaveFolder project,
) async {
  final state = ref.read(saveSystemProvider);
  final saves = getSavesInSubtree(state.folders, state.saves, project.id);
  final folderIds = getSubtreeFolderIds(state.folders, project.id);
  final folderCount = folderIds.length - 1;
  final body = saves.isEmpty
      ? 'Delete "${project.name}"? It has no saves.'
      : 'Delete "${project.name}"?\n\n'
            'This will permanently remove '
            '${saves.length} save${saves.length == 1 ? '' : 's'}'
            '${folderCount > 0 ? ' and $folderCount subfolder${folderCount == 1 ? '' : 's'}' : ''}.\n\n'
            'This cannot be undone.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => MuzicianDialog(
      title: 'Delete project?',
      content: Text(body),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        MuzicianDialogButton(
          'Delete',
          emphasis: MuzicianDialogEmphasis.destructive,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(saveSystemProvider.notifier).deleteProject(project.id);
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            border: Border.all(
              color: accent.withValues(alpha: 0.40),
              width: 0.6,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
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

Future<String?> _promptName(
  BuildContext context, {
  required String title,
}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => MuzicianDialog(
      title: title,
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: MuzicianTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Project name…',
          hintStyle: TextStyle(color: MuzicianTheme.textMuted),
        ),
        onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
      ),
      actions: [
        MuzicianDialogButton('Cancel', onPressed: () => Navigator.pop(ctx)),
        MuzicianDialogButton(
          'OK',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
        ),
      ],
    ),
  );
}
