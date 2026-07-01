import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  String seedClip() {
    final s = c.read(songwriterProvider.notifier);
    s.addSection(label: 'A', lengthBars: 4);
    final secId = c.read(songwriterProvider).sections.single.id;
    s.addLane(sectionId: secId, kind: SongLaneKind.audio);
    return s.addAudioClip(assetId: 'a1', durationMs: 4000);
  }

  test('addChordSegment appends a harmony segment', () {
    final clipId = seedClip();
    final segId = c
        .read(songwriterProvider.notifier)
        .addChordSegment(
          clipId: clipId,
          startTick: 0,
          spanTicks: 480,
          chordSymbol: 'C',
          chordQuality: 'maj',
          chordRootPc: 0,
          chordNotes: const ['C', 'E', 'G'],
          romanNumeral: 'I',
        );
    final clip = c.read(songwriterProvider).audioClips.single;
    expect(clip.segments.single.id, segId);
    expect(clip.segments.single.chordSymbol, 'C');
  });

  test('removeChordSegment drops it', () {
    final clipId = seedClip();
    final segId = c
        .read(songwriterProvider.notifier)
        .addChordSegment(
          clipId: clipId,
          startTick: 0,
          spanTicks: 480,
          saveId: 'x',
        );
    c
        .read(songwriterProvider.notifier)
        .removeChordSegment(clipId: clipId, segmentId: segId);
    expect(c.read(songwriterProvider).audioClips.single.segments, isEmpty);
  });

  test('clampClipSegments removes out-of-span segments', () {
    final clipId = seedClip();
    final n = c.read(songwriterProvider.notifier);
    n.addChordSegment(
      clipId: clipId,
      startTick: 0,
      spanTicks: 480,
      chordSymbol: 'C',
    );
    n.addChordSegment(
      clipId: clipId,
      startTick: 1920,
      spanTicks: 480,
      chordSymbol: 'G',
    );
    n.clampClipSegments(clipId: clipId, spanTotalTicks: 960);
    expect(c.read(songwriterProvider).audioClips.single.segments.length, 1);
  });
}
