import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/network/trusted_ca_http_overrides.dart';

void main() {
  test('bundled ISRG root is accepted by the secure HTTP context', () {
    final pem = File('assets/certificates/isrgrootx1.pem').readAsBytesSync();

    expect(() => TrustedCaHttpOverrides(pem), returnsNormally);
    expect(String.fromCharCodes(pem), contains('BEGIN CERTIFICATE'));
  });
}
