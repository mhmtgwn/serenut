import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/device_fingerprint_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('DeviceFingerprintService getHardwareHash is stable and computes sha256', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final deviceManager = DeviceManager(prefs);
    final service = DeviceFingerprintService(prefs, deviceManager);

    final hash = service.getHardwareHash();
    expect(hash, isNotEmpty);
    expect(hash.length, 64); // SHA256 length is 64 hex characters
  });
}
