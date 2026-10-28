import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../store/persisted_data_recovery_store.dart';
import '../../theme/studio_theme.dart';
import '../../ui/core/muzician_dialog.dart';
import 'recovery_export.dart';

class DataRecoveryPanel extends ConsumerWidget {
  const DataRecoveryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = StudioPalette.of(context);
    final backups = ref.watch(dataRecoveryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.restore_page_outlined,
                    color: palette.sky,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Data Recovery',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Preserved original data stays here until you delete that backup.',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              if (backups.isEmpty)
                Text(
                  'No preserved data.',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                )
              else
                for (final backup in backups)
                  _RecoveryBackupEntry(
                    key: ValueKey(backup.storageKey),
                    backup: backup,
                  ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: palette.glassBorder.withValues(alpha: 0.55),
          indent: 24,
          endIndent: 24,
        ),
      ],
    );
  }
}

class _RecoveryBackupEntry extends ConsumerWidget {
  const _RecoveryBackupEntry({super.key, required this.backup});

  final DataRecoveryBackup backup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = StudioPalette.of(context);
    final exportAnchorKey = GlobalKey();
    return ExpansionTile(
      key: Key('recoveryEntry_${backup.storageKey}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        backup.label,
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
      ),
      subtitle: Text(
        'Original key: ${backup.sourceKey}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textMuted, fontSize: 11),
      ),
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 180),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: palette.isStudio
                  ? palette.glassBorder
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              backup.raw,
              key: Key('recoveryRaw_${backup.storageKey}'),
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: Key('recoveryCopy_${backup.storageKey}'),
              onPressed: () => _copy(context),
              icon: Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy'),
            ),
            Align(
              key: exportAnchorKey,
              widthFactor: 1,
              heightFactor: 1,
              child: TextButton.icon(
                key: Key('recoveryExport_${backup.storageKey}'),
                onPressed: () => _export(context, exportAnchorKey),
                icon: Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export'),
              ),
            ),
            TextButton.icon(
              key: Key('recoveryDelete_${backup.storageKey}'),
              onPressed: () => _confirmDelete(context, ref),
              icon: Icon(Icons.delete_outline, size: 18, color: palette.red),
              label: Text(
                'Delete backup',
                style: TextStyle(color: palette.red),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: backup.raw));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Original recovery text copied.')),
    );
  }

  Future<void> _export(BuildContext context, GlobalKey anchorKey) async {
    try {
      final renderObject = anchorKey.currentContext?.findRenderObject();
      final origin = renderObject is RenderBox && renderObject.hasSize
          ? renderObject.localToGlobal(Offset.zero) & renderObject.size
          : null;
      final outcome = await exportRecoveryBackup(
        backup,
        sharePositionOrigin: origin,
      );
      if (!context.mounted || outcome == RecoveryExportOutcome.cancelled) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(recoveryExportFeedback(outcome))));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export this recovery backup.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: StudioRouteTheme.builder(
        context,
        (dialogContext) => MuzicianDialog(
          title: 'Delete recovery backup?',
          content: const Text(
            'This removes only this preserved copy. The active project and other recovery entries stay as they are.',
          ),
          actions: [
            MuzicianDialogButton(
              'Cancel',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            MuzicianDialogButton(
              'Delete backup',
              emphasis: MuzicianDialogEmphasis.destructive,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(dataRecoveryProvider.notifier)
          .deleteBackup(backup.storageKey);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this backup.')),
      );
    }
  }
}
