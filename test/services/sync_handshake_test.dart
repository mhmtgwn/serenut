// test/services/sync_handshake_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/offline_sync_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';

class FakeLicenseService implements LicenseService {
  static SharedPreferences? mockPrefs;

  @override
  SharedPreferences get prefs {
    if (mockPrefs == null) {
      throw StateError('mockPrefs not initialized');
    }
    return mockPrefs!;
  }

  @override
  LicenseInfo? getLicenseInfo() {
    return LicenseInfo(
      merchantId: 'MOCK_MERCHANT',
      allowedDevices: ['*'],
      expiryDate: DateTime.now().add(const Duration(days: 30)),
      tier: LicenseTier.proPlus,
      features: ['cloud_sync'],
      signature: '',
    );
  }

  @override
  String? getLicenseToken() => 'mock_token';

  @override
  bool verifyLicenseToken(String token) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSaleRepository implements ISaleRepository {
  @override
  Future<List<SaleEntity>> findAll() async => [];
  
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Schema Handshake Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FakeLicenseService.mockPrefs = await SharedPreferences.getInstance();
    });

    test('syncPendingSales blocks synchronization when schema versions mismatch', () async {
      // Mock server returning schemaVersion 2 (mismatch with client version 1)
      final mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/updates/check')) {
          return http.Response(
            '{"latest_version": "1.0.0+4", "min_required_version": "1.0.0+1", "is_force_update": false, "download_url": "", "schema_version": 2}',
            200,
          );
        }
        return http.Response('{"status": "ok"}', 200);
      });

      final apiClient = ApiClient(httpClient: mockHttpClient);
      final syncService = OfflineSyncService(
        saleRepository: MockSaleRepository(),
        licenseService: FakeLicenseService(),
        apiClient: apiClient,
      );

      final result = await syncService.syncPendingSales();

      expect(result.synced, equals(0));
      expect(result.failed, equals(0));
      expect(result.success, isTrue); // No sales failed pushing, but errors list contains warning
      expect(result.errors.first, contains('Veritabanı şema uyuşmazlığı tespit edildi'));
    });
  });
}
