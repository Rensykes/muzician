/// A scriptable [FeedbackService] for widget and store tests.
library;

import 'dart:async';

import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/utils/feedback_service.dart';

/// Records submissions and fails or hangs on demand.
class FakeFeedbackService implements FeedbackService {
  FakeFeedbackService({this.failing = 0, this.hang = false});

  /// Every entry passed to [send], successful or not.
  final List<FeedbackEntry> attempts = [];

  final List<FeedbackEntry> _sent = [];

  /// The first [failing] calls throw an unreachable failure.
  int failing;

  /// When true, [send] never completes.
  bool hang;

  /// Entries that were sent successfully.
  List<FeedbackEntry> get sent => List.unmodifiable(_sent);

  @override
  Future<void> send(FeedbackEntry entry) async {
    attempts.add(entry);
    if (hang) {
      await Completer<void>().future;
    }
    if (attempts.length <= failing) {
      throw const FeedbackSendException(FeedbackSendFailure.unreachable);
    }
    _sent.add(entry);
  }
}
