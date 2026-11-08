import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/feedback_store.dart';
import 'package:muzician/ui/core/shake_feedback_listener.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_feedback_service.dart';

/// Runs [body] while the app believes it is on a phone.
///
/// The host test runner is a desktop platform, where shake feedback is
/// intentionally off. The override is cleared before the body returns because
/// the widget binding checks the foundation debug variables at the end of a
/// test, before teardown callbacks run.
Future<void> _onPhone(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

ProviderContainer _makeContainer(
  Stream<AccelerometerEvent> stream, {
  VoidCallback? onStreamRequested,
}) {
  final container = ProviderContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(FakeFeedbackService()),
      shakeStreamProvider.overrideWithValue(() {
        onStreamRequested?.call();
        return stream;
      }),
      feedbackSendTimeoutProvider.overrideWithValue(const Duration(seconds: 1)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Mounts the listener in a host app, reusing the same element on a repump so
/// [ShakeFeedbackListener.didUpdateWidget] sees the change.
Future<void> _pumpShell(
  WidgetTester tester,
  ProviderContainer container, {
  String screenLabel = 'roll',
  bool enabled = true,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: ShakeFeedbackListener(
        key: const ValueKey('shake_listener'),
        screenLabel: screenLabel,
        enabled: enabled,
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ),
);

Future<ProviderContainer> _pumpListener(
  WidgetTester tester,
  Stream<AccelerometerEvent> stream, {
  VoidCallback? onStreamRequested,
}) async {
  SharedPreferences.setMockInitialValues({});
  final container = _makeContainer(
    stream,
    onStreamRequested: onStreamRequested,
  );
  await _pumpShell(tester, container);
  return container;
}

/// Feeds the three hard samples the detector needs to report a shake.
void _addShake(
  StreamController<AccelerometerEvent> controller, [
  DateTime? at,
]) {
  final timestamp = at ?? DateTime.now();
  for (var i = 0; i < 3; i++) {
    controller.add(AccelerometerEvent(30, 0, 0, timestamp));
  }
}

/// Lets the sheet's real package_info capture finish outside fake-async.
Future<void> _settleDiagnostics(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a shake opens the sheet with the current screen label', (
    tester,
  ) async {
    await _onPhone(() async {
      final controller = StreamController<AccelerometerEvent>();
      addTearDown(controller.close);
      final container = await _pumpListener(tester, controller.stream);

      _addShake(controller);
      await tester.pumpAndSettle();

      expect(find.text('Send feedback'), findsOneWidget);
      await _settleDiagnostics(tester);
      expect(container.read(feedbackProvider).diagnostics?.screen, 'roll');
    });
  });

  testWidgets('quiet movement does not open the sheet', (tester) async {
    await _onPhone(() async {
      final controller = StreamController<AccelerometerEvent>();
      addTearDown(controller.close);
      await _pumpListener(tester, controller.stream);

      for (var i = 0; i < 3; i++) {
        controller.add(AccelerometerEvent(0, 0, 9.81, DateTime.now()));
      }
      await tester.pumpAndSettle();

      expect(find.text('Send feedback'), findsNothing);
    });
  });

  testWidgets('no sensor stream is opened off a phone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      var opened = 0;
      await _pumpListener(
        tester,
        const Stream<AccelerometerEvent>.empty(),
        onStreamRequested: () => opened++,
      );

      await tester.pumpAndSettle();

      expect(opened, 0);
      expect(find.text('Send feedback'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('no subscription exists until the listener is enabled', (
    tester,
  ) async {
    await _onPhone(() async {
      var opened = 0;
      final controller = StreamController<AccelerometerEvent>();
      addTearDown(controller.close);
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer(
        controller.stream,
        onStreamRequested: () => opened++,
      );

      await _pumpShell(tester, container, enabled: false);
      _addShake(controller);
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('Send feedback'), findsNothing);

      await _pumpShell(tester, container);
      await tester.pumpAndSettle();
      expect(opened, 1);

      _addShake(controller, DateTime.now().add(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
    });
  });

  testWidgets('a route on top swallows shakes until it is popped', (
    tester,
  ) async {
    await _onPhone(() async {
      final controller = StreamController<AccelerometerEvent>();
      addTearDown(controller.close);
      await _pumpListener(tester, controller.stream);

      final hostContext = tester.element(find.byType(Scaffold));
      unawaited(
        showDialog<void>(
          context: hostContext,
          builder: (_) => const AlertDialog(title: Text('Route on top')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Route on top'), findsOneWidget);

      _addShake(controller);
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsNothing);

      Navigator.of(hostContext).pop();
      await tester.pumpAndSettle();
      expect(find.text('Route on top'), findsNothing);

      _addShake(controller, DateTime.now().add(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
    });
  });

  testWidgets('the rebuilt label is used for the next shake', (tester) async {
    await _onPhone(() async {
      final controller = StreamController<AccelerometerEvent>();
      addTearDown(controller.close);
      SharedPreferences.setMockInitialValues({});
      final container = _makeContainer(controller.stream);
      await _pumpShell(tester, container);

      _addShake(controller);
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
      await _settleDiagnostics(tester);
      expect(container.read(feedbackProvider).diagnostics?.screen, 'roll');

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsNothing);

      // Same widget type and key, so the element and its detector survive.
      await _pumpShell(tester, container, screenLabel: 'piano');
      await tester.pumpAndSettle();

      _addShake(controller, DateTime.now().add(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
      await _settleDiagnostics(tester);
      expect(container.read(feedbackProvider).diagnostics?.screen, 'piano');
    });
  });

  testWidgets('unmounting cancels the sensor subscription', (tester) async {
    await _onPhone(() async {
      var cancelled = false;
      final controller = StreamController<AccelerometerEvent>(
        onCancel: () => cancelled = true,
      );
      addTearDown(() => unawaited(controller.close()));
      await _pumpListener(tester, controller.stream);
      expect(cancelled, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });
  });
}
