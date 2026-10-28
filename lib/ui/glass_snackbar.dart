/// Compact palette-aware notifications, retaining legacy Song presentation.
library;

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import '../theme/studio_theme.dart';

/// Shows a scoped floating notification with an optional action.
///
/// [contentType] controls the color and icon (failure/success/warning/help).
/// [actionLabel] and [onAction] add an optional trailing action button.
void showGlassSnackbar(
  BuildContext context, {
  required String title,
  required String message,
  required ContentType contentType,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final isStudio = StudioPalette.of(context).isStudio;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: StudioPalette.of(context).glassBorder),
      ),
      duration: duration,
      dismissDirection: DismissDirection.horizontal,
      action: !isStudio && actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: StudioPalette.of(context).sky,
              onPressed: onAction,
            )
          : null,
      content: StudioRouteTheme(
        isStudio: isStudio,
        child: _SnackbarBody(
          title: title,
          message: message,
          contentType: contentType,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    ),
  );
}

class _SnackbarBody extends StatelessWidget {
  const _SnackbarBody({
    required this.title,
    required this.message,
    required this.contentType,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String message;
  final ContentType contentType;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    if (!p.isStudio) {
      return AwesomeSnackbarContent(
        title: title,
        message: message,
        contentType: contentType,
      );
    }
    final (color, icon) = contentType == ContentType.failure
        ? (p.red, Icons.error_outline)
        : contentType == ContentType.warning
        ? (p.orange, Icons.warning_amber_rounded)
        : contentType == ContentType.success
        ? (p.teal, Icons.check_circle_outline)
        : (p.sky, Icons.info_outline);
    return Material(
      color: p.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: p.textSecondary, fontSize: 13),
                  ),
                  if (actionLabel != null && onAction != null)
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        onAction!();
                      },
                      child: Text(actionLabel!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
