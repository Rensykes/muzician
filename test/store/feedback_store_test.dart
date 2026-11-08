import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/store/feedback_store.dart';
import 'package:muzician/utils/feedback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(
    FakeFeedbackService service, {
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 8),
  }) => ProviderContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(service),
      if (clock != null) feedbackClockProvider.overrideWithValue(clock),
      feedbackSendTimeoutProvider.overrideWithValue(timeout),
    ],
  );

  Future<FeedbackNotifier> loaded(ProviderContainer c) async {
    final n = c.read(feedbackProvider.notifier);
    await n.hydrate();
    return n;
  }

  test('sends, clears the draft, and records the send time', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService();
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('crashes on open');
    await n.setCategory(FeedbackCategory.bug);
    expect(await n.send(), isTrue);
    expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
    expect(c.read(feedbackProvider).message, '');
    expect(service.sent.single.docId, isNotEmpty);
  });

  test('a failed send keeps the text, the docId, and bumps attempt', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService(failing: 1);
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('hello');
    expect(await n.send(), isFalse);
    expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
    expect(c.read(feedbackProvider).message, 'hello');
    await n.send();
    expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
    expect(service.attempts.map((e) => e.docId).toSet(), hasLength(1));
    expect(service.attempts.map((e) => e.attempt), [1, 2]);
  });

  test('a timeout leaves the text pending, not failed', () async {
    SharedPreferences.setMockInitialValues({});
    final c = containerWith(
      FakeFeedbackService(hang: true),
      timeout: const Duration(milliseconds: 20),
    );
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('offline');
    await n.send();
    expect(c.read(feedbackProvider).status, FeedbackStatus.pending);
    expect(c.read(feedbackProvider).message, 'offline');
  });

  test('an alreadyRecorded retry counts as sent', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService(
      failures: [
        FeedbackSendFailure.unreachable,
        FeedbackSendFailure.alreadyRecorded,
      ],
    );
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('landed twice');
    await n.send(); // unreachable -> failed, text and docId kept
    expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
    expect(c.read(feedbackProvider).message, 'landed twice');
    expect(c.read(feedbackProvider).docId, isNotNull);
    expect(await n.send(), isTrue); // alreadyRecorded -> success
    expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
    expect(c.read(feedbackProvider).message, '');
    expect(service.attempts, hasLength(2));
    expect(service.attempts.map((e) => e.docId).toSet(), hasLength(1));
    expect(service.attempts.map((e) => e.attempt), [1, 2]);
  });

  test('text typed during an in-flight send survives the success', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService(gate: Completer<void>());
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('first version');
    final send = n.send();
    await n.setMessage('typed later');
    service.gate!.complete();
    await send;
    final state = c.read(feedbackProvider);
    expect(state.status, FeedbackStatus.sent);
    expect(state.message, 'typed later');
    expect(state.docId, isNull);
    expect(service.attempts.single.message, 'first version');
  });

  test('the draft and its docId survive a new container', () async {
    SharedPreferences.setMockInitialValues({});
    final a = containerWith(FakeFeedbackService());
    await (await loaded(a)).setMessage('restored');
    a.dispose();
    final b = containerWith(FakeFeedbackService());
    addTearDown(b.dispose);
    await loaded(b);
    expect(b.read(feedbackProvider).message, 'restored');
    expect(b.read(feedbackProvider).docId, isNotNull);
  });

  test('cooldown blocks a repeat send for 60s but never a retry', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 11, 8, 12);
    final service = FakeFeedbackService(failing: 1);
    final c = containerWith(service, clock: () => now);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('same words');
    await n.send(); // fails, no cooldown
    await n.send(); // retry, succeeds
    expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
    await n.setMessage('same words');
    await n.send(); // blocked
    expect(service.attempts, hasLength(2));
    expect(
      c.read(feedbackProvider).error,
      'You just sent this — give it a minute.',
    );
    expect(c.read(feedbackProvider).status, FeedbackStatus.idle);
    now = now.add(const Duration(seconds: 61));
    await n.send();
    expect(service.attempts, hasLength(3));
  });

  test('a backwards clock never blocks a repeat send', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 11, 8, 12);
    final service = FakeFeedbackService();
    final c = containerWith(service, clock: () => now);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('same words');
    await n.send();
    await n.setMessage('same words');
    now = now.subtract(const Duration(minutes: 5));
    await n.send();
    expect(service.attempts, hasLength(2));
  });

  test('an empty message never reaches the service', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService();
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.send();
    expect(service.attempts, isEmpty);
    expect(c.read(feedbackProvider).error, 'Write a message first.');
  });
}
