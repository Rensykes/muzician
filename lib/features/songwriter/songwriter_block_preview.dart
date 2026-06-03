import 'package:flutter/material.dart';
import '../../models/save_system.dart';
import '../../ui/save_card_label.dart';
import '../../ui/save_previews/save_preview_thumbnail.dart';

void showBlockPreviewSheet(BuildContext context, InstrumentSnapshot snapshot) {
  final label = saveCardLabel(snapshot);
  final icon = saveInstrumentIcon(snapshot.instrument);

  showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.text ?? snapshot.instrument,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SavePreviewThumbnail(snapshot: snapshot, width: 200, height: 120),
            if (snapshot.selectedNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final note in snapshot.selectedNotes)
                    Chip(
                      label: Text(note),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void showBrokenReferenceSheet(
  BuildContext context, {
  required VoidCallback onDelete,
  VoidCallback? onRelink,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This block references a deleted save.'),
          ),
          if (onRelink != null)
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Re-link to another save'),
              onTap: () {
                Navigator.pop(sheetCtx);
                onRelink();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete block'),
            onTap: () {
              Navigator.pop(sheetCtx);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}
