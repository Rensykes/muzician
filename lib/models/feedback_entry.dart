/// An in-app feedback submission composed on the client.
library;

import '../utils/feedback_diagnostics.dart';

/// Number of Unicode runes in [value].
///
/// Limits are counted in runes so an emoji is one character, not two UTF-16
/// code units.
int countRunes(String value) => value.runes.length;

/// Kind of feedback the user is sending.
enum FeedbackCategory {
  bug,
  idea,
  confusing,
  other;

  /// The value stored in the backend `category` field.
  String get wireName => name;
}

/// A validated feedback draft, ready for the send service to submit.
///
/// [docId] is the document path chosen by the client retry loop; [attempt] and
/// [possiblyWritten] are client-only, and none of them is part of [toMap],
/// which carries only the fields the backend accepts.
class FeedbackEntry {
  const FeedbackEntry({
    required this.docId,
    required this.sessionId,
    required this.message,
    required this.category,
    required this.contact,
    required this.diagnostics,
    required this.attempt,
    this.possiblyWritten = false,
  });

  static const int maxMessageLength = 4000;
  static const int maxContactLength = 200;

  final String docId;
  final String sessionId;
  final String message;
  final FeedbackCategory category;
  final String contact;
  final FeedbackDiagnostics diagnostics;
  final int attempt;

  /// Whether the previous attempt could have reached the server.
  ///
  /// Only a timeout or an unreachable error leaves a write possibly recorded;
  /// a rejected or unknown failure means nothing landed. A `permission-denied`
  /// on the next attempt is only read as "already recorded" when this is true.
  final bool possiblyWritten;

  /// The fields written to the backend document.
  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': 1,
    'message': message.trim(),
    'category': category.wireName,
    'contact': contact.trim(),
    'clientSessionId': sessionId,
    ...diagnostics.toMap(),
  };

  FeedbackEntry copyWith({
    String? docId,
    String? sessionId,
    String? message,
    FeedbackCategory? category,
    String? contact,
    FeedbackDiagnostics? diagnostics,
    int? attempt,
    bool? possiblyWritten,
  }) => FeedbackEntry(
    docId: docId ?? this.docId,
    sessionId: sessionId ?? this.sessionId,
    message: message ?? this.message,
    category: category ?? this.category,
    contact: contact ?? this.contact,
    diagnostics: diagnostics ?? this.diagnostics,
    attempt: attempt ?? this.attempt,
    possiblyWritten: possiblyWritten ?? this.possiblyWritten,
  );

  /// `null` when [raw] has visible text within [maxMessageLength] runes.
  static String? validateMessage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Write a message first.';
    if (countRunes(trimmed) > maxMessageLength) {
      return 'That message is too long.';
    }
    return null;
  }

  /// `null` when [raw] is empty or within [maxContactLength] runes.
  static String? validateContact(String raw) {
    if (countRunes(raw.trim()) > maxContactLength) {
      return 'That email is too long.';
    }
    return null;
  }
}
