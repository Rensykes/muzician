import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_clip_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders a chord label for an existing segment', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(songwriterProvider.notifier);
    s.addSection(label: 'A', lengthBars: 4);
    final secId = c.read(songwriterProvider).sections.single.id;
    s.addLane(sectionId: secId, kind: SongLaneKind.audio);
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    s.addAudioAsset(
      const AudioAsset(
        id: 'a1',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20],
        sourceLabel: 'r',
      ),
    );
    final clipId = s.addAudioClip(assetId: 'a1', durationMs: 4000);
    s.addAudioBlock(
      sectionId: secId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );
    s.addChordSegment(
      clipId: clipId,
      startTick: 0,
      spanTicks: 480,
      chordSymbol: 'C',
      romanNumeral: 'I',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SongwriterAudioClipBody(
                sectionId: secId,
                laneId: laneId,
                clipId: clipId,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('segBeat_0')), findsOneWidget);
    expect(find.text('C'), findsWidgets);
    expect(find.text('I'), findsWidgets);
  });
}
