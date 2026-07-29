import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/app_platform.dart';

void main() {
  group('AppPlatform update file extensions', () {
    test('keeps Android, iOS, and Windows artifacts distinct', () {
      expect(AppPlatform.updateFileExtension('android'), '.apk');
      expect(AppPlatform.updateFileExtension('ios'), '.ipa');
      expect(AppPlatform.updateFileExtension('windows'), '.exe');
    });

    test('does not treat an unknown platform as Windows', () {
      expect(AppPlatform.updateFileExtension('unknown'), isEmpty);
    });
  });
}
