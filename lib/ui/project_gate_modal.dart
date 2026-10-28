library;

import 'package:flutter/material.dart';
import '../theme/studio_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'project_picker_sheet.dart';

class ProjectGateModal extends ConsumerWidget {
  final bool allowDump;
  final bool allowCancel;
  const ProjectGateModal({
    super.key,
    required this.allowDump,
    required this.allowCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: allowCancel,
      child: Stack(
        children: [
          ProjectPickerSheet(allowDump: allowDump),
          if (allowCancel)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> show(
    BuildContext context, {
    required bool allowDump,
    required bool allowCancel,
  }) {
    return showStudioModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: allowCancel,
      enableDrag: allowCancel,
      builder: (_) =>
          ProjectGateModal(allowDump: allowDump, allowCancel: allowCancel),
    );
  }
}
