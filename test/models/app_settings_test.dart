import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/utils/note_utils.dart' show NoteSpelling;

void main() {
  test('theme variant defaults to Studio and both options round-trip', () {
    expect(const AppSettings().themeVariant, AppThemeVariant.studio);

    for (final variant in AppThemeVariant.values) {
      final restored = AppSettings.fromJson(
        const AppSettings().copyWith(themeVariant: variant).toJson(),
      );
      expect(restored.themeVariant, variant);
    }
  });

  test('missing, unknown, or invalid theme variants default to Studio', () {
    final cases = <Map<String, dynamic>>[
      {'noteVolume': 0.4},
      {'themeVariant': 'unknown', 'saveBrowserGrid': true},
      {'themeVariant': 2, 'noteVolume': 0.35},
    ];

    for (final json in cases) {
      final restored = AppSettings.fromJson(json);
      expect(restored.themeVariant, AppThemeVariant.studio);
      if (json.containsKey('saveBrowserGrid')) {
        expect(restored.saveBrowserGrid, true);
      }
      if (json.containsKey('noteVolume')) {
        expect(restored.noteVolume, json['noteVolume']);
      }
    }
  });

  test('copyWith changes theme while preserving other settings', () {
    const original = AppSettings(
      noteVolume: 0.35,
      saveBrowserGrid: true,
      noteSpelling: NoteSpelling.flats,
    );

    final updated = original.copyWith(
      themeVariant: AppThemeVariant.studioMuzician,
    );

    expect(updated.themeVariant, AppThemeVariant.studioMuzician);
    expect(updated.noteVolume, 0.35);
    expect(updated.saveBrowserGrid, true);
    expect(updated.noteSpelling, NoteSpelling.flats);
  });

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
