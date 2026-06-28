import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/songwriter/songwriter_audio_clip_sheet.dart';
import 'package:muzician/models/song_project.dart';
import 'package:muzician/models/songwriter.dart';
import 'package:muzician/store/songwriter_slice_controller.dart';
import 'package:muzician/store/songwriter_store.dart';

/// Deterministic stand-in for the real (off-thread, disk-backed) slice
/// controller. It yields a fixed set of onsets so the widget test never
/// touches `compute`/the audio repo, keeping marker count + scatter result
/// exact. [detect]/[clear] are no-ops — the onsets are whatever `build`
/// returned.
class _FakeSliceController extends SongwriterSliceController {
  _FakeSliceController(this._onsets);
  final List<int> _onsets;

  @override
  SliceDetectionState build() => SliceDetectionState(onsets: _onsets);

  @override
  void detect({required String clipId, required double sensitivity}) {}

  @override
  void clear() {}
}

void main() {
  testWidgets('slice mode shows markers and scatter creates per-bar tiles', (
    tester,
  ) async {
    // Region = full asset (trim 0..0): 4000ms @ 44100 Hz => 176400 samples.
    // Onsets at 44100 (1000ms => frac 0.25) and 88200 (2000ms => frac 0.5):
    // 2 cuts => 3 regions => bars 0,1,2 within a 4-bar section.
    final container = ProviderContainer(
      overrides: [
        songwriterSliceControllerProvider.overrideWith(
          () => _FakeSliceController(const [44100, 88200]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final store = container.read(songwriterProvider.notifier);
    store.addSection(label: 'A', lengthBars: 4);
    final sectionId = container.read(songwriterProvider).sections.single.id;
    store.addLane(sectionId: sectionId, kind: SongLaneKind.audio);
    final laneId = container
        .read(songwriterProvider)
        .sections
        .single
        .lanes
        .firstWhere((l) => l.kind == SongLaneKind.audio)
        .id;
    // Non-empty peaks => the asset is treated as a recorded WAV, so the Slice
    // toggle is enabled.
    store.addAudioAsset(
      const AudioAsset(
        id: 'a1',
        durationMs: 4000,
        sampleRate: 44100,
        channels: 1,
        format: 'wav',
        peaks: [10, 20, 30, 20, 10],
        sourceLabel: 'rec',
      ),
    );
    final clipId = store.addAudioClip(assetId: 'a1', durationMs: 4000);
    store.addAudioBlock(
      sectionId: sectionId,
      laneId: laneId,
      audioClipId: clipId,
      startBar: 0,
      spanBars: 1,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await tester.pump();

    // Enter slice mode.
    await tester.tap(find.byKey(const Key('clipSliceToggle')));
    await tester.pumpAndSettle();

    // Auto markers from the (faked) onsets appear over the waveform.
    expect(find.byKey(const Key('sliceMarker_0')), findsOneWidget);
    expect(find.byKey(const Key('sliceMarker_1')), findsOneWidget);

    // Scatter to bars: source replaced by one 1-bar audio block per region.
    await tester.tap(find.byKey(const Key('clipScatter')));
    await tester.pumpAndSettle();

    final project = container.read(songwriterProvider);
    final lane = project.sections
        .firstWhere((s) => s.id == sectionId)
        .lanes
        .firstWhere((l) => l.id == laneId);
    final audioBlocks = lane.blocks
        .where((b) => b.audioClipId != null)
        .toList();
    expect(
      audioBlocks.length,
      greaterThan(1),
      reason: 'scatter should replace the single source with multiple slices',
    );
    expect(audioBlocks.length, 3);
    // Original source block is gone; slices land on bars 0,1,2 as 1-bar tiles.
    expect(audioBlocks.any((b) => b.id == 'doesNotMatter'), isFalse);
    final bars = audioBlocks.map((b) => b.startBar).toList()..sort();
    expect(bars, [0, 1, 2]);
    expect(audioBlocks.every((b) => b.spanBars == 1), isTrue);
  });
}
