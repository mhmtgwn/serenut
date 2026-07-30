import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows installer uses machine-wide install and conditional VC runtime',
      () {
    final script =
        File('windows/installer/serenut_installer.iss').readAsStringSync();

    expect(script, contains('PrivilegesRequired=admin'));
    expect(script, contains('DefaultDirName={autopf}\\Serenut OS'));
    expect(script, contains('Check: NeedsVCRuntime'));
    expect(
      script,
      contains('RegQueryDWordValue('),
    );
  });
}
