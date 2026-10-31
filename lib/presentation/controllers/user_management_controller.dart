import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/providers/auth/auth_providers.dart';
import 'package:serenutos/providers/service_providers.dart';

final userManagementControllerProvider = Provider<UserManagementController>((ref) {
  return UserManagementController(ref);
});

class UserManagementController {
  final Ref _ref;

  UserManagementController(this._ref);

  Future<List<AuthUser>> getUsers() async {
    final authService = _ref.read(authServiceProvider);
    return await authService.getUsers();
  }

  Future<void> createUser(
    AuthUser user,
    String password, {
    String? pin,
  }) async {
    final authService = _ref.read(authServiceProvider);
    await authService.createUser(user, password, pin: pin);

    try {
      _ref.read(auditLogServiceProvider).log(
            action: 'user_created',
            details: '{"id":"${user.id}","name":"${user.name}","role":"${user.role.name}"}',
          );
    } catch (_) {
      // Audit log hatası kullanıcı eklemeyi engellemez
    }
  }

  Future<void> updateUser(
    AuthUser user, {
    String? password,
    String? pin,
    bool? isActive,
  }) async {
    final authService = _ref.read(authServiceProvider);
    await authService.updateUser(
      user,
      password: password,
      pin: pin,
      isActive: isActive,
    );

    try {
      _ref.read(auditLogServiceProvider).log(
            action: 'user_updated',
            details: '{"id":"${user.id}","name":"${user.name}","role":"${user.role.name}"}',
          );
    } catch (_) {
      // Audit log hatası kullanıcı güncellemeyi engellemez
    }
  }

  Future<void> deleteUser(String userId) async {
    final authService = _ref.read(authServiceProvider);
    await authService.deleteUser(userId);

    try {
      _ref.read(auditLogServiceProvider).log(
            action: 'user_deleted',
            details: '{"id":"$userId"}',
          );
    } catch (_) {
      // Audit log hatası işlemi engellemez
    }
  }
}

