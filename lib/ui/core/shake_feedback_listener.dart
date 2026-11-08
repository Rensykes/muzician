/// Opens the feedback sheet when the device is shaken.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../utils/shake_feedback_detector.dart';
import 'feedback_sheet.dart';

/// Whether the running platform can detect a shake for feedback.
///
/// Shake is a native phone gesture; web and desktop keep only the Settings
/// entry, so no sensor stream is ever opened there.
bool get isShakeFeedbackAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Creates the accelerometer stream the shake listener subscribes to.
///
/// A provider so widget tests can push their own samples instead of talking
/// to a real sensor.
final shakeStreamProvider = Provider<Stream<AccelerometerEvent> Function()>(
  (ref) =>
      () => accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
);

/// Wraps [child] and opens the feedback sheet when the device is shaken.
///
/// A shake only opens the composer, which is also skipped while another route
/// is on top so a dialog or sheet is never stacked underneath a new one.
class ShakeFeedbackListener extends ConsumerStatefulWidget {
  const ShakeFeedbackListener({
    super.key,
    required this.screenLabel,
    required this.child,
    this.enabled = true,
  });

  /// The screen reported in the sheet's diagnostics.
  final String screenLabel;

  final Widget child;

  /// Whether shakes are listened for.
  ///
  /// The shell keeps this false until a workspace is actually showing, so a
  /// shake on the startup or recovery view cannot open the sheet with a screen
  /// the user never visited.
  final bool enabled;

  @override
  ConsumerState<ShakeFeedbackListener> createState() =>
      _ShakeFeedbackListenerState();
}

class _ShakeFeedbackListenerState extends ConsumerState<ShakeFeedbackListener> {
  final _detector = ShakeFeedbackDetector();
  StreamSubscription<AccelerometerEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _syncSubscription();
  }

  @override
  void didUpdateWidget(ShakeFeedbackListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _syncSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Opens the sensor stream while shakes can do something, and closes it as
  /// soon as they cannot, so no subscription outlives the workspace shell.
  void _syncSubscription() {
    final shouldListen = widget.enabled && isShakeFeedbackAvailable;
    if (!shouldListen) {
      if (_subscription == null) return;
      _subscription?.cancel();
      _subscription = null;
      _detector.reset();
      return;
    }
    if (_subscription != null) return;
    _subscription = ref
        .read(shakeStreamProvider)()
        .listen(_onSample, onError: (Object _) {});
  }

  void _onSample(AccelerometerEvent event) {
    if (!mounted) return;
    // Drop samples while another route covers the shell instead of queueing
    // them, so closing a sheet never triggers a stale shake.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      _detector.reset();
      return;
    }
    if (!_detector.add(event.x, event.y, event.z, event.timestamp)) return;
    unawaited(FeedbackSheet.show(context, screen: widget.screenLabel));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
