import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:path/path.dart';

class MockUserRepository implements IUserRepository {
  AuthUser? cachedUser;

  @override
  Future<void> insertUser(
    AuthUser user,
    String passwordHash, {
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  }) async {
    cachedUser = user;
  }

  @override
  Future<void> updateUserFields(
    AuthUser user, {
    bool? isActive,
    String? passwordHash,
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  }) async {
    cachedUser = user;
  }

  @override
  Future<AuthUser?> findByUsername(String username) async => cachedUser;

  @override
  Future<List<AuthUser>> findAll() async => cachedUser != null ? [cachedUser!] : [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHashService implements IHashService {
  @override
  String hashPassword(String password) => 'hashed_$password';

  @override
  bool verifyPassword(String password, String hash) => hash == 'hashed_$password';

  @override
  bool isLegacyHash(String hash) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Online User Sync Tests', () {
    late MockUserRepository userRepo;
    late MockHashService hashService;
    late ApiClient apiClient;
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userRepo = MockUserRepository();
      hashService = MockHashService();
      apiClient = ApiClient();
      authService = AuthService(
        userRepository: userRepo,
        hashService: hashService,
        apiClient: apiClient,
      );
      await authService.initialize();
    });

    test('Logs out user if deactivated on backend', () async {
      // Mock login first
      final user = AuthUser(
        id: 'user_deactivate',
        name: 'kasiyer',
        email: 'kasiyer@shaman.com',
        role: UserRole.cashier,
        permissions: [],
        createdAt: DateTime.now(),
      );
      await authService.setCurrentUser(user);
      apiClient.setJwtToken('valid_token');

      // Mock deactivated response for /auth/me
      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/auth/me')) {
          return ApiResponse(
            statusCode: 200,
            body: '{"user": {"id": "user_deactivate", "is_active": false, "roles": ["cashier"]}}',
            headers: const {},
          );
        }
        return ApiResponse(statusCode: 400, body: '{}', headers: const {});
      };

      bool sessionExpiredTriggered = false;
      authService.onSessionExpiredCallback = () {
        sessionExpiredTriggered = true;
      };

      await authService.checkCurrentUserSessionOnline();

      expect(sessionExpiredTriggered, true);
      expect(await authService.getCurrentUser(), null);
    });

    test('Updates user role and triggers callback if role changes on backend', () async {
      final user = AuthUser(
        id: 'user_upgrade',
        name: 'kasiyer',
        email: 'kasiyer@shaman.com',
        role: UserRole.cashier,
        permissions: [],
        createdAt: DateTime.now(),
      );
      await authService.setCurrentUser(user);
      apiClient.setJwtToken('valid_token');

      // Mock updated manager response for /auth/me
      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/auth/me')) {
          return ApiResponse(
            statusCode: 200,
            body: '{"user": {"id": "user_upgrade", "is_active": true, "roles": ["manager"]}}',
            headers: const {},
          );
        }
        return ApiResponse(statusCode: 400, body: '{}', headers: const {});
      };

      AuthUser? updatedUserCallbackPayload;
      authService.onUserUpdatedCallback = (updatedUser) {
        updatedUserCallbackPayload = updatedUser;
      };

      await authService.checkCurrentUserSessionOnline();

      expect(updatedUserCallbackPayload, isNotNull);
      expect(updatedUserCallbackPayload!.role, UserRole.manager);
      expect(await authService.getCurrentUser(), isNotNull);
      expect((await authService.getCurrentUser())!.role, UserRole.manager);
    });
  });
}
