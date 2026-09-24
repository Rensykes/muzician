import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveRecoveryFile({
  required Uint8List bytes,
  required String fileName,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export recovery data',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (path == null) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
