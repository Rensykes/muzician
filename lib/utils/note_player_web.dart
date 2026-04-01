/// Web stub – imported instead of note_player_io.dart on dart.library.html.
/// These functions must never be called at runtime on web because _needsFile
/// is always false there; they exist only to satisfy the compiler.
library;

import 'dart:typed_data';

Future<String> ioTempDir() async => throw UnsupportedError('web');

Future<void> ioWriteIfAbsent(String path, Uint8List bytes) async =>
    throw UnsupportedError('web');
