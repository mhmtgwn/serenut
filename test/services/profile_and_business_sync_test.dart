import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/services/device_manager.dart';

class MockUserRepository implements IUserRepository {
  final Map<String, AuthUser> _users = {};

  void addUser(AuthUser user) {
    _users[user.id] = user;
    _users[user.name] = user;
  }

  @override
  Future<void> updateUserFields(AuthUser user, {bool? isActive, String? passwordHash, String? username, String? businessCode, String? pinHash, int? deviceTokenVersion}) async {
    _users[user.id] = user;
  }

  @override
  Future<AuthUser?> findById(dynamic id) async => _users[id];

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profile Name and Cashier Display Tests', () {
    late AuthService authService;
    late MockUserRepository userRepo;
    late MockHashService hashService;
    late DeviceManager deviceManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      userRepo = MockUserRepository();
      hashService = MockHashService();
      deviceManager = DeviceManager(prefs);

      authService = AuthService(
        userRepository: userRepo,
        hashService: hashService,
        deviceManager: deviceManager,
      );
      await authService.initialize();

      final testUser = AuthUser(
        id: 'user-test-1',
        name: 'Mehmet Güven',
        email: 'mehmet@example.com',
        role: UserRole.owner,
        permissions: ['*'],
        createdAt: DateTime.now(),
      );

      await authService.setCurrentUser(testUser);
      userRepo.addUser(testUser);
    });

    test('updateProfileName should update current user name and persist', () async {
      final userBefore = await authService.getCurrentUser();
      expect(userBefore?.name, equals('Mehmet Güven'));

      AuthUser? notifiedUser;
      authService.onUserUpdatedCallback = (user) {
        notifiedUser = user;
      };

      await authService.updateProfileName('Kasa 1 (Ahmet)');

      final userAfter = await authService.getCurrentUser();
      expect(userAfter?.name, equals('Kasa 1 (Ahmet)'));
      expect(notifiedUser?.name, equals('Kasa 1 (Ahmet)'));
    });

    test('updateProfileName ignores empty or whitespace names', () async {
      await authService.updateProfileName('   ');
      final userAfter = await authService.getCurrentUser();
      expect(userAfter?.name, equals('Mehmet Güven'));
    });
  });

  group('Business Profile Sync Protection Tests', () {
    test('copyWith preserves customized businessName when remote is default Serenut OS', () {
      final current = Settings(
        businessName: 'Bizim Kasap',
        businessPhone: '+90 555 111 2233',
        businessAddress: 'Merkez Mah.',
        currency: '₺',
        printerPort: 9100,
        paperWidth: 80,
        printReceipt: true,
        printQRCode: false,
        printProductDetails: true,
        printBarcode: false,
        printCopies: 1,
        vatCategories: '[]',
        smsEnabled: false,
        qrEnabled: false,
        qrFormat: 'type|id|timestamp|customerId|amount|hash',
        debugMode: false,
        createdAt: DateTime.now(),
      );

      const remoteName = 'Serenut OS';
      final shouldKeepLocal = current.businessName.isNotEmpty &&
          current.businessName != 'Serenut OS' &&
          (remoteName.isEmpty || remoteName == 'Serenut OS');

      expect(shouldKeepLocal, isTrue);

      final updated = current.copyWith(
        businessName: shouldKeepLocal ? current.businessName : remoteName,
      );

      expect(updated.businessName, equals('Bizim Kasap'));
    });
  });
}
