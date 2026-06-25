import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/features/songwriter/songwriter_audio_lane_row.dart';

void main() {
  testWidgets('renders a clip tile for an audio block', (tester) async {
    const section = SongSection(
      id: 'sec',
      lengthBars: 4,
      order: 0,
      lanes: [
        SongLane(
          id: 'ln',
          kind: SongLaneKind.audio,
          order: 0,
          blocks: [
            SongBlock(id: 'bl', startBar: 0, spanBars: 2, audioClipId: 'c1'),
          ],
        ),
      ],
    );
    const clip = AudioClip(id: 'c1', assetId: 'a1', trimEndMs: 4000);
    const asset = AudioAsset(
      id: 'a1',
      durationMs: 4000,
      sampleRate: 44100,
      channels: 1,
      format: 'wav',
      peaks: [10, 20, 30],
      sourceLabel: 'Recording',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioLaneRow(
              section: section,
              lane: section.lanes.single,
              instanceIndex: 0,
              clipsById: const {'c1': clip},
              assetsById: const {'a1': asset},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sheetAudioTile_c1')), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
  });

  testWidgets('renders an empty tappable cell when no block', (tester) async {
    const section = SongSection(
      id: 'sec',
      lengthBars: 2,
      order: 0,
      lanes: [SongLane(id: 'ln', kind: SongLaneKind.audio, order: 0)],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SongwriterAudioLaneRow(
              section: section,
              lane: section.lanes.single,
              instanceIndex: 0,
              clipsById: const {},
              assetsById: const {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sheetAudioEmpty_ln_0')), findsOneWidget);
  });
}
