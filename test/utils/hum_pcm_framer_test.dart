import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/hum_to_midi.dart';
import 'package:muzician/schema/rules/mono_pitch_rules.dart' as rules;
import 'package:muzician/utils/hum_pcm_framer.dart';

import '../support/hum_signal.dart';

List<PitchFrame> _frames(
  List<HumNote> notes, {
  required int totalMs,
  double noise = 0,
  int chunkBytes = 1000,
}) {
  final pcm = toPcm16(
    renderHum(notes, totalMs: totalMs, noiseAmplitude: noise),
  );
  final framer = HumPcmFramer();
  final frames = <PitchFrame>[];
  // Odd chunk size also exercises byte carry-over.
  for (var i = 0; i < pcm.length; i += chunkBytes) {
    final end = i + chunkBytes > pcm.length ? pcm.length : i + chunkBytes;
    frames.addAll(framer.addPcm16(pcm.sublist(i, end)));
  }
  return frames;
}

void main() {
  test('emits a frame every 16 ms with window-start timestamps', () {
    final frames = _frames([HumNote(midiToHz(60), 0, 500)], totalMs: 500);
    expect(frames.first.timestampMs, 0);
    expect(frames[1].timestampMs, 16);
  });

  test('C4 E4 G4 with gaps becomes three notes with accurate onsets', () {
    final notes = [
      HumNote(midiToHz(60), 200, 700),
      HumNote(midiToHz(64), 800, 1300),
      HumNote(midiToHz(67), 1400, 1900),
    ];
    final frames = _frames(notes, totalMs: 2200, chunkBytes: 999);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected.map((n) => n.midiNote), [60, 64, 67]);
    for (var i = 0; i < 3; i++) {
      expect((detected[i].startMs - notes[i].startMs).abs(), lessThan(80));
    }
  });

  test('moderate room noise creates no extra notes', () {
    final notes = [
      HumNote(midiToHz(60), 600, 1100),
      HumNote(midiToHz(64), 1200, 1700),
    ];
    final frames = _frames(notes, totalMs: 2000, noise: 0.04);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected.map((n) => n.midiNote), [60, 64]);
  });

  test('repeated same-pitch notes with a short rest stay separate', () {
    final notes = [
      HumNote(midiToHz(60), 100, 500),
      HumNote(midiToHz(60), 640, 1040),
    ];
    final frames = _frames(notes, totalMs: 1200);
    final detected = rules.segmentStableNotes(
      frames,
      sensitivity: rules.HumSensitivity.balanced,
    );
    expect(detected, hasLength(2));
  });
}
