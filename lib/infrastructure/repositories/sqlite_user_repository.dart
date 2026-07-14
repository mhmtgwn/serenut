import 'dart:async';
import 'dart:convert';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class SqliteUserRepository implements IUserRepository {
  final DbGateway _gateway;

  SqliteUserRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  AuthUser _mapRowToAuthUser(Map<String, dynamic> row) {
    final roleStr = row['role'] as String;
    final role = UserRole.values.firstWhere(
      (r) => r.name == roleStr.toLowerCase(),
      orElse: () => UserRole.cashier,
    );
    return AuthUser(
      id: row['id'] as String,
      name: row['name'] as String,
      email: row['email'] as String? ?? '',
      username: row['username'] as String?,
      pin: row['pin_hash'] as String?,
      businessCode: row['business_code'] as String?,
      role: role,
      permissions: row['permissions'] != null
          ? List<String>.from(jsonDecode(row['permissions'] as String))
          : Permission.forRole(role).map((p) => p.value).toList(),
      createdAt: DateTime.parse(
        (row['created_at'] ?? DateTime.now().toIso8601String()) as String,
      ),
    );
  }

  @override
  Future<List<AuthUser>> findAll() async {
    final rows = await _executor.query('users', orderBy: 'name ASC');
    return rows.map((r) => _mapRowToAuthUser(r)).toList();
  }

  @override
  Future<AuthUser?> findById(dynamic id) async {
    final rows =
        await _executor.query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _mapRowToAuthUser(rows.first);
  }

  @override
  Future<AuthUser?> findByUsername(String username) async {
    final rows = await _executor.query(
      'users',
      where: '(email = ? OR name = ?) AND is_active = 1',
      whereArgs: [username.trim(), username.trim()],
    );
    if (rows.isEmpty) return null;
    return _mapRowToAuthUser(rows.first);
  }

  @override
  Future<String?> getPasswordHash(String userId) async {
    final rows = await _executor.query(
      'users',
      columns: ['password_hash'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (rows.isEmpty) return null;
    return rows.first['password_hash'] as String?;
  }

  @override
  Future<void> updateLastLogin(String userId) async {
    await _executor.update(
      'users',
      {'last_login': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  @override
  Future<void> updatePasswordHash(String userId, String passwordHash) async {
    await _executor.update(
      'users',
      {
        'password_hash': passwordHash,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  @override
  Future<void> insertUser(
    AuthUser user,
    String passwordHash, {
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  }) async {
    await _executor.insert('users', {
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'password_hash': passwordHash,
      'role': user.role.name,
      'is_active': 1,
      'created_at': user.createdAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      if (username != null) 'username': username,
      if (pinHash != null) 'pin_hash': pinHash,
      if (businessCode != null) 'business_code': businessCode,
      if (deviceTokenVersion != null)
        'device_token_version': deviceTokenVersion,
      'permissions': jsonEncode(user.permissions),
    });
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
    final Map<String, dynamic> values = {
      'name': user.name,
      'email': user.email,
      'role': user.role.name,
      'updated_at': DateTime.now().toIso8601String(),
      'permissions': jsonEncode(user.permissions),
    };
    if (passwordHash != null) {
      values['password_hash'] = passwordHash;
    }
    if (isActive != null) {
      values['is_active'] = isActive ? 1 : 0;
    }
    if (username != null) {
      values['username'] = username;
    }
    if (pinHash != null) {
      values['pin_hash'] = pinHash;
    }
    if (businessCode != null) {
      values['business_code'] = businessCode;
    }
    if (deviceTokenVersion != null) {
      values['device_token_version'] = deviceTokenVersion;
    }
    await _executor
        .update('users', values, where: 'id = ?', whereArgs: [user.id]);
  }

  @override
  Future<int> create(AuthUser user) async {
    await insertUser(user, '');
    return 1;
  }

  @override
  Future<int> update(AuthUser user) async {
    await updateUserFields(user);
    return 1;
  }

  @override
  Future<int> delete(dynamic id) async {
    return await _executor.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> count() async {
    final rows =
        await _executor.rawQuery('SELECT COUNT(*) as count FROM users');
    if (rows.isEmpty) return 0;
    return rows.first['count'] as int? ?? 0;
  }

  @override
  Future<bool> exists(dynamic id) async {
    final user = await findById(id);
    return user != null;
  }

  @override
  Future<AuthUser?> findByBusinessCodeAndUsername(
      String businessCode, String username) async {
    final rows = await _executor.query(
      'users',
      where: 'business_code = ? AND username = ? AND is_active = 1',
      whereArgs: [businessCode.trim().toUpperCase(), username.trim()],
    );
    if (rows.isEmpty) return null;
    return _mapRowToAuthUser(rows.first);
  }

  @override
  Future<Map<String, String?>> getCredentialHashes(String userId) async {
    final rows = await _executor.query(
      'users',
      columns: ['password_hash', 'pin_hash'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (rows.isEmpty) return {};
    return {
      'password_hash': rows.first['password_hash'] as String?,
      'pin_hash': rows.first['pin_hash'] as String?,
    };
  }

  // ── Brute-Force Lockout ───────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getFailedPinAttempts(String userId) async {
    final rows = await _executor.query(
      'users',
      columns: ['failed_pin_attempts', 'locked_until'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (rows.isEmpty) return {'failed_pin_attempts': 0, 'locked_until': null};
    return {
      'failed_pin_attempts': rows.first['failed_pin_attempts'] as int? ?? 0,
      'locked_until': rows.first['locked_until'] as String?,
    };
  }

  @override
  Future<void> incrementFailedPinAttempts(String userId,
      {int lockoutMinutes = 5, int maxAttempts = 5}) async {
    final current = await getFailedPinAttempts(userId);
    final newCount = ((current['failed_pin_attempts'] as int?) ?? 0) + 1;
    final values = <String, dynamic>{
      'failed_pin_attempts': newCount,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (newCount >= maxAttempts) {
      values['locked_until'] = DateTime.now()
          .add(Duration(minutes: lockoutMinutes))
          .toIso8601String();
    }
    await _executor
        .update('users', values, where: 'id = ?', whereArgs: [userId]);
  }

  @override
  Future<void> resetPinAttempts(String userId) async {
    await _executor.update(
      'users',
      {
        'failed_pin_attempts': 0,
        'locked_until': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
}
