/// Native implementation – imported only off web (iOS, Android, macOS, Linux,
/// Windows). Dart:io is safe here because web builds never compile this file.
library;

import 'dart:io';

import 'feedback_os_label.dart';

/// Native builds have no browser user agent.
String? currentUserAgent() => null;

/// `Platform.operatingSystemVersion` labelled with its operating system, so
/// `Android 14 (API 34)` becomes `Android 14` and `Version 27.0.1 (Build …)`
/// becomes `iOS 27.0.1`.
String nativeOperatingSystemVersion() =>
    describeNativeOs(Platform.operatingSystemVersion, Platform.operatingSystem);
