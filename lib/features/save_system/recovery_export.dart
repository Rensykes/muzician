import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

import '../generated_file_delivery.dart';
import '../../store/persisted_data_recovery_store.dart';

enum RecoveryExportOutcome { shared, sharedOrDownloaded, saved, cancelled }

/// Exports the original stored string as UTF-8 bytes without JSON rewriting.
Future<RecoveryExportOutcome> exportRecoveryBackup(
  DataRecoveryBackup backup, {
  Rect? sharePositionOrigin,
  ShareGeneratedFile? share,
  WriteShareTempFile? writeTemporaryFile,
  DeleteShareTempFile? deleteTemporaryFile,
}) async {
  final bytes = recoveryBackupBytes(backup);
  final fileName = _fileNameFor(backup);
  final outcome = await deliverGeneratedFile(
    bytes: bytes,
    fileName: fileName,
    mimeType: 'application/json',
    dialogTitle: 'Export recovery data',
    allowedExtensions: const ['json'],
    sharePositionOrigin: sharePositionOrigin,
    share: share,
    writeTemporaryFile: writeTemporaryFile,
    deleteTemporaryFile: deleteTemporaryFile,
  );
  return switch (outcome) {
    GeneratedFileDeliveryOutcome.shared => RecoveryExportOutcome.shared,
    GeneratedFileDeliveryOutcome.sharedOrDownloaded =>
      RecoveryExportOutcome.sharedOrDownloaded,
    GeneratedFileDeliveryOutcome.saved => RecoveryExportOutcome.saved,
    GeneratedFileDeliveryOutcome.cancelled => RecoveryExportOutcome.cancelled,
  };
}

Uint8List recoveryBackupBytes(DataRecoveryBackup backup) =>
    Uint8List.fromList(utf8.encode(backup.raw));

RecoveryExportOutcome recoveryShareOutcome(
  ShareResult result, {
  required bool isWeb,
}) {
  if (result.status == ShareResultStatus.dismissed) {
    return RecoveryExportOutcome.cancelled;
  }
  // share_plus returns `unavailable` both when Web Share succeeds without a
  // result and when its download fallback completes, so the truthful feedback
  // describes both outcomes.
  return isWeb
      ? RecoveryExportOutcome.sharedOrDownloaded
      : RecoveryExportOutcome.shared;
}

String recoveryExportFeedback(RecoveryExportOutcome outcome) =>
    switch (outcome) {
      RecoveryExportOutcome.shared => 'Recovery JSON shared.',
      RecoveryExportOutcome.sharedOrDownloaded =>
        'Recovery JSON shared or downloaded.',
      RecoveryExportOutcome.saved => 'Recovery JSON exported.',
      RecoveryExportOutcome.cancelled => '',
    };

String _fileNameFor(DataRecoveryBackup backup) {
  final safeSource = backup.sourceKey.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]'),
    '_',
  );
  final safeId = backup.backupId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'muzician-recovery-$safeSource-$safeId.json';
}
