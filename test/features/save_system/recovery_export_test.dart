import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/save_system/recovery_export.dart';
import 'package:muzician/store/persisted_data_recovery_store.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test('recovery export bytes preserve the original JSON string', () {
    const raw = '{  "note": "café 🎸" }\n';
    const backup = DataRecoveryBackup(
      storageKey: '${dataRecoveryStoragePrefix}entry',
      sourceKey: '@muzician/songwriter_sessions/v1',
      raw: raw,
    );

    expect(recoveryBackupBytes(backup), utf8.encode(raw));
  });

  test(
    'share filenames include sanitized source and unique backup id',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const first = DataRecoveryBackup(
        storageKey: '${dataRecoveryStoragePrefix}backup-one:0:c291cmNl',
        sourceKey: '@muzician/song_sessions/v1',
        raw: '{"one":1}',
      );
      const second = DataRecoveryBackup(
        storageKey: '${dataRecoveryStoragePrefix}backup-two:1:c291cmNl',
        sourceKey: '@muzician/song_sessions/v1',
        raw: '{"two":2}',
      );
      final origin = Rect.fromLTWH(10, 20, 30, 40);
      ShareParams? firstParams;
      ShareParams? secondParams;

      final firstOutcome = await exportRecoveryBackup(
        first,
        sharePositionOrigin: origin,
        writeTemporaryFile: ({required bytes, required fileName}) async =>
            '/tmp/$fileName',
        deleteTemporaryFile: (_) async {},
        share: (params) async {
          firstParams = params;
          return const ShareResult('shared', ShareResultStatus.success);
        },
      );
      final secondOutcome = await exportRecoveryBackup(
        second,
        writeTemporaryFile: ({required bytes, required fileName}) async =>
            '/tmp/$fileName',
        deleteTemporaryFile: (_) async {},
        share: (params) async {
          secondParams = params;
          return const ShareResult('shared', ShareResultStatus.success);
        },
      );

      expect(firstOutcome, RecoveryExportOutcome.shared);
      expect(secondOutcome, RecoveryExportOutcome.shared);
      expect(firstParams!.sharePositionOrigin, origin);
      expect(
        firstParams!.fileNameOverrides!.single,
        contains('_muzician_song_sessions_v1'),
      );
      expect(firstParams!.fileNameOverrides!.single, contains('backup-one'));
      expect(secondParams!.fileNameOverrides!.single, contains('backup-two'));
      expect(
        firstParams!.fileNameOverrides!.single,
        isNot(secondParams!.fileNameOverrides!.single),
      );
    },
  );

  test('share feedback follows dismissal and Web fallback outcomes', () {
    const dismissed = ShareResult('', ShareResultStatus.dismissed);
    const unavailable = ShareResult(
      'unavailable',
      ShareResultStatus.unavailable,
    );

    expect(
      recoveryShareOutcome(dismissed, isWeb: false),
      RecoveryExportOutcome.cancelled,
    );
    expect(
      recoveryShareOutcome(dismissed, isWeb: true),
      RecoveryExportOutcome.cancelled,
    );
    expect(
      recoveryShareOutcome(unavailable, isWeb: true),
      RecoveryExportOutcome.sharedOrDownloaded,
    );
    expect(
      recoveryExportFeedback(RecoveryExportOutcome.sharedOrDownloaded),
      'Recovery JSON shared or downloaded.',
    );
  });
}
