import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DeviceManager identity migration', () {
    test('preserves the existing license-bound identity', () async {
      SharedPreferences.setMockInitialValues({
        'device_uuid': 'license-bound-device',
        'nutopiano_device_id': 'old-device',
        'sync_v4_device_id': 'old-sync-device',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(DeviceManager(prefs).getDeviceId(), 'license-bound-device');
      expect(prefs.getString('serenut_device_id'), 'license-bound-device');
      expect(prefs.containsKey('device_uuid'), isFalse);
      expect(prefs.containsKey('nutopiano_device_id'), isFalse);
      expect(prefs.containsKey('sync_v4_device_id'), isFalse);
    });

    test('uses a former local ID when no license binding exists', () async {
      SharedPreferences.setMockInitialValues({
        'nutopiano_device_id': 'existing-local-device',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(DeviceManager(prefs).getDeviceId(), 'existing-local-device');
      expect(DeviceManager(prefs).getDeviceId(), 'existing-local-device');
      expect(prefs.getString('serenut_device_id'), 'existing-local-device');
    });

    test('creates a stable Serenut ID for a fresh installation', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final manager = DeviceManager(prefs);

      final id = manager.getDeviceId();
      expect(id, isNotEmpty);
      expect(manager.getDeviceId(), id);
      expect(prefs.getString('serenut_device_id'), id);
    });
  });
}
