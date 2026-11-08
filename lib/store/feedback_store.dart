/// Feedback draft Riverpod store.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/feedback_entry.dart';
import '../utils/feedback_diagnostics.dart';
import '../utils/feedback_doc_writer.dart';
import '../utils/feedback_service.dart';

/// Where the unsent draft is persisted between launches.
const feedbackDraftStorageKey = '@muzician/feedback_draft/v1';

/// How long an identical message is held back after a successful send.
const feedbackSendCooldown = Duration(seconds: 60);

/// Where a feedback submission is in its send lifecycle.
enum FeedbackStatus { idle, sending, pending, sent, failed }

/// The composer draft and the state of its last send.
class FeedbackState {
  const FeedbackState({
    required this.sessionId,
    this.message = '',
    this.category = FeedbackCategory.bug,
    this.contact = '',
    this.docId,
    this.attempt = 0,
    this.diagnostics,
    this.status = FeedbackStatus.idle,
    this.error,
    this.lastSentAt,
    this.lastSentMessage = '',
  });

  /// Restores a persisted draft, keeping a freshly generated [sessionId].
  factory FeedbackState.fromJson(
    Map<String, dynamic> json, {
    required String sessionId,
  }) => FeedbackState(
    sessionId: sessionId,
    message: json['message'] as String? ?? '',
    category: FeedbackCategory.values.firstWhere(
      (value) => value.wireName == json['category'],
      orElse: () => FeedbackCategory.bug,
    ),
    contact: json['contact'] as String? ?? '',
    docId: json['docId'] as String?,
    attempt: (json['attempt'] as num?)?.toInt() ?? 0,
    lastSentAt: switch (json['lastSentAt']) {
      final num value => DateTime.fromMillisecondsSinceEpoch(value.toInt()),
      _ => null,
    },
    lastSentMessage: json['lastSentMessage'] as String? ?? '',
  );

  /// Per-launch identity attached to every submission; never persisted.
  final String sessionId;
  final String message;
  final FeedbackCategory category;
  final String contact;

  /// The document id chosen for this draft and reused by every retry.
  final String? docId;
  final int attempt;
  final FeedbackDiagnostics? diagnostics;
  final FeedbackStatus status;
  final String? error;
  final DateTime? lastSentAt;
  final String lastSentMessage;

  /// Whether there is text worth keeping or copying.
  bool get hasDraft => message.trim().isNotEmpty;

  FeedbackState copyWith({
    String? message,
    FeedbackCategory? category,
    String? contact,
    String? docId,
    bool clearDocId = false,
    int? attempt,
    FeedbackDiagnostics? diagnostics,
    FeedbackStatus? status,
    String? error,
    bool clearError = false,
    DateTime? lastSentAt,
    String? lastSentMessage,
  }) => FeedbackState(
    sessionId: sessionId,
    message: message ?? this.message,
    category: category ?? this.category,
    contact: contact ?? this.contact,
    docId: clearDocId ? null : (docId ?? this.docId),
    attempt: attempt ?? this.attempt,
    diagnostics: diagnostics ?? this.diagnostics,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    lastSentAt: lastSentAt ?? this.lastSentAt,
    lastSentMessage: lastSentMessage ?? this.lastSentMessage,
  );

  /// The fields kept in [feedbackDraftStorageKey].
  Map<String, Object?> toJson() => <String, Object?>{
    'message': message,
    'category': category.wireName,
    'contact': contact,
    'docId': docId,
    'attempt': attempt,
    'lastSentAt': lastSentAt?.millisecondsSinceEpoch,
    'lastSentMessage': lastSentMessage,
  };
}

/// Fields every entry needs, used until the sheet attaches real diagnostics.
const _unknownDiagnostics = FeedbackDiagnostics(
  appVersion: 'unknown',
  platform: 'unknown',
  osVersion: 'unknown',
  screen: 'unknown',
  locale: 'unknown',
);

/// Owns the feedback draft, its retry document id, and the send lifecycle.
class FeedbackNotifier extends Notifier<FeedbackState> {
  @override
  FeedbackState build() => FeedbackState(sessionId: const Uuid().v4());

