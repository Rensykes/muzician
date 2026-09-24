import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/generated_file_delivery.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'iOS delivery shares a temporary file and cleans it afterward',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final origin = const Rect.fromLTWH(2, 3, 40, 44);
      ShareParams? sent;
      var deletedPath = '';

      final outcome = await deliverGeneratedFile(
        bytes: bytes,
        fileName: 'song.wav',
        mimeType: 'audio/wav',
        dialogTitle: 'Export song as WAV',
        allowedExtensions: const ['wav'],
        sharePositionOrigin: origin,
        writeTemporaryFile: ({required bytes, required fileName}) async =>
            '/tmp/$fileName',
        deleteTemporaryFile: (path) async => deletedPath = path,
        share: (params) async {
          sent = params;
          return const ShareResult('shared', ShareResultStatus.success);
        },
      );

      expect(outcome, GeneratedFileDeliveryOutcome.shared);
      expect(sent!.sharePositionOrigin, origin);
      expect(sent!.files!.single.path, '/tmp/song.wav');
      expect(sent!.files!.single.mimeType, 'audio/wav');
      expect(sent!.fileNameOverrides, ['song.wav']);
      expect(deletedPath, '/tmp/song.wav');
    },
  );

  test(
    'dismissed mobile share reports cancellation and still cleans up',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var cleaned = false;

      final outcome = await deliverGeneratedFile(
        bytes: Uint8List.fromList([9]),
        fileName: 'song.mzbundle',
        mimeType: 'application/zip',
        dialogTitle: 'Export Song Bundle',
        allowedExtensions: const ['mzbundle'],
        writeTemporaryFile: ({required bytes, required fileName}) async =>
            '/tmp/$fileName',
        deleteTemporaryFile: (_) async => cleaned = true,
        share: (params) async =>
            const ShareResult('', ShareResultStatus.dismissed),
      );

      expect(outcome, GeneratedFileDeliveryOutcome.cancelled);
      expect(cleaned, isTrue);
    },
  );

  test('desktop route saves the byte buffer with its file metadata', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final expectedBytes = Uint8List.fromList([4, 5, 6]);
    Uint8List? savedBytes;
    String? savedName;
    List<String>? savedExtensions;

    final outcome = await deliverGeneratedFile(
      bytes: expectedBytes,
      fileName: 'song.wav',
      mimeType: 'audio/wav',
      dialogTitle: 'Export song as WAV',
      allowedExtensions: const ['wav'],
      saveFile:
          ({
            required bytes,
            required fileName,
            required dialogTitle,
            required allowedExtensions,
          }) async {
            savedBytes = bytes;
            savedName = fileName;
            savedExtensions = allowedExtensions;
            return true;
          },
    );

    expect(outcome, GeneratedFileDeliveryOutcome.saved);
    expect(savedBytes, expectedBytes);
    expect(savedName, 'song.wav');
    expect(savedExtensions, ['wav']);
  });

  test('Web share fallback maps to shared-or-downloaded feedback', () {
    const fallback = ShareResult('unavailable', ShareResultStatus.unavailable);
    const dismissed = ShareResult('', ShareResultStatus.dismissed);

    expect(
      generatedShareOutcome(fallback, isWeb: true),
      GeneratedFileDeliveryOutcome.sharedOrDownloaded,
    );
    expect(
      generatedShareOutcome(dismissed, isWeb: true),
      GeneratedFileDeliveryOutcome.cancelled,
    );
  });
}
