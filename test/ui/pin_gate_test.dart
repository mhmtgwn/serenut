import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/presentation/widgets/auth/pin_verification_dialog.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/services/auth_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class MockUserRepository implements IUserRepository {
  int attempts = 0;
  String? lockedUntil;

  @override
  Future<Map<String, dynamic>> getFailedPinAttempts(String userId) async {
    return {
      'failed_pin_attempts': attempts,
      'locked_until': lockedUntil,
    };
  }

  @override
  Future<void> incrementFailedPinAttempts(String userId,
      {int lockoutMinutes = 5, int maxAttempts = 5}) async {
    attempts++;
    if (attempts >= maxAttempts) {
      lockedUntil = DateTime.now()
          .add(Duration(minutes: lockoutMinutes))
          .toIso8601String();
    }
  }

  @override
  Future<void> resetPinAttempts(String userId) async {
    attempts = 0;
    lockedUntil = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockAuthService implements AuthService {
  final AuthUser mockUser;
  final MockUserRepository repo;
  bool verifyResult = false;

  MockAuthService(this.mockUser, this.repo);

  @override
  Future<AuthUser?> getCurrentUser() async => mockUser;

  @override
  Future<({bool success, String? approverUserId, String? approverUserName})>
      verifyCurrentUserPin(String pin) async {
    final lockout = await repo.getFailedPinAttempts(mockUser.id);
    if (lockout['locked_until'] != null) {
      return (success: false, approverUserId: null, approverUserName: null);
    }

    if (pin == '1234') {
      await repo.resetPinAttempts(mockUser.id);
      return (
        success: true,
        approverUserId: mockUser.id,
        approverUserName: mockUser.name
      );
    } else {
      await repo.incrementFailedPinAttempts(mockUser.id);
      return (success: false, approverUserId: null, approverUserName: null);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets(
      'PinVerificationDialog correctly handles inputs, wrong pins, lockout and success',
      (WidgetTester tester) async {
    final mockUser = AuthUser(
      id: 'admin_1',
      name: 'Test Admin',
      email: 'admin@shaman.com',
      role: UserRole.admin,
      permissions: [],
      createdAt: DateTime.now(),
    );

    final mockRepo = MockUserRepository();
    final mockAuth = MockAuthService(mockUser, mockRepo);

    // Set virtual screen size large enough to fit custom dialog components and prevent overflow
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    PinVerificationResult? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(mockAuth),
          userRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<PinVerificationResult>(
                      context: context,
                      builder: (context) => const PinVerificationDialog(
                        actionTitle: 'Test Action',
                        requireConfirm: true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      ),
    );

    // 1. Open dialog
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Yönetici Doğrulaması'), findsOneWidget);
    expect(find.text('Test Action'), findsOneWidget);

    // 2. Enter wrong pin (e.g. 1111) by tapping keypad buttons
    await tester.tap(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    // Verify it failed and attempts is 1
    expect(mockRepo.attempts, 1);
    expect(find.text('Hatalı PIN girdiniz. Kalan deneme: 4'), findsOneWidget);

    // 3. Enter wrong pin 4 more times to trigger lockout
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
    }

    // Verify lockout active
    expect(mockRepo.attempts, 5);
    expect(find.text('Çok fazla hatalı deneme! Cihaz kilitlendi.'),
        findsOneWidget);
    expect(find.textContaining('Güvenlik kilidi devrede'), findsOneWidget);

    // 4. Close dialog and reopen (simulating reopening during lockout)
    await tester.tap(find.text('İptal Et'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Should immediately show locked screen
    expect(find.textContaining('Güvenlik kilidi devrede'), findsOneWidget);

    // Bypass/reset lockout on repo to test success path
    await mockRepo.resetPinAttempts(mockUser.id);
    await tester.tap(find.text('İptal Et'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Tap numeric keys '1', '2', '3', '4' for correct PIN
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    // Since requireConfirm was true and checkbox not checked, it should display warning
    expect(
        find.textContaining(
            'Lütfen tehlikeli işlemi onay kutusunu işaretleyerek onaylayın'),
        findsOneWidget);

    // Check the confirmation checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Re-enter correct PIN
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    // Dialog should close with success result
    expect(find.text('Yönetici Doğrulaması'), findsNothing);
    expect(result, isNotNull);
    expect(result!.success, isTrue);
    expect(result!.userId, 'admin_1');
    expect(result!.userName, 'Test Admin');
  });
}
