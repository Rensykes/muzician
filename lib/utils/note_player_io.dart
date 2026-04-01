/// dart:io implementation – imported only on native (iOS/macOS/Android/Linux).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> ioTempDir() async {
  final dir = await getApplicationDocumentsDirectory();
  return dir.path;
}

Future<void> ioWriteIfAbsent(String path, Uint8List bytes) async {
  final file = File(path);
  if (!file.existsSync()) await file.writeAsBytes(bytes);
}
