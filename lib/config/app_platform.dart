import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Central platform identifiers shared with the API and update services.
///
/// Keep this mapping in one place so iOS never falls through to Windows.
abstract final class AppPlatform {
  static String get releaseKey {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String get deviceLabel {
    switch (releaseKey) {
      case 'android':
        return 'Android POS';
      case 'ios':
        return 'iOS POS';
      case 'windows':
        return 'Windows POS';
      case 'macos':
        return 'macOS POS';
      case 'linux':
        return 'Linux POS';
      case 'web':
        return 'Web POS';
      default:
        return 'POS Cihazı';
    }
  }

  static String updateFileExtension(String platform) {
    switch (platform) {
      case 'android':
        return '.apk';
      case 'ios':
        return '.ipa';
      case 'windows':
        return '.exe';
      default:
        return '';
    }
  }
}
