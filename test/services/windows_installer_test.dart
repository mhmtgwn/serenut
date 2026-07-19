import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows updates do not launch the elevated VC++ redistributable', () {
    final script = File('windows/installer/serenut_installer.iss').readAsStringSync();

    expect(script, contains('PrivilegesRequired=lowest'));
    expect(script, contains('Check: NeedsVCRuntime'));
    expect(
      script,
      contains("FileExists(ExpandConstant('{app}\\serenutos.exe'))"),
    );
  });
}
