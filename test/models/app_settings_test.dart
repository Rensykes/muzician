import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  test('saveBrowserGrid defaults to false and round-trips', () {
    const s = AppSettings();
    expect(s.saveBrowserGrid, false);

    final json = s.copyWith(saveBrowserGrid: true).toJson();
    final back = AppSettings.fromJson(json);
    expect(back.saveBrowserGrid, true);
  });

  test('missing saveBrowserGrid in stored json falls back to false', () {
    final back = AppSettings.fromJson(<String, dynamic>{});
    expect(back.saveBrowserGrid, false);
  });

  test('record-monitor fields default OFF', () {
    const s = AppSettings();
    expect(s.recordMonitorBacking, isFalse);
    expect(s.recordMonitorMetronome, isFalse);
    expect(s.recordCountIn, isFalse);
  });

  test('record-monitor fields survive json round-trip', () {
    const s = AppSettings(
      recordMonitorBacking: true,
      recordMonitorMetronome: true,
      recordCountIn: true,
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.recordMonitorBacking, isTrue);
    expect(back.recordMonitorMetronome, isTrue);
    expect(back.recordCountIn, isTrue);
  });

  test('legacy json without the fields defaults them OFF', () {
    final back = AppSettings.fromJson(const {'metronomeEnabled': true});
    expect(back.recordMonitorBacking, isFalse);
    expect(back.recordMonitorMetronome, isFalse);
    expect(back.recordCountIn, isFalse);
  });
}
