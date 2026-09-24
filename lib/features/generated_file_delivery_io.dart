import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> writeShareTempFile({
  required Uint8List bytes,
  required String fileName,
}) async {
  final directory = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File(
    p.join(
      directory.path,
      'muzician_${DateTime.now().microsecondsSinceEpoch}_$safeName',
    ),
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> deleteShareTempFile(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // Temporary share files are best-effort cleanup.
  }
}

Future<bool> saveGeneratedFile({
  required Uint8List bytes,
  required String fileName,
  required String dialogTitle,
  required List<String> allowedExtensions,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );
  if (path == null) return false;
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
