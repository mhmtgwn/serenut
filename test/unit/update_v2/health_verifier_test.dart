// test/unit/update_v2/health_verifier_test.dart
// Serenut Platform — Post-Install Health Verifier Unit Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/services/update_v2/health_verifier_service.dart';

class MockSqliteCheck implements SqliteHealthCheck {
  bool isHealthy = true;
  @override
  Future<bool> verifyIntegrity() async => isHealthy;
}

class MockNetworkCheck implements NetworkHealthCheck {
  bool isHealthy = true;
  @override
  Future<bool> verifyVpsConnection() async => isHealthy;
}

class MockUiCheck implements UiHealthCheck {
  bool isHealthy = true;
  @override
  Future<bool> verifyUiInitialized() async => isHealthy;
}

void main() {
  group('HealthVerifierService Tests', () {
    late MockSqliteCheck sqliteCheck;
    late MockNetworkCheck networkCheck;
    late MockUiCheck uiCheck;
    late HealthVerifierService verifier;

    setUp(() {
      sqliteCheck = MockSqliteCheck();
      networkCheck = MockNetworkCheck();
      uiCheck = MockUiCheck();
      verifier = HealthVerifierService(
        sqliteCheck: sqliteCheck,
        networkCheck: networkCheck,
        uiCheck: uiCheck,
      );
    });

    test('Passes health evaluation when all steps succeed (score = 1.0)', () async {
      final healthy = await verifier.evaluateHealth();
      expect(healthy, isTrue);
    });

    test('Fails health evaluation when network VPS check fails (score = 0.80 < 0.95)', () async {
      networkCheck.isHealthy = false;
      final healthy = await verifier.evaluateHealth();
      expect(healthy, isFalse);
    });
  });
}
