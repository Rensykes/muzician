/// A scriptable [FeedbackService] for widget and store tests.
library;

import 'dart:async';

import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/utils/feedback_service.dart';

/// Records submissions and fails or hangs on demand.
class FakeFeedbackService implements FeedbackService {
  FakeFeedbackService({
    this.failing = 0,
    this.hang = false,
    this.failure = FeedbackSendFailure.unreachable,
    this.failures,
    this.gate,
  });

  /// Every entry passed to [send], successful or not.
  final List<FeedbackEntry> attempts = [];

  final List<FeedbackEntry> _sent = [];

  /// The first [failing] calls throw [failure].
  int failing;

  /// The failure the scripted [failing] calls throw.
  final FeedbackSendFailure failure;

  /// When provided, the first calls throw these failures in order, then
  /// succeed. Takes precedence over [failing] for the calls it covers.
  final List<FeedbackSendFailure>? failures;

  /// When true, [send] never completes.
  bool hang;

  /// When set, [send] waits for it before succeeding or throwing, so a test
  /// can act while the call is in flight.
  Completer<void>? gate;

  /// Entries that were sent successfully.
  List<FeedbackEntry> get sent => List.unmodifiable(_sent);

  @override
  Future<void> send(FeedbackEntry entry) async {
    attempts.add(entry);
    if (hang) {
      await Completer<void>().future;
    }
    final gate = this.gate;
    if (gate != null) {
      await gate.future;
    }
    final scripted = failures;
    if (scripted != null) {
      if (attempts.length <= scripted.length) {
        throw FeedbackSendException(scripted[attempts.length - 1]);
      }
    } else if (attempts.length <= failing) {
      throw FeedbackSendException(failure);
    }
    _sent.add(entry);
  }
}
