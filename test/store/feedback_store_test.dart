import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/store/feedback_store.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';
import 'package:muzician/utils/feedback_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerWith(
    FakeFeedbackService service, {
    DateTime Function()? clock,
    Duration timeout = const Duration(seconds: 8),
    List<Override> overrides = const [],
  }) => ProviderContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(service),
      if (clock != null) feedbackClockProvider.overrideWithValue(clock),
      feedbackSendTimeoutProvider.overrideWithValue(timeout),
      ...overrides,
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

  test('a rejected send retried stays failed and keeps the draft', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService(
      failing: 2,
      failure: FeedbackSendFailure.rejected,
    );
    final c = containerWith(service);
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('bad payload');
    expect(await n.send(), isFalse);
    expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
    expect(await n.send(), isFalse);
    expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
    expect(c.read(feedbackProvider).message, 'bad payload');
    expect(c.read(feedbackProvider).docId, isNotNull);
    expect(c.read(feedbackProvider).possiblyWritten, isFalse);
    // Nothing could have landed, so neither attempt is treated as written.
    expect(service.attempts.map((e) => e.possiblyWritten), [false, false]);
  });

  test('a timed-out retry reads a denial as already recorded', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService(
      hang: true,
      failures: [
        FeedbackSendFailure.unreachable,
        FeedbackSendFailure.alreadyRecorded,
      ],
    );
    final c = containerWith(service, timeout: const Duration(milliseconds: 20));
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('slow but landed');
    expect(await n.send(), isFalse);
    expect(c.read(feedbackProvider).status, FeedbackStatus.pending);
    expect(c.read(feedbackProvider).possiblyWritten, isTrue);

    service.hang = false;
    expect(await n.send(), isTrue);
    expect(c.read(feedbackProvider).status, FeedbackStatus.sent);
    expect(c.read(feedbackProvider).message, '');
    expect(service.attempts.map((e) => e.possiblyWritten), [false, true]);
  });

  test('send waits for diagnostics captured after it was called', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService();
    final capture = Completer<FeedbackDiagnostics>();
    final c = containerWith(
      service,
      overrides: [
        feedbackDiagnosticsProvider.overrideWithValue((_) => capture.future),
      ],
    );
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('late details');
    final sending = n.send();
    await Future<void>.delayed(Duration.zero);
    capture.complete(
      const FeedbackDiagnostics(
        appVersion: '2.0.0+2',
        platform: 'web',
        osVersion: 'Chrome / macOS',
        screen: 'settings',
        locale: 'en',
      ),
    );
    expect(await sending, isTrue);
    final diagnostics = service.sent.single.diagnostics;
    expect(diagnostics.appVersion, '2.0.0+2');
    expect(diagnostics.osVersion, 'Chrome / macOS');
    expect(service.sent.single.toMap()['appVersion'], '2.0.0+2');
  });

  test('a failed capture still sends a rules-valid platform', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = FakeFeedbackService();
    final c = containerWith(
      service,
      overrides: [
        feedbackDiagnosticsProvider.overrideWithValue(
          (_) => Future<FeedbackDiagnostics>.error(StateError('no plugin')),
        ),
      ],
    );
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('no details');
    expect(await n.send(screen: 'settings'), isTrue);
    final entry = service.sent.single;
    expect(entry.diagnostics.platform, isIn(['web', 'android']));
    expect(entry.diagnostics.platform, isNot('unknown'));
    expect(entry.diagnostics.screen, 'settings');
    expect(entry.toMap()['platform'], isNot('unknown'));
  });

  test('a send from a new screen captures fresh diagnostics', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService();
    String? captured;
    final c = containerWith(
      service,
      overrides: [
        feedbackDiagnosticsProvider.overrideWithValue((screen) async {
          captured = screen;
          return FeedbackDiagnostics(
            appVersion: '2.0.0+2',
            platform: 'web',
            osVersion: 'Chrome / macOS',
            screen: screen,
            locale: 'en',
          );
        }),
      ],
    );
    addTearDown(c.dispose);
    final n = await loaded(c);
    await n.setMessage('wrong tab');
    await n.attachDiagnostics(
      const FeedbackDiagnostics(
        appVersion: '2.0.0+2',
        platform: 'web',
        osVersion: 'Chrome / macOS',
        screen: 'roll',
        locale: 'en',
      ),
    );
    expect(await n.send(screen: 'piano'), isTrue);
    expect(captured, 'piano');
    expect(service.sent.single.diagnostics.screen, 'piano');
  });

  test(
    'editing after a possibly-written attempt starts a new document',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = FakeFeedbackService(
        failures: [
          FeedbackSendFailure.unreachable,
          FeedbackSendFailure.rejected,
        ],
      );
      final c = containerWith(service);
      addTearDown(c.dispose);
      final n = await loaded(c);
      await n.setMessage('original');
      expect(await n.send(), isFalse); // unreachable: may have landed
      expect(c.read(feedbackProvider).possiblyWritten, isTrue);
      final firstDocId = c.read(feedbackProvider).docId;

      await n.setMessage('edited');
      expect(c.read(feedbackProvider).possiblyWritten, isFalse);
      expect(c.read(feedbackProvider).docId, isNot(firstDocId));

      // The edited text gets its own document, so a denial stays a failure.
      expect(await n.send(), isFalse);
      expect(c.read(feedbackProvider).status, FeedbackStatus.failed);
      expect(c.read(feedbackProvider).message, 'edited');
      expect(service.attempts.map((e) => e.docId).toSet(), hasLength(2));
      expect(service.attempts.last.possiblyWritten, isFalse);
    },
  );

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
