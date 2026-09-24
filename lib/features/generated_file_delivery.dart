/// Shared delivery path for generated WAV, bundle, and recovery files.
library;

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'generated_file_delivery_stub.dart'
    if (dart.library.io) 'generated_file_delivery_io.dart'
    as platform;

enum GeneratedFileDeliveryOutcome {
  shared,
  sharedOrDownloaded,
  saved,
  cancelled,
}

typedef ShareGeneratedFile = Future<ShareResult> Function(ShareParams params);
typedef WriteShareTempFile =
    Future<String> Function({
      required Uint8List bytes,
      required String fileName,
    });
typedef DeleteShareTempFile = Future<void> Function(String path);
typedef SaveGeneratedFile =
    Future<bool> Function({
      required Uint8List bytes,
      required String fileName,
      required String dialogTitle,
      required List<String> allowedExtensions,
    });

/// Shares on Android/iOS, saves through a path picker on desktop, and uses
/// share_plus's Web Share API with its download fallback on Web.
Future<GeneratedFileDeliveryOutcome> deliverGeneratedFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String dialogTitle,
  required List<String> allowedExtensions,
  Rect? sharePositionOrigin,
  ShareGeneratedFile? share,
  WriteShareTempFile? writeTemporaryFile,
  DeleteShareTempFile? deleteTemporaryFile,
  SaveGeneratedFile? saveFile,
}) async {
  final useShareSheet =
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (useShareSheet) {
    final tempPath = kIsWeb
        ? null
        : await (writeTemporaryFile ?? platform.writeShareTempFile)(
            bytes: bytes,
            fileName: fileName,
          );
    try {
      final result = await (share ?? SharePlus.instance.share)(
        ShareParams(
          title: dialogTitle,
          subject: dialogTitle,
          sharePositionOrigin: sharePositionOrigin,
          files: [
            if (tempPath != null)
              XFile(tempPath, mimeType: mimeType, name: fileName)
            else
              XFile.fromData(bytes, mimeType: mimeType, name: fileName),
          ],
          fileNameOverrides: [fileName],
          downloadFallbackEnabled: kIsWeb,
        ),
      );
      return generatedShareOutcome(result, isWeb: kIsWeb);
    } finally {
      if (tempPath != null) {
        await (deleteTemporaryFile ?? platform.deleteShareTempFile)(tempPath);
      }
    }
  }

  final saved = await (saveFile ?? platform.saveGeneratedFile)(
    bytes: bytes,
    fileName: fileName,
    dialogTitle: dialogTitle,
    allowedExtensions: allowedExtensions,
  );
  return saved
      ? GeneratedFileDeliveryOutcome.saved
      : GeneratedFileDeliveryOutcome.cancelled;
}

GeneratedFileDeliveryOutcome generatedShareOutcome(
  ShareResult result, {
  required bool isWeb,
}) {
  if (result.status == ShareResultStatus.dismissed) {
    return GeneratedFileDeliveryOutcome.cancelled;
  }
  return isWeb
      ? GeneratedFileDeliveryOutcome.sharedOrDownloaded
      : GeneratedFileDeliveryOutcome.shared;
}

String generatedFileDeliveryFeedback(GeneratedFileDeliveryOutcome outcome) =>
    switch (outcome) {
      GeneratedFileDeliveryOutcome.shared => 'File shared.',
      GeneratedFileDeliveryOutcome.sharedOrDownloaded =>
        'File shared or downloaded.',
      GeneratedFileDeliveryOutcome.saved => 'File saved.',
      GeneratedFileDeliveryOutcome.cancelled => '',
    };
