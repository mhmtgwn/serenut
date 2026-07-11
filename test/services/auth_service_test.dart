// test/services/auth_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/config/environment.dart';

class MockUserRepository implements IUserRepository {
  final Map<String, AuthUser> _users = {};
  final Map<String, String> _hashes = {};

  void addUser(AuthUser user, String passwordHash) {
    _users[user.email] = user;
    _users[user.name] = user;
    _hashes[user.id] = passwordHash;
  }

  @override
  Future<AuthUser?> findByUsername(String username) async {
    return _users[username];
  }

  @override
  Future<String?> getPasswordHash(String userId) async {
    return _hashes[userId];
  }

  @override
  Future<void> updateLastLogin(String userId) async {}

  @override
  Future<void> createUser(AuthUser user, String passwordHash) async {}

  @override
  Future<void> updatePasswordHash(String userId, String newHash) async {}

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
  group('AuthService JWT Integration Tests', () {
    late MockUserRepository userRepo;
    late MockHashService hashService;
    late ApiClient apiClient;
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userRepo = MockUserRepository();
      hashService = MockHashService();
      apiClient = ApiClient(config: EnvironmentConfig.fromEnv(AppEnvironment.test));
      authService = AuthService(
        userRepository: userRepo,
        hashService: hashService,
        apiClient: apiClient,
      );

      final user = AuthUser(
        id: 'admin_id',
        name: 'Admin User',
        email: 'admin@serenut.com',
        role: UserRole.admin,
        permissions: [],
        createdAt: DateTime.now(),
      );
      userRepo.addUser(user, 'hashed_admin123');
      await authService.initialize();
    });

    test('Attaches JWT token to ApiClient on login', () async {
      expect(apiClient.send('GET', '/dummy').then((res) => res.headers['Authorization']), throwsA(anything)); // Expect fail because no mock handler yet

      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/auth/login')) {
          return ApiResponse(
            statusCode: 200,
            body: '{"access_token": "jwt_mock_admin_id_xyz", "refresh_token": "mock_refresh", "user": {"id": "admin_id", "name": "Admin User", "email": "admin@serenut.com", "role": "admin"}}',
            headers: const {},
          );
        }
        return ApiResponse(
          statusCode: 200,
          body: '{"auth_header": "${request.headers['Authorization']}"}',
          headers: const {},
        );
      };

      // Perform login
      await authService.login('admin@serenut.com', 'admin123');

      // JWT should be generated and set on client
      final response = await apiClient.get('/dummy');
      expect(response.json['auth_header'], startsWith('Bearer jwt_mock_admin_id_'));

      // Validate SharedPreferences storage
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auth_jwt_token'), true);
      expect(prefs.getString('auth_jwt_token'), startsWith('jwt_mock_admin_id_'));
    });

    test('Clears JWT token on logout', () async {
      apiClient.mockHandler = (request) {
        if (request.url.path.contains('/auth/login')) {
          return ApiResponse(
            statusCode: 200,
            body: '{"access_token": "jwt_mock_admin_id_xyz", "refresh_token": "mock_refresh", "user": {"id": "admin_id", "name": "Admin User", "email": "admin@serenut.com", "role": "admin"}}',
            headers: const {},
          );
        }
        return ApiResponse(
          statusCode: 200,
          body: '{"has_auth": ${request.headers.containsKey('Authorization')}}',
          headers: const {},
        );
      };

      // Login first
      await authService.login('admin@serenut.com', 'admin123');
      var response = await apiClient.get('/dummy');
      expect(response.json['has_auth'], true);

      // Perform logout
      await authService.logout();

      // Token must be cleared
      response = await apiClient.get('/dummy');
      expect(response.json['has_auth'], false);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auth_jwt_token'), false);
    });

    test('Restores token on initialization', () async {
      SharedPreferences.setMockInitialValues({
        'auth_jwt_token': 'jwt_mock_restored_12345',
      });

      final localService = AuthService(
        userRepository: userRepo,
        hashService: hashService,
        apiClient: apiClient,
      );

      apiClient.mockHandler = (request) {
        return ApiResponse(
          statusCode: 200,
          body: '{"auth_header": "${request.headers['Authorization']}"}',
          headers: const {},
        );
      };

      await localService.initialize();

      final response = await apiClient.get('/dummy');
      expect(response.json['auth_header'], 'Bearer jwt_mock_restored_12345');
    });
  });
}
