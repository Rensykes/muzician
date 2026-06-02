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
}
