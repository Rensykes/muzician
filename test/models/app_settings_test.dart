import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;

void main() {
  test('saveBrowserGrid defaults to false and round-trips', () {
    const s = AppSettings();
    expect(s.saveBrowserGrid, false);

    final json = s.copyWith(saveBrowserGrid: true).toJson();
    final back = AppSettings.fromJson(json);
    expect(back.saveBrowserGrid, true);
  });

  test('note spelling defaults to sharps and round-trips', () {
    const defaults = AppSettings();
    expect(defaults.noteSpelling, NoteSpelling.sharps);

    final restored = AppSettings.fromJson(
      defaults.copyWith(noteSpelling: NoteSpelling.flats).toJson(),
    );
    expect(restored.noteSpelling, NoteSpelling.flats);
  });

  test('missing or unknown spelling falls back to sharps', () {
    expect(AppSettings.fromJson(const {}).noteSpelling, NoteSpelling.sharps);
    expect(
      AppSettings.fromJson(const {
        'noteSpelling': 'doubleAccidentals',
      }).noteSpelling,
      NoteSpelling.sharps,
    );
  });

  test('last content workspace defaults to Writer and round-trips', () {
    const defaults = AppSettings();
    expect(defaults.lastContentWorkspace, isNull);

    final restored = AppSettings.fromJson(
      defaults.copyWith(lastContentWorkspace: () => 'piano').toJson(),
    );
    expect(restored.lastContentWorkspace, 'piano');
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
