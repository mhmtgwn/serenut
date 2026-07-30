import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/device_hardware_profile_service.dart';

class _LicenseService extends LicenseService {
  _LicenseService(super.prefs);

  @override
  LicenseInfo? getLicenseInfo() => LicenseInfo(
        merchantId: 'company-1',
        activationId: 'activation-1',
        deviceId: 'device-hash-1',
        expiryDate: DateTime.now().add(const Duration(days: 30)),
        tier: LicenseTier.basic,
        features: const [],
        signature: 'test',
      );
}

void main() {
  late ApiClient api;
  late DeviceHardwareProfileService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ApiClient();
    api.setJwtToken('jwt');
    service = DeviceHardwareProfileService(
      apiClient: api,
      licenseService: _LicenseService(await SharedPreferences.getInstance()),
    );
  });

  test('restores the profile bound to the active device identity', () async {
    api.mockHandler = (request) {
      final body = jsonDecode((request as http.Request).body) as Map;
      expect(body['device_activation_id'], 'activation-1');
      expect(body['device_id'], 'device-hash-1');
      return const ApiResponse(
        statusCode: 200,
        body:
            '{"profile":[{"id":"printer-1","name":"Fiş","type":"receiptPrinter","connection_type":"embedded","configuration":{},"enabled":true,"status":"ready"}]}',
        headers: {},
      );
    };

    final devices = await service.restore();
    expect(devices, hasLength(1));
    expect(devices.single.connectionType, HardwareConnectionType.embedded);
  });

  test('removes secret fields before cloud backup', () async {
    api.mockHandler = (request) {
      final body = jsonDecode((request as http.Request).body) as Map;
      final profile = body['profile'] as List;
      final config = (profile.single as Map)['configuration'] as Map;
      expect(config['host'], '10.0.0.2');
      expect(config.containsKey('password'), isFalse);
      expect(config.containsKey('pin'), isFalse);
      return const ApiResponse(statusCode: 200, body: '{}', headers: {});
    };

    await service.backup(const [
      HardwareDevice(
        id: 'pos-1',
        name: 'POS',
        type: HardwareDeviceType.paymentTerminal,
        connectionType: HardwareConnectionType.tcp,
        configuration: {
          'host': '10.0.0.2',
          'password': 'never-upload',
          'pin': '1234',
        },
      ),
    ]);
  });
}
