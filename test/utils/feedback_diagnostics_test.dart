import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/utils/feedback_diagnostics.dart';
import 'package:muzician/utils/feedback_os_label.dart';

void main() {
  test('describes common user agents coarsely', () {
    expect(
      describeUserAgent(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      ),
      'Chrome / macOS',
    );
    expect(
      describeUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 '
        'Safari/604.1',
      ),
      'Safari / iOS',
    );
    expect(describeUserAgent(null), 'unknown');
    expect(describeUserAgent('curl/8.0'), 'unknown');
  });

  test('summary joins the four visible fields with a middle dot', () {
    const d = FeedbackDiagnostics(
      appVersion: '2.0.0+2',
      platform: 'android',
      osVersion: 'Android 14',
      screen: 'settings',
      locale: 'en',
    );
    expect(d.summary, 'Muzician 2.0.0+2 · Android 14 · settings · en');
    expect(
      d.toMap().keys,
      containsAll(<String>[
        'appVersion',
        'platform',
        'osVersion',
        'screen',
        'locale',
      ]),
    );
  });

  test('feedback is available on web, android, ios, macos and windows', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(isFeedbackAvailable, isTrue, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isFeedbackAvailable, isFalse);
  });

  test('platform names are lowercase and stable for the rules', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const wireNames = <TargetPlatform, String>{
      TargetPlatform.android: 'android',
      TargetPlatform.iOS: 'ios',
      TargetPlatform.macOS: 'macos',
      TargetPlatform.windows: 'windows',
    };
    for (final entry in wireNames.entries) {
      debugDefaultTargetPlatformOverride = entry.key;
      expect(platformWireName(), entry.value, reason: '${entry.key}');
    }
  });

  test('native OS labels name the system before the version', () {
    expect(
      describeNativeOs('Version 27.0.1 (Build 24A335)', 'ios'),
      'iOS 27.0.1',
    );
    expect(
      describeNativeOs('Version 15.2 (Build 24C101)', 'macos'),
      'macOS 15.2',
    );
    expect(describeNativeOs('Android 14 (API 34)', 'android'), 'Android 14');
    expect(describeNativeOs('', 'ios'), 'unknown');
    expect(
      describeNativeOs('Windows 11 Pro 10.0.22631', 'windows'),
      'Windows 11',
    );
  });
}
