import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/feedback_entry.dart';
import 'package:muzician/store/feedback_store.dart';
import 'package:muzician/ui/core/feedback_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_feedback_service.dart';

Future<ProviderContainer> pumpSheet(
  WidgetTester tester,
  FakeFeedbackService service, {
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(service),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FeedbackSheet())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> pumpTile(
  WidgetTester tester, {
  Future<void> Function(ProviderContainer container)? prepare,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (prepare != null) await prepare(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: FeedbackSettingsTile())),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('cannot send an empty message', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester, FakeFeedbackService());
    await tester.tap(find.byKey(const ValueKey('feedback_send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Write a message'), findsOneWidget);
  });

  testWidgets('sends the typed message with its category', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = FakeFeedbackService();
    await pumpSheet(tester, service);
    await tester.enterText(
      find.byKey(const ValueKey('feedback_message')),
      'bug!',
    );
    await tester.tap(find.byKey(const ValueKey('feedback_category_confusing')));
    await tester.tap(find.byKey(const ValueKey('feedback_send')));
    await tester.pumpAndSettle();
    expect(service.sent.single.message, 'bug!');
    expect(service.sent.single.category, FeedbackCategory.confusing);
  });

  testWidgets('a failure keeps the text and offers Retry and Copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester, FakeFeedbackService(failing: 1));
    await tester.enterText(
      find.byKey(const ValueKey('feedback_message')),
      'oops',
    );
    await tester.tap(find.byKey(const ValueKey('feedback_send')));
    await tester.pumpAndSettle();
    expect(find.text('oops'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_copy')), findsOneWidget);
  });

  testWidgets('a pending send keeps the sheet open with Retry and Copy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(
      tester,
      FakeFeedbackService(hang: true),
      overrides: [
        feedbackSendTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    await tester.enterText(
      find.byKey(const ValueKey('feedback_message')),
      'slow',
    );
    await tester.tap(find.byKey(const ValueKey('feedback_send')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.textContaining('Still trying'), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('feedback_message')), findsOneWidget);
  });

  testWidgets('copy writes the message, a blank line and the diagnostics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final container = await pumpSheet(tester, FakeFeedbackService());
    // The package_info lookup is a real platform call, so let it settle
    // outside the fake-async zone before reading the attached summary.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(container.read(feedbackProvider).diagnostics, isNotNull);
    final summary = container.read(feedbackProvider).diagnostics!.summary;
    await tester.enterText(
      find.byKey(const ValueKey('feedback_message')),
      'hello',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback_copy')));
    await tester.pumpAndSettle();
    final data = calls.single.arguments as Map<Object?, Object?>;
    expect(data['text'], 'hello\n\n$summary');
  });

  testWidgets('settings tile shows the default subtitle and opens the sheet', (
    tester,
  ) async {
    await pumpTile(tester);
    expect(find.text('Bugs, ideas, anything confusing'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_send_feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('feedback_message')), findsOneWidget);
  });

  testWidgets('settings tile reports a saved draft', (tester) async {
    await pumpTile(
      tester,
      prepare: (container) =>
          container.read(feedbackProvider.notifier).setMessage('half-written'),
    );
    expect(find.text('Draft saved'), findsOneWidget);
    expect(find.text('Bugs, ideas, anything confusing'), findsNothing);
  });

  testWidgets('scrolls with the keyboard open on a 320x568 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSheet(tester, FakeFeedbackService());
    await tester.enterText(
      find.byKey(const ValueKey('feedback_message')),
      'x' * 400,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('feedback_send')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('feedback_send')));
    expect(rect.bottom, lessThanOrEqualTo(568));
    expect(rect.top, greaterThanOrEqualTo(0));
  });
}
