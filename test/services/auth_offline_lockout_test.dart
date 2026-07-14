import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';

class MockUserRepository implements IUserRepository {
  final Map<String, AuthUser> _usersByUsername = {};
  final Map<String, String> _pinHashes = {};
  final Map<String, int> _failedAttempts = {};
  final Map<String, String?> _lockedUntil = {};

  void registerUser(AuthUser user, String pinHash) {
    _usersByUsername[user.name] = user;
    _pinHashes[user.id] = pinHash;
    _failedAttempts[user.id] = 0;
    _lockedUntil[user.id] = null;
  }

  @override
  Future<AuthUser?> findByBusinessCodeAndUsername(
      String businessCode, String username) async {
    return _usersByUsername[username];
  }

  @override
  Future<Map<String, String?>> getCredentialHashes(String userId) async {
    return {'pin_hash': _pinHashes[userId], 'password_hash': null};
  }

  @override
  Future<Map<String, dynamic>> getFailedPinAttempts(String userId) async {
    return {
      'failed_pin_attempts': _failedAttempts[userId] ?? 0,
      'locked_until': _lockedUntil[userId],
    };
  }

  @override
  Future<void> incrementFailedPinAttempts(String userId,
      {int lockoutMinutes = 5, int maxAttempts = 5}) async {
    final attempts = (_failedAttempts[userId] ?? 0) + 1;
    _failedAttempts[userId] = attempts;
    if (attempts >= maxAttempts) {
      _lockedUntil[userId] = DateTime.now()
          .add(Duration(minutes: lockoutMinutes))
          .toIso8601String();
    }
  }

  @override
  Future<void> resetPinAttempts(String userId) async {
    _failedAttempts[userId] = 0;
    _lockedUntil[userId] = null;
  }

  @override
  Future<void> updateLastLogin(String userId) async {}

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
  group('AuthService Offline Lockout Tests', () {
    late MockUserRepository userRepo;
    late MockHashService hashService;
    late AuthService authService;
    late AuthUser user;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final deviceManager = DeviceManager(prefs);
      userRepo = MockUserRepository();
      hashService = MockHashService();
      authService = AuthService(
        userRepository: userRepo,
        hashService: hashService,
        deviceManager: deviceManager,
        apiClient: null,
      );

      user = AuthUser(
        id: 'user_123',
        name: 'kasiyer',
        email: 'kasiyer@shaman.com',
        role: UserRole.cashier,
        permissions: [],
        createdAt: DateTime.now(),
      );
      userRepo.registerUser(user, 'hashed_1234');
      await authService.initialize();
    });

    test('Successful offline PIN login resets failed attempts', () async {
      // 1. First fail once
      await expectLater(
        authService.loginSubUser('TEST', 'kasiyer', 'wrong_pin'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('Kalan deneme'))),
      );

      final status = await userRepo.getFailedPinAttempts(user.id);
      expect(status['failed_pin_attempts'], 1);

      // 2. Login successfully
      final loggedIn =
          await authService.loginSubUser('TEST', 'kasiyer', '1234');
      expect(loggedIn.id, user.id);

      // 3. Status is reset
      final resetStatus = await userRepo.getFailedPinAttempts(user.id);
      expect(resetStatus['failed_pin_attempts'], 0);
      expect(resetStatus['locked_until'], isNull);
    });

    test(
        'Offline login lockout activates after 5 failed attempts and blocks login',
        () async {
      // Fail 4 times
      for (int i = 0; i < 4; i++) {
        await expectLater(
          authService.loginSubUser('TEST', 'kasiyer', 'wrong'),
          throwsA(isA<AuthException>()
              .having((e) => e.message, 'message', contains('Kalan deneme'))),
        );
      }

      final status4 = await userRepo.getFailedPinAttempts(user.id);
      expect(status4['failed_pin_attempts'], 4);
      expect(status4['locked_until'], isNull);

      // 5th failure -> Lockout
      await expectLater(
        authService.loginSubUser('TEST', 'kasiyer', 'wrong'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('kilitlendi'))),
      );

      final status5 = await userRepo.getFailedPinAttempts(user.id);
      expect(status5['failed_pin_attempts'], 5);
      expect(status5['locked_until'], isNotNull);

      // Subsequent login attempt (even with correct PIN) throws lockout exception
      await expectLater(
        authService.loginSubUser('TEST', 'kasiyer', '1234'),
        throwsA(isA<AuthException>().having((e) => e.message, 'message',
            contains('başarısız deneme nedeniyle kilitlendi'))),
      );
    });
  });
}
