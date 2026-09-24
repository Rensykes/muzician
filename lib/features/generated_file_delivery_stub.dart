import 'dart:typed_data';

Future<String> writeShareTempFile({
  required Uint8List bytes,
  required String fileName,
}) async => throw UnsupportedError('Temporary file sharing requires dart:io');

Future<void> deleteShareTempFile(String path) async {}

Future<bool> saveGeneratedFile({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
}) async => false;
