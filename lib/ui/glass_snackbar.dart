/// Glass-styled snackbar using [AwesomeSnackbarContent] for content layout and
/// the app's glassmorphism theme for the container (border, rounded corners).
library;

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import '../theme/muzician_theme.dart';

/// Shows a floating snackbar with the app's glass styling and
/// [AwesomeSnackbarContent] for icon / title / message layout.
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
        side: BorderSide(color: MuzicianTheme.glassBorder),
      ),
      duration: duration,
      dismissDirection: DismissDirection.horizontal,
      action: actionLabel != null && onAction != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: MuzicianTheme.sky,
              onPressed: onAction,
            )
          : null,
      content: AwesomeSnackbarContent(
        title: title,
        message: message,
        contentType: contentType,
      ),
    ),
  );
}
