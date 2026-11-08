/// Native implementation – imported only off web (iOS, Android, macOS, Linux,
/// Windows). Dart:io is safe here because web builds never compile this file.
library;

import 'dart:io';

/// Native builds have no browser user agent.
String? currentUserAgent() => null;

/// `Platform.operatingSystemVersion` trimmed to its first two tokens, so
/// `Android 14 (API 34)` becomes `Android 14`.
String nativeOperatingSystemVersion() {
  final tokens = Platform.operatingSystemVersion.trim().split(RegExp(r'\s+'));
  if (tokens.first.isEmpty) return 'unknown';
  return tokens.take(2).join(' ');
}
