/// In-app feedback composer reached from Settings.
library;

import 'dart:async';

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/feedback_entry.dart';
import '../../store/feedback_store.dart';
import '../../theme/studio_theme.dart';
import '../../utils/feedback_diagnostics.dart';
import '../glass_snackbar.dart';

/// The full privacy copy shown inside "What gets sent".
const _whatGetsSentText =
    'Only the message you write, an optional email address, and these '
    'details are sent: app version, platform, operating system, screen and '
    'language. Your projects, lyrics and saves never leave your device. '
    'There is no analytics, no tracking and no account. Feedback is kept '
    'until it is deleted — email bytebakehouseinc@gmail.com to have it '
    'removed.';

/// A palette-aware feedback form that keeps its draft until a send succeeds.
class FeedbackSheet extends ConsumerStatefulWidget {
  const FeedbackSheet({super.key});

  /// Opens the feedback composer above the current workspace.
  static Future<void> show(BuildContext context) =>
      showStudioModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const FeedbackSheet(),
      );

  @override
  ConsumerState<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<FeedbackSheet> {
  late final TextEditingController _messageController;
  late final TextEditingController _contactController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(feedbackProvider);
    _messageController = TextEditingController(text: state.message);
    _contactController = TextEditingController(text: state.contact);
    unawaited(_attachDiagnostics());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  /// Captures the coarse device details the sheet shows and sends.
  Future<void> _attachDiagnostics() async {
    final diagnostics = await captureDiagnostics(screen: 'Settings');
    if (!mounted) return;
    await ref.read(feedbackProvider.notifier).attachDiagnostics(diagnostics);
  }

  Future<void> _send() async {
    final sent = await ref.read(feedbackProvider.notifier).send();
    if (!mounted || !sent) return;
    showGlassSnackbar(
      context,
      title: 'Thanks for the feedback',
      message: 'Your message was sent.',
      contentType: ContentType.success,
    );
    // In the app this closes the sheet; a route-less host keeps it mounted.
    if (Navigator.canPop(context)) Navigator.of(context).pop();
  }

  Future<void> _copy(FeedbackState state) async {
    await Clipboard.setData(
      ClipboardData(
        text: '${state.message}\n\n${state.diagnostics?.summary ?? ''}',
      ),
    );
    if (!mounted) return;
    showGlassSnackbar(
      context,
      title: 'Copied',
      message: 'Your message and details are on the clipboard.',
      contentType: ContentType.help,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = StudioPalette.of(context);
    final state = ref.watch(feedbackProvider);
    final notifier = ref.read(feedbackProvider.notifier);
    final sending = state.status == FeedbackStatus.sending;

    // Drafts restored before the sheet opened, and text cleared by a
    // successful send, must stay in sync with the store.
    ref.listen(feedbackProvider.select((s) => s.message), (_, message) {
      if (_messageController.text == message) return;
      _messageController.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    });
    ref.listen(feedbackProvider.select((s) => s.contact), (_, contact) {
      if (_contactController.text == contact) return;
      _contactController.value = TextEditingValue(
        text: contact,
        selection: TextSelection.collapsed(offset: contact.length),
      );
    });

    // A success can leave text typed mid-send, so the draft decides the
    // button, not the status alone.
    final String buttonKey;
    final String buttonLabel;
    final VoidCallback? onPressed;
    if (state.status == FeedbackStatus.sent && !state.hasDraft) {
      buttonKey = 'feedback_sent';
      buttonLabel = 'Sent';
      onPressed = null;
    } else if (state.hasDraft &&
        (state.status == FeedbackStatus.failed ||
            state.status == FeedbackStatus.pending)) {
      buttonKey = 'feedback_retry';
      buttonLabel = 'Retry';
      onPressed = sending ? null : _send;
    } else {
      buttonKey = 'feedback_send';
      buttonLabel = 'Send';
      onPressed = sending ? null : _send;
    }

    return Container(
      decoration: BoxDecoration(
        color: p.dialogBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: p.glassBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        // showStudioModalBottomSheet already lifts this sheet by
        // MediaQuery.viewInsets, so the scroll viewport shrinks with the
        // keyboard and every field stays reachable.
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.feedback_outlined, color: p.sky, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Send feedback',
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: Navigator.canPop(context)
                        ? () => Navigator.of(context).pop()
                        : null,
                    icon: Icon(
                      Icons.close_rounded,
                      color: p.textMuted,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'CATEGORY',
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in FeedbackCategory.values)
                    ChoiceChip(
                      key: ValueKey('feedback_category_${category.wireName}'),
                      label: Text(_categoryLabel(category)),
                      selected: state.category == category,
                      onSelected: sending
                          ? null
                          : (_) => notifier.setCategory(category),
                      showCheckmark: false,
                      backgroundColor: p.glassBg,
                      selectedColor: p.sky.withValues(alpha: 0.18),
                      side: BorderSide(
                        color: state.category == category
                            ? p.sky
                            : p.glassBorder,
                      ),
                      labelStyle: TextStyle(
                        color: state.category == category
                            ? p.sky
                            : p.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('feedback_message'),
                controller: _messageController,
                enabled: !sending,
                minLines: 3,
                maxLines: 6,
                maxLength: FeedbackEntry.maxMessageLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: p.textPrimary, fontSize: 14),
                decoration: _fieldDecoration(
                  p,
                  label: 'What happened?',
                  hint: 'Describe a bug, an idea, or something confusing.',
                ),
                onChanged: notifier.setMessage,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('feedback_contact'),
                controller: _contactController,
                enabled: !sending,
                maxLength: FeedbackEntry.maxContactLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: p.textPrimary, fontSize: 14),
                decoration: _fieldDecoration(
                  p,
                  label: "Email, if you'd like a reply (optional)",
                ),
                onChanged: notifier.setContact,
              ),
              const SizedBox(height: 4),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const ValueKey('feedback_what_is_sent'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  iconColor: p.textMuted,
                  collapsedIconColor: p.textMuted,
                  title: Text(
                    'What gets sent',
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        state.diagnostics?.summary ??
                            'Device details are captured when you send.',
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _whatGetsSentText,
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 4),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.error!,
                    key: const ValueKey('feedback_error'),
                    style: TextStyle(
                      color: state.status == FeedbackStatus.failed
                          ? p.red
                          : p.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (state.hasDraft)
                    TextButton(
                      key: const ValueKey('feedback_copy'),
                      onPressed: () => _copy(state),
                      child: Text(
                        'Copy',
                        style: TextStyle(
                          color: p.sky,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: ValueKey(buttonKey),
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: p.sky,
                      foregroundColor: p.onAccent,
                      disabledBackgroundColor: p.glassBg,
                      disabledForegroundColor: p.textMuted,
                      minimumSize: const Size(112, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: sending
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: p.onAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Sending…'),
                            ],
                          )
                        : Text(buttonLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    StudioPalette p, {
    required String label,
    String? hint,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: p.textMuted, fontSize: 13),
      hintStyle: TextStyle(color: p.textDim, fontSize: 13),
      filled: true,
      fillColor: p.glassBg,
      counterStyle: TextStyle(color: p.textMuted, fontSize: 11),
      contentPadding: const EdgeInsets.all(12),
      enabledBorder: border(p.glassBorder),
      focusedBorder: border(p.sky),
      disabledBorder: border(p.glassBorder),
    );
  }

  static String _categoryLabel(FeedbackCategory category) => switch (category) {
    FeedbackCategory.bug => 'Bug',
    FeedbackCategory.idea => 'Idea',
    FeedbackCategory.confusing => 'Confusing',
    FeedbackCategory.other => 'Other',
  };
}

/// The Settings row that opens [FeedbackSheet].
///
/// Kept separate from `_SettingsScreen` so the row and its draft subtitle can
/// be tested without mounting the whole app shell.
class FeedbackSettingsTile extends ConsumerWidget {
  const FeedbackSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDraft = ref.watch(
      feedbackProvider.select((state) => state.hasDraft),
    );
    return ListTile(
      key: const ValueKey('settings_send_feedback'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.feedback_outlined,
        color: StudioPalette.of(context).sky,
      ),
      title: const Text('Send feedback'),
      subtitle: Text(
        hasDraft ? 'Draft saved' : 'Bugs, ideas, anything confusing',
      ),
      onTap: () => FeedbackSheet.show(context),
    );
  }
}
