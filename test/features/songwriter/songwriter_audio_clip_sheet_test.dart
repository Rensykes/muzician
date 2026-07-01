import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_clip_sheet.dart';
import 'package:muzician/store/songwriter_store.dart';

void main() {
  testWidgets('fit toggle updates the clip fit mode', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final store = c.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 4);
    final sectionId = c.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = c
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    store.addAudioAsset(
      const AudioAsset(
        id: 'a1',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30],
        sourceLabel: 'r',
      ),
    );
    final clipId = store.addAudioClip(assetId: 'a1', durationMs: 4000);
    store.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 2,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioClipBody(
              sectionId: sectionId,
              laneId: laneId,
              clipId: clipId,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('clipFit_oneShot')));
    await tester.pump();
    expect(
      c.read(songwriterProvider).audioClips.single.fitMode,
      AudioFitMode.oneShot,
    );
  });
}
