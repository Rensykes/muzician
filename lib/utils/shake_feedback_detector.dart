/// Turns a stream of accelerometer samples into shake events for feedback.
///
/// A shake is a short run of hard accelerations, so the detector asks for
/// several consecutive loud samples and then stays quiet for a cooldown to
/// swallow the rest of the same physical gesture.
library;

import 'dart:math' as math;

/// Counts consecutive high-acceleration samples and reports a shake once.
class ShakeFeedbackDetector {
  ShakeFeedbackDetector({
    this.threshold = 2.6,
    this.requiredSamples = 3,
    this.cooldown = const Duration(milliseconds: 1500),
  }) : assert(threshold > 0),
       assert(requiredSamples > 0),
       assert(!cooldown.isNegative);

  /// Acceleration magnitude, in multiples of gravity, at or above which a
  /// sample counts toward a shake.
  final double threshold;

  /// How many counting samples in a row are needed to report a shake.
  final int requiredSamples;

  /// How long after a reported shake further shakes are ignored.
  final Duration cooldown;

  /// Standard gravity in m/s², the divisor that makes a magnitude a multiple
  /// of gravity.
  static const double _gravity = 9.80665;

  int _run = 0;
  DateTime? _lastFire;

  /// Feeds one sample of [x], [y] and [z] acceleration in m/s² taken at [at].
  ///
  /// Returns `true` exactly when this sample completes a confirming run and
  /// the previous report is at least [cooldown] old. A sample below
  /// [threshold], or a suppressed report, starts the run over.
  bool add(double x, double y, double z, DateTime at) {
    final magnitude = math.sqrt(x * x + y * y + z * z) / _gravity;
    if (magnitude < threshold) {
      _run = 0;
      return false;
    }

    _run++;
    if (_run < requiredSamples) return false;

    _run = 0;
    final lastFire = _lastFire;
    if (lastFire != null && at.difference(lastFire) < cooldown) return false;

    _lastFire = at;
    return true;
  }

  /// Forgets the confirming run and the cooldown, so the next shake can fire
  /// immediately.
  void reset() {
    _run = 0;
    _lastFire = null;
  }
}
