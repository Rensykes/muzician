/// Shared "outside the key" confirmation dialog used by both fretboard and piano.
library;

import 'package:flutter/material.dart';
import 'muzician_dialog.dart';

/// Carries the dialog result: whether the user confirmed and whether they want
/// to suppress future alerts.
class OutOfKeyResult {
  final bool suppress;
  const OutOfKeyResult({required this.suppress});
}

class OutOfKeyDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool showSuppressOption;
  const OutOfKeyDialog({
    super.key,
    this.title = 'Outside the key',
    this.message =
        'This note is outside the highlighted scale. Adding it will clear the scale highlight.',
    this.showSuppressOption = true,
  });

  @override
  State<OutOfKeyDialog> createState() => _OutOfKeyDialogState();
}

class _OutOfKeyDialogState extends State<OutOfKeyDialog> {
  bool _suppress = false;

  @override
  Widget build(BuildContext context) {
    return MuzicianDialog(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          if (widget.showSuppressOption) ...[
            const SizedBox(height: 16),
            MuzicianDialogCheckbox(
              value: _suppress,
              onChanged: (v) => setState(() => _suppress = v),
              label: "Don't show this again",
            ),
          ],
        ],
      ),
      actions: [
        MuzicianDialogButton(
          'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        MuzicianDialogButton(
          'Continue',
          emphasis: MuzicianDialogEmphasis.primary,
          onPressed: () =>
              Navigator.of(context).pop(OutOfKeyResult(suppress: _suppress)),
        ),
      ],
    );
  }
}
