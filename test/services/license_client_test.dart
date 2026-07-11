// test/services/license_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/config/environment.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_client.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

void main() {
  group('CloudLicenseClient Tests', () {
    late ApiClient apiClient;
    late CloudLicenseClient licenseClient;

    setUp(() {
      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      licenseClient = CloudLicenseClient(apiClient);
    });

    test('activate sends request and returns CompanyLicense on success', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"companyId": "c_123", "tier": "PRO", "activeDeviceIds": ["dev_1"], "isActive": true}',
          headers: {},
        );
      };

      final license = await licenseClient.activate('token_abc', 'dev_1');
      expect(license, isNotNull);
      expect(license!.companyId, 'c_123');
      expect(license.tier, LicenseTier.pro);
      expect(license.activeDeviceIds.first, 'dev_1');
      expect(license.isActive, true);
    });

    test('validate checks validation status successfully', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"valid": true}',
          headers: {},
        );
      };

      final isValid = await licenseClient.validate('lic_123');
      expect(isValid, true);
    });

    test('deactivate triggers correctly', () async {
      apiClient.mockHandler = (request) {
        return const ApiResponse(
          statusCode: 200,
          body: '{"deactivated": true}',
          headers: {},
        );
      };

      final isDeactivated = await licenseClient.deactivate('lic_123', 'dev_1');
      expect(isDeactivated, true);
    });
  });
}
