import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';

class MockUserRepository implements IUserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHashService implements IHashService {
  @override
  String hashPassword(String password) => 'hashed_$password';

  @override
  bool verifyPassword(String password, String hash) =>
      hash == 'hashed_$password';

  @override
  bool isLegacyHash(String hash) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    authService = AuthService(
      userRepository: MockUserRepository(),
      hashService: MockHashService(),
      deviceManager: DeviceManager(prefs),
    );
    await authService.initialize();
  });

  group('AuthService - Remember Me & Logout Reason Tests', () {
    test('Remember Me saves and retrieves credentials correctly', () async {
      expect(authService.isRememberMeEnabled(), isTrue);
      expect(authService.getRememberedUsername(), isNull);
      expect(authService.getRememberedPassword(), isNull);

      // Save credentials
      await authService.saveRememberedCredentials(
        username: 'admin@serenut.com',
        password: 'secretPassword123',
        rememberMe: true,
      );

      expect(authService.isRememberMeEnabled(), isTrue);
      expect(authService.getRememberedUsername(), 'admin@serenut.com');
      expect(authService.getRememberedPassword(), 'secretPassword123');

      // Clear credentials
      await authService.clearRememberedCredentials();
      expect(authService.isRememberMeEnabled(), isFalse);
      expect(authService.getRememberedUsername(), isNull);
      expect(authService.getRememberedPassword(), isNull);
    });

    test('Logout reason is recorded and stored with history', () async {
      expect(authService.getLastLogoutReason(), isNull);
      expect(authService.getLogoutHistory(), isEmpty);

      // Record a session expiration
      await authService.recordLogoutReason(
        'Oturum süresi doldu.',
        code: 'API_SESSION_EXPIRED',
        details: 'HTTP 401 on /users/me',
      );

      expect(authService.getLastLogoutReason(), 'Oturum süresi doldu.');
      expect(authService.getLastLogoutCode(), 'API_SESSION_EXPIRED');
      expect(authService.getLastLogoutDetails(), 'HTTP 401 on /users/me');
      expect(authService.getLastLogoutTime(), isNotNull);

      final history = authService.getLogoutHistory();
      expect(history.length, 1);
      expect(history.first['reason'], 'Oturum süresi doldu.');
      expect(history.first['code'], 'API_SESSION_EXPIRED');

      // Record another logout (manual)
      await authService.recordLogoutReason(
        'Kullanıcı isteğiyle çıkış yapıldı.',
        code: 'MANUAL_LOGOUT',
      );

      expect(authService.getLastLogoutReason(), 'Kullanıcı isteğiyle çıkış yapıldı.');
      expect(authService.getLastLogoutCode(), 'MANUAL_LOGOUT');
      expect(authService.getLogoutHistory().length, 2);

      // Clear reason
      await authService.clearLastLogoutReason();
      expect(authService.getLastLogoutReason(), isNull);
      // History should still be preserved for inspection
      expect(authService.getLogoutHistory().length, 2);
    });

    test('triggerSessionExpired calls logout and onSessionExpiredCallback with reason', () async {
      String? receivedReason;
      authService.onSessionExpiredCallback = (reason) {
        receivedReason = reason;
      };

      await authService.triggerSessionExpired(
        'Sunucu oturumu yetkilendirilemedi (HTTP 401).',
        code: 'SERVER_REJECTED_401',
      );

      expect(receivedReason, 'Sunucu oturumu yetkilendirilemedi (HTTP 401).');
      expect(authService.getLastLogoutReason(), 'Sunucu oturumu yetkilendirilemedi (HTTP 401).');
      expect(authService.getLastLogoutCode(), 'SERVER_REJECTED_401');
    });
  });
}
