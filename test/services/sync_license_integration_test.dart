// test/services/sync_license_integration_test.dart
// Integration tests for Sync & License/Activation Chain

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Sync & License Activation Chain Integration Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('LicenseService single source initialization resolves device UUID', () {
      final licenseService = LicenseService(prefs);
      final uuid = licenseService.getDeviceUuid();
      expect(uuid, isNotEmpty);
      expect(licenseService.getLicenseInfo(), isNull);
    });

    test('SyncV4Service throws active_device_activation_required when unactivated', () async {
      final licenseService = LicenseService(prefs);
      final syncService = SyncV4Service(
        ApiClient(),
        licenseService: licenseService,
      );

      expect(
        () async => await syncService.sync(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('active_device_activation_required'),
        )),
      );
    });
  });
}
