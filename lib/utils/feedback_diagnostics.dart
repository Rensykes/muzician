/// Coarse diagnostics attached to in-app feedback.
///
/// Nothing here identifies a user: the value object carries only the app
/// version, platform, operating system, current screen and language.
library;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'feedback_user_agent.dart';

/// The platform details shown with a feedback submission.
class FeedbackDiagnostics {
  const FeedbackDiagnostics({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.screen,
    required this.locale,
  });

  final String appVersion;
  final String platform;
  final String osVersion;
  final String screen;
  final String locale;

  /// The payload sent alongside the feedback text.
  Map<String, Object?> toMap() => <String, Object?>{
    'appVersion': appVersion,
    'platform': platform,
    'osVersion': osVersion,
    'screen': screen,
    'locale': locale,
  };

  /// One line for display: the four visible fields joined by a middle dot.
  String get summary => 'Muzician $appVersion · $osVersion · $screen · $locale';
}

/// The current user agent described coarsely as `<Browser> / <OS>`, or
/// `unknown` when either half cannot be classified.
String describeUserAgent(String? userAgent) {
  final browser = _describeBrowser(userAgent);
  final os = _describeOperatingSystem(userAgent);
  if (browser == null || os == null) return 'unknown';
  return '$browser / $os';
}

String? _describeBrowser(String? userAgent) {
  if (userAgent == null || userAgent.isEmpty) return null;
  // Edge also carries Chrome/ and Safari/ tokens, so it is tested first.
  if (userAgent.contains('Edg/')) return 'Edge';
  if (userAgent.contains('Firefox/')) return 'Firefox';
  if (userAgent.contains('Chrome/')) return 'Chrome';
  if (userAgent.contains('Version/') && userAgent.contains('Safari/')) {
    return 'Safari';
  }
  return null;
}

String? _describeOperatingSystem(String? userAgent) {
  if (userAgent == null || userAgent.isEmpty) return null;
  // iOS user agents also contain "like Mac OS X", so iOS is tested first.
  if (userAgent.contains('iPhone') ||
      userAgent.contains('iPad') ||
      userAgent.contains('iPod')) {
    return 'iOS';
  }
  if (userAgent.contains('Android')) return 'Android';
  if (userAgent.contains('Macintosh') || userAgent.contains('Mac OS X')) {
    return 'macOS';
  }
  if (userAgent.contains('Windows')) return 'Windows';
  if (userAgent.contains('Linux')) return 'Linux';
  return null;
}

/// Whether the platform can open a feedback composer.
bool get isFeedbackAvailable =>
    kIsWeb ||
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

/// The platform name accepted by the feedback rules: always lowercase.
String platformWireName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    // Kept for completeness; neither is reachable from the feedback UI.
    _ => 'linux',
  };
}

/// Captures the diagnostics attached to feedback sent from [screen].
Future<FeedbackDiagnostics> captureDiagnostics({required String screen}) async {
  String appVersion;
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = '${info.version}+${info.buildNumber}';
  } catch (_) {
    appVersion = 'unknown';
  }
  return FeedbackDiagnostics(
    appVersion: appVersion,
    platform: platformWireName(),
    osVersion: kIsWeb
        ? describeUserAgent(currentUserAgent())
        : nativeOperatingSystemVersion(),
    screen: screen,
    locale: PlatformDispatcher.instance.locale.languageCode,
  );
}
