/// Modal bottom sheet for editing a section's lyrics blob.
///
/// Returns the new lyrics string (trimmed of trailing whitespace) on save,
/// or `null` if the user cleared the text or dismissed the sheet.
library;

import 'package:flutter/material.dart';

import '../_mockup_shell.dart';
import '../../theme/muzician_theme.dart';

Future<String?> showSectionLyricsSheet({
  required BuildContext context,
  String? initial,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  String? result;
  await showWidgetSheet(
    context: context,
    title: 'Lyrics',
    child: _SectionLyricsBody(
      controller: controller,
      onSave: (text) {
        result = text.trimRight().isEmpty ? null : text.trimRight();
        Navigator.of(context).pop();
      },
      onClear: () {
        result = null;
        Navigator.of(context).pop();
      },
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 200));
  controller.dispose();
  return result;
}

class _SectionLyricsBody extends StatelessWidget {
  const _SectionLyricsBody({
    required this.controller,
    required this.onSave,
    required this.onClear,
  });

  final TextEditingController controller;
  final void Function(String text) onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('sectionLyricsField'),
            controller: controller,
            minLines: 4,
            maxLines: 10,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Type lyrics for this section…',
              hintStyle: const TextStyle(color: MuzicianTheme.textMuted),
              filled: true,
              fillColor: MuzicianTheme.glassBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MuzicianTheme.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: MuzicianTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: MuzicianTheme.sky),
              ),
            ),
            style: const TextStyle(
              color: MuzicianTheme.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                key: const Key('sectionLyricsClear'),
                onPressed: onClear,
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('sectionLyricsSave'),
                onPressed: () => onSave(controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
