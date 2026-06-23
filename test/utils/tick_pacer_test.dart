import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/tick_pacer.dart';

void main() {
  group('TickPacer', () {
    test('awaitBoundary(n) becomes due at tickDuration * n from start',
        () async {
      final pacer = TickPacer(const Duration(milliseconds: 10));
      final clock = Stopwatch()..start();
      await pacer.awaitBoundary(5); // due at 50ms
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(45));
      expect(clock.elapsedMilliseconds, lessThan(120));
    });

    test('absorbs per-step body cost instead of accumulating it as drift',
        () async {
      // Cost (5ms) exceeds the tick (4ms), so the pacer is always behind. It
      // must return without adding the 4ms wait on top — total tracks the cost
      // (~40ms), not cost + waits (~40 + 32 = 72ms, which a fixed per-tick
      // delay would produce).
      final pacer = TickPacer(const Duration(milliseconds: 4));
      final clock = Stopwatch()..start();
      for (var n = 1; n <= 8; n++) {
        final spin = Stopwatch()..start();
        while (spin.elapsedMilliseconds < 5) {
          // Busy-wait simulating per-tick work.
        }
        await pacer.awaitBoundary(n);
      }
      expect(
        clock.elapsedMilliseconds,
        lessThan(60),
        reason: 'pacer added wait on top of cost: '
            '${clock.elapsedMilliseconds}ms',
      );
    });

    test('adds no wait when already past the requested boundary', () async {
      final pacer = TickPacer(const Duration(milliseconds: 5));
      // Boundary 1 is due at 5ms, but we are already well past it.
      final spin = Stopwatch()..start();
      while (spin.elapsedMilliseconds < 30) {
        // Fall behind on purpose.
      }
      final clock = Stopwatch()..start();
      await pacer.awaitBoundary(1);
      expect(clock.elapsedMilliseconds, lessThan(5));
    });
  });
}
