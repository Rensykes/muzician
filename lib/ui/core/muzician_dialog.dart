/// Shared modal dialog primitives for Muzician.
///
/// [MuzicianDialog] is a thin wrapper over [AlertDialog] that inherits its
/// surface, shape and text styles from the current [DialogThemeData], so
/// callers only supply a title, content and actions and get a consistent scoped
/// dialog. [MuzicianDialogButton] and [MuzicianDialogCheckbox] cover the action
/// and "don't ask again" rows that previously diverged across the codebase.
library;

import 'package:flutter/material.dart';
import '../../theme/studio_theme.dart';

/// Visual weight for a [MuzicianDialogButton].
enum MuzicianDialogEmphasis {
  /// Dismissive / secondary action — muted text.
  normal,

  /// The main confirming action — sky accent, bold.
  primary,

  /// A irreversible / dangerous action — red accent, bold.
  destructive,
}

/// A palette-aware modal dialog. Pulls background, border, radius and the title/content
/// text styles from the app [DialogThemeData]; supply only [title]/[content]/
/// [actions].
class MuzicianDialog extends StatelessWidget {
  /// Plain-string title, rendered with the theme's `titleTextStyle`. Mutually
  /// exclusive with [titleWidget].
  final String? title;

  /// Custom title widget when a plain string is not enough.
  final Widget? titleWidget;

  /// Body of the dialog. Plain [Text] children inherit the theme's
  /// `contentTextStyle`.
  final Widget content;

  /// Footer actions — typically [MuzicianDialogButton]s.
  final List<Widget> actions;

  const MuzicianDialog({
    super.key,
    this.title,
    this.titleWidget,
    required this.content,
    required this.actions,
  }) : assert(
         title == null || titleWidget == null,
         'Provide either title or titleWidget, not both.',
       );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: titleWidget ?? (title != null ? Text(title!) : null),
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: actions,
    );
  }
}

/// A text action button with one of the canonical Muzician emphases. Pass an
/// explicit [color] to override the emphasis colour (e.g. a caution action).
class MuzicianDialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final MuzicianDialogEmphasis emphasis;
  final Color? color;

  /// Optional key applied to the underlying [TextButton] for widget tests.
  final Key? buttonKey;

  const MuzicianDialogButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.emphasis = MuzicianDialogEmphasis.normal,
    this.color,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final (Color base, FontWeight weight) = switch (emphasis) {
      MuzicianDialogEmphasis.normal => (
        StudioPalette.of(context).textSecondary,
        FontWeight.w500,
      ),
      MuzicianDialogEmphasis.primary => (
        StudioPalette.of(context).sky,
        FontWeight.w700,
      ),
      MuzicianDialogEmphasis.destructive => (
        StudioPalette.of(context).red,
        FontWeight.w700,
      ),
    };
    final resolved = onPressed == null
        ? StudioPalette.of(context).textDim
        : (color ?? base);
    return TextButton(
      key: buttonKey,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(color: resolved, fontSize: 13, fontWeight: weight),
      ),
    );
  }
}

/// The "don't ask again" / opt-in checkbox row shared by confirmation dialogs.
class MuzicianDialogCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final Key? checkboxKey;

  const MuzicianDialogCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.checkboxKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: checkboxKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: StudioPalette.of(context).isStudio ? 44 : 0,
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: value
                    ? StudioPalette.of(context).sky.withValues(alpha: 0.2)
                    : (StudioPalette.of(context).isStudio
                          ? StudioPalette.of(context).glassBg
                          : Colors.white.withValues(alpha: 0.04)),
                border: Border.all(
                  color: value
                      ? StudioPalette.of(context).sky
                      : StudioPalette.of(context).isStudio
                      ? StudioPalette.of(context).textMuted
                      : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: value
                  ? Icon(
                      Icons.check,
                      size: 12,
                      color: StudioPalette.of(context).sky,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: StudioPalette.of(context).textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
