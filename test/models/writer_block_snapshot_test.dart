import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/save_system.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('WriterBlockSnapshot round-trips every Writer lane kind', () {
    for (final laneKind in SongLaneKind.values) {
      final original = WriterBlockSnapshot(laneKind: laneKind);
      final restored = InstrumentSnapshot.fromJson(original.toJson());

      expect(restored, isA<WriterBlockSnapshot>());
      expect((restored as WriterBlockSnapshot).laneKind, laneKind);
    }
  });

  test(
    'WriterBlockSnapshot retains patterns, clip and full audio metadata',
    () {
      const asset = AudioAsset(
        id: 'source',
        durationMs: 1200,
        sampleRate: 44100,
        channels: 2,
        format: 'wav',
        peaks: [1, 4, 2],
        sourceLabel: 'Take 1',
      );
      const stretchedAsset = AudioAsset(
        id: 'stretch',
        durationMs: 1600,
        sampleRate: 44100,
        channels: 2,
        format: 'wav',
        peaks: [3, 2],
        sourceLabel: 'Take 1 (stretched)',
      );
      final original = WriterBlockSnapshot(
        laneKind: SongLaneKind.audio,
        isSilent: true,
        chordSymbol: 'Am',
        chordQuality: 'm',
        chordRootPc: 9,
        chordNotes: const ['A', 'C', 'E'],
        romanNumeral: 'i',
        defaultLyrics: const ['Saved line'],
        drumPattern: const DrumPattern(
          id: 'drum-pattern',
          name: 'Beat',
          lengthTicks: 32,
          lanes: [
            DrumLaneSequence(laneId: DrumLaneId.kick, activeTicks: [0, 8]),
          ],
        ),
        melodyPattern: const NotePattern(
          id: 'melody-pattern',
          name: 'Top line',
          lengthTicks: 16,
          notes: [
            NotePatternNote(
              id: 'n1',
              midiNote: 69,
              startTick: 0,
              durationTicks: 4,
            ),
          ],
          pitchRangeStart: 48,
          pitchRangeEnd: 84,
          snapTicks: 1,
          highlightedNotes: ['A'],
        ),
        guitarStrumPattern: const GuitarStrumPattern(
          id: 'strum-pattern',
          name: 'Down up',
          lengthTicks: 16,
          events: [
            GuitarStrumEvent(tick: 0, direction: GuitarStrumDirection.down),
            GuitarStrumEvent(tick: 8, direction: GuitarStrumDirection.up),
          ],
        ),
        audioClip: const AudioClip(
          id: 'clip',
          assetId: 'source',
          trimStartMs: 100,
          trimEndMs: 900,
          fitMode: AudioFitMode.stretch,
          stretchedAssetId: 'stretch',
          segments: [
            ChordSegment(
              id: 'segment',
              startTick: 0,
              spanTicks: 4,
              chordSymbol: 'Am',
              chordRootPc: 9,
              chordNotes: ['A', 'C', 'E'],
            ),
          ],
        ),
        audioAsset: asset,
        stretchedAudioAsset: stretchedAsset,
      );

      final restored = InstrumentSnapshot.fromJson(original.toJson());

      expect(restored, isA<WriterBlockSnapshot>());
      final writer = restored as WriterBlockSnapshot;
      expect(writer.laneKind, SongLaneKind.audio);
      expect(writer.isSilent, isTrue);
      expect(writer.chordSymbol, 'Am');
      expect(writer.defaultLyrics, ['Saved line']);
      expect(writer.drumPattern?.lanes.single.activeTicks, [0, 8]);
      expect(writer.melodyPattern?.notes.single.midiNote, 69);
      expect(
        writer.guitarStrumPattern?.events.last.direction,
        GuitarStrumDirection.up,
      );
      expect(writer.audioClip?.fitMode, AudioFitMode.stretch);
      expect(writer.audioClip?.segments.single.chordNotes, ['A', 'C', 'E']);
      expect(writer.audioAsset?.toJson(), asset.toJson());
      expect(writer.stretchedAudioAsset?.toJson(), stretchedAsset.toJson());
    },
  );

  test('older WriterBlockSnapshot JSON defaults its lyric seed to empty', () {
    final legacy = WriterBlockSnapshot(
      laneKind: SongLaneKind.harmony,
      chordSymbol: 'C',
    ).toJson()..remove('defaultLyrics');

    final restored = WriterBlockSnapshot.fromJson(legacy);

    expect(restored.defaultLyrics, isEmpty);
  });
}
