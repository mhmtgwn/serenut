// test/services/auth_offline_lease_test.dart
// Unit tests for Auth Offline Lease Expiration and Stored Session Security

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';

import 'package:serenutos/domain/models/permission.dart';

class MockUserRepository implements IUserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHashService implements IHashService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService — Offline Auth Lease Tests', () {
    test(
        'Offline auth lease rejects a non-empty but unverified stored JWT after expiry',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final user = AuthUser(
        id: 'user-lease-1',
        name: 'Lease Test User',
        email: 'lease@serenutos.com',
        role: UserRole.cashier,
        companyId: 'company-1',
        permissions: const [],
        createdAt: DateTime.now(),
      );

      await prefs.setString('auth_user_json', user.toJson());
      // Set last verified timestamp to 10 days ago (lease is default 7 days)
      final tenDaysAgo =
          DateTime.now().toUtc().subtract(const Duration(days: 10));
      await prefs.setString('serenut_last_authz_verified_at_${user.id}',
          tenDaysAgo.toIso8601String());
      await prefs.setString('auth_jwt_token', 'expired.or.revoked.jwt');

      final authService = AuthService(
        userRepository: MockUserRepository(),
        hashService: MockHashService(),
        deviceManager: DeviceManager(prefs),
      );

      await authService.initialize();

      final currentUser = await authService.getCurrentUser();
      expect(currentUser, isNull,
          reason:
              'A stored bearer token is not valid offline authorization after the lease expires');
      expect(prefs.getString('auth_jwt_token'), isNull);
    });
  });
}