  /// Restores the persisted draft under a fresh per-launch session id.
  Future<void> hydrate() async {
    var restored = FeedbackState(sessionId: const Uuid().v4());
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(feedbackDraftStorageKey);
      if (raw != null) {
        restored = FeedbackState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
          sessionId: restored.sessionId,
        );
      }
    } catch (_) {
      // A missing or unreadable draft must never block startup.
    }
    state = restored;
  }

  Future<void> setMessage(String value) async {
    state = _editing(state.copyWith(message: value));
    await _persist();
  }

  Future<void> setCategory(FeedbackCategory value) async {
    state = _editing(state.copyWith(category: value));
    await _persist();
  }

  Future<void> setContact(String value) async {
    state = _editing(state.copyWith(contact: value));
    await _persist();
  }

  Future<void> attachDiagnostics(FeedbackDiagnostics value) async {
    state = state.copyWith(diagnostics: value);
    await _persist();
  }

  /// Sends the draft, or records why it could not be sent.
  ///
  /// Returns `true` only when the backend accepted the submission (a normal
  /// success or an `alreadyRecorded` retry), so the sheet never has to infer
  /// the outcome from [FeedbackStatus].
  Future<bool> send() async {
    final current = state;
    if (current.status == FeedbackStatus.sending) return false;

    final error =
        FeedbackEntry.validateMessage(current.message) ??
        FeedbackEntry.validateContact(current.contact);
    if (error != null) {
      state = current.copyWith(error: error);
      await _persist();
      return false;
    }

    final now = ref.read(feedbackClockProvider)();
    if (_coolingDown(current, now)) {
      state = current.copyWith(error: 'You just sent this — give it a minute.');
      return false;
    }

    // The id is chosen once and kept through retries so a retry of a write
    // that already landed is recognised as alreadyRecorded.
    final docId = current.docId ?? const Uuid().v4();
    final attempt = current.attempt + 1;
    final entry = FeedbackEntry(
      docId: docId,
      sessionId: current.sessionId,
      message: current.message,
      category: current.category,
      contact: current.contact,
      diagnostics: current.diagnostics ?? _unknownDiagnostics,
      attempt: attempt,
    );

    state = current.copyWith(
      docId: docId,
      attempt: attempt,
      status: FeedbackStatus.sending,
      clearError: true,
    );
    await _persist();

    try {
      await ref
          .read(feedbackServiceProvider)
          .send(entry)
          .timeout(ref.read(feedbackSendTimeoutProvider));
      await _markSent(entry, now);
      return true;
    } on TimeoutException {
      state = state.copyWith(
        status: FeedbackStatus.pending,
        error: 'Still trying… your text is saved.',
      );
      await _persist();
      return false;
    } on FeedbackSendException catch (error) {
      if (error.failure == FeedbackSendFailure.alreadyRecorded) {
        await _markSent(entry, now);
        return true;
      }
      await _markFailed();
      return false;
    } catch (_) {
      await _markFailed();
      return false;
    }
  }

  Future<void> _markSent(FeedbackEntry entry, DateTime now) async {
    final current = state;
    // Text typed during the in-flight send was not part of [entry]; keep it
    // instead of silently discarding it.
    final draftChanged =
        current.message != entry.message || current.contact != entry.contact;
    // A resend must never reuse a document id that already landed, so the id
    // and the attempt counter are always cleared on success.
    state = current.copyWith(
      message: draftChanged ? current.message : '',
      contact: draftChanged ? current.contact : '',
      status: FeedbackStatus.sent,
      lastSentAt: now,
      lastSentMessage: entry.message.trim(),
      clearDocId: true,
      attempt: 0,
      clearError: true,
    );
    await _persist();
  }

  Future<void> _markFailed() async {
    state = state.copyWith(
      status: FeedbackStatus.failed,
      error: "Couldn't send. Your text is saved — try again.",
    );
    await _persist();
  }

  /// Only a send that visibly succeeded starts the identical-message cooldown;
  /// `pending` and `failed` must always allow Retry.
  bool _coolingDown(FeedbackState current, DateTime now) {
    final lastSentAt = current.lastSentAt;
    if (lastSentAt == null) return false;
    // A clock that moved backwards must not block the text indefinitely.
    if (now.isBefore(lastSentAt)) return false;
    return current.message.trim() == current.lastSentMessage &&
        now.difference(lastSentAt) < feedbackSendCooldown;
  }

  /// Keeps a draft's document id stable while the user edits it.
  FeedbackState _editing(FeedbackState next) {
    if (next.status == FeedbackStatus.sending) return next;
    final withDocId = next.docId == null
        ? next.copyWith(docId: const Uuid().v4())
        : next;
    return withDocId.copyWith(status: FeedbackStatus.idle, clearError: true);
  }

  /// Writes the draft, swallowing storage errors.
  ///
  /// A failing disk must never rewrite a send outcome or leave [status] stuck
  /// at `sending`.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        feedbackDraftStorageKey,
        jsonEncode(state.toJson()),
      );
    } catch (_) {
      // The draft is best effort; the in-memory state stays authoritative.
    }
  }
}

final feedbackProvider = NotifierProvider<FeedbackNotifier, FeedbackState>(
  FeedbackNotifier.new,
);

final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => const FirestoreFeedbackService(FirestoreDocWriter()),
);

final feedbackClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final feedbackSendTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);
