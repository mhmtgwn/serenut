// lib/domain/services/auth_service.dart
// PHASE 0 - Auth Contract (Day 1 — Security Hardened: 24 Jun 2026)
// SQLite + SharedPreferences implementation with PBKDF2-HMAC-SHA256 hashing

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/domain/models/permission.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/i_hash_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String _userStorageKey = 'auth_user_json';

  final IUserRepository _userRepository;
  final IHashService _hashService;
  final ApiClient? _apiClient;
  late SharedPreferences _prefs;
  AuthUser? _currentUser;

  AuthService({
    required IUserRepository userRepository,
    required IHashService hashService,
    ApiClient? apiClient,
  })  : _userRepository = userRepository,
        _hashService = hashService,
        _apiClient = apiClient;

  /// Initialize service (call once on app startup)
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadStoredUser();
    
    // Restore JWT token to ApiClient if exists
    final savedToken = _prefs.getString('auth_jwt_token');
    _apiClient?.setJwtToken(savedToken);

    if (_apiClient != null) {
      _apiClient!.onTokenExpired = () async {
        return await refreshToken();
      };
      _apiClient!.onSessionExpired = () {
        triggerSessionExpired();
      };
    }
  }

  /// Load user from local storage if exists
  Future<void> _loadStoredUser() async {
    final userJson = _prefs.getString(_userStorageKey);
    if (userJson != null) {
      try {
        final user = AuthUser.fromJson(userJson);
        final lastVerifiedStr = _prefs.getString('serenut_last_authz_verified_at_${user.id}');
        if (lastVerifiedStr != null) {
          // Lease check removed from here to allow offline POS sales.
        }
        _currentUser = user;
      } catch (e) {
        // Corrupt or outdated session — clear it
        await _prefs.remove(_userStorageKey);
        _currentUser = null;
      }
    }
  }

  // ════════════════════════════════════════════════════════════
  // LOGIN — Secure PBKDF2 verification
  // ════════════════════════════════════════════════════════════

  /// Login with username (email or name) and password.
  ///
  /// Security notes:
  /// - Uses PBKDF2-HMAC-SHA256 for hash verification.
  /// - Supports legacy hashes from old system and rehashes on successful login.
  /// - Does NOT fall back to username == password (removed exploit).
  Future<AuthUser> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw AuthException('Kullanıcı adı ve şifre boş olamaz.');
    }

    // Try online login first if API client is available
    if (_apiClient != null) {
      try {
        final response = await _apiClient!.post('/auth/login', {
          'email': username.trim(),
          'password': password,
        });
        
        if (response.isSuccess) {
          final data = response.json;
          final token = data['access_token'] as String;
          final refreshToken = data['refresh_token'] as String;
          final userMap = data['user'] as Map<String, dynamic>;

          await _prefs.setString('auth_jwt_token', token);
          await _prefs.setString('auth_refresh_token', refreshToken);
          _apiClient!.setJwtToken(token);

          // Synchronize trial starting date from server (AC 1.2)
          final trialManager = TrialManager(_prefs);
          final trialStartedAtStr = data['trial_started_at'] as String?;
          if (trialStartedAtStr != null) {
            final trialStartedAt = DateTime.tryParse(trialStartedAtStr);
            if (trialStartedAt != null) {
              await trialManager.startTrial(trialStartedAt);
            }
          } else if (data['trial_started'] == true) {
            await trialManager.startTrial(DateTime.now());
          }

          final roles = userMap['roles'] as List<dynamic>? ?? [];
          final roleStr = roles.isNotEmpty ? roles.first.toString() : (userMap['role'] as String? ?? 'cashier');
          final role = UserRole.values.firstWhere(
            (r) => r.name == roleStr.toLowerCase(),
            orElse: () => UserRole.cashier,
          );
          
          final user = AuthUser(
            id: userMap['id'] as String,
            companyId: userMap['company_id'] as String? ?? 'TEST_COMPANY',
            name: userMap['name'] as String,
            email: userMap['email'] as String? ?? '',
            role: role,
            permissions: getPermissionsForRole(role),
            createdAt: DateTime.tryParse(userMap['created_at'] as String? ?? '') ?? DateTime.now(),
          );

          // Cache credentials in local sqlite for offline login
          try {
            final hash = _hashService.hashPassword(password);
            await _userRepository.insertUser(user, hash);
          } catch (_) {
            try {
              final hash = _hashService.hashPassword(password);
              await _userRepository.updateUserFields(user, isActive: true, passwordHash: hash);
            } catch (_) {}
          }

          _currentUser = user;
          await _prefs.setString(_userStorageKey, user.toJson());
          await _prefs.setString('serenut_last_authz_verified_at_${user.id}', DateTime.now().toUtc().toIso8601String());
          return user;
        }
      } catch (e) {
        if (e is ApiException) {
          if (e.statusCode == 400 || e.statusCode == 401 || e.statusCode == 403) {
            final body = e.responseBody;
            String message = 'Giriş başarısız.';
            if (body != null) {
              try {
                message = jsonDecode(body)['message'] ?? message;
              } catch (_) {}
            }
            throw AuthException(message);
          }
        }
        // Network timeout / DNS resolution issues — fall back to offline DB check
      }
    }

    // Not: kIsWeb hardcode kullanıcı bloğu kaldırıldı (güvenlik açığı).
    // Web'de de backend API çağrısı yapılır (satır 99-174 yukarıda).
    // Backend erişilemiyorsa local SQLite'a düşülür (aşağıdaki blok).
    // kIsWeb + local SQLite sorgusu: web'de SQLite çalışmaz, hata fırlatır
    // → throw AuthException ile sonuçlanır, bu doğru davranış.

    try {
      final user = await _userRepository.findByUsername(username.trim());
      if (user != null) {
        final hash = await _userRepository.getPasswordHash(user.id);
        if (hash != null) {
          final isValid = _hashService.verifyPassword(password, hash);

          if (isValid) {
            final lastVerifiedStr = _prefs.getString('serenut_last_authz_verified_at_${user.id}');
            if (lastVerifiedStr != null) {
              final lastVerified = DateTime.parse(lastVerifiedStr);
              if (DateTime.now().toUtc().difference(lastVerified).inDays >= 7) {
                throw AuthException('Güvenlik nedeniyle (offline policy) 7 günde bir çevrimiçi giriş yapmalısınız.');
              }
            } else {
              throw AuthException('Çevrimdışı giriş için önceden senkronizasyon gereklidir.');
            }

            await _onLoginSuccess(user);

            // Rehash on first login if legacy format detected
            if (_hashService.isLegacyHash(hash)) {
              await _rehashPassword(user.id, password);
            }

            // Update last_login timestamp
            await _userRepository.updateLastLogin(user.id);

            return user;
          }
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
    }

    throw AuthException('Kullanıcı adı veya şifre hatalı.');
  }

  /// Login sub-user (cashier, manager, staff) using business_code, username, and PIN.
  /// Enforces online lookup with automatic local SQLite cache and offline fallback.
  Future<AuthUser> loginSubUser(String businessCode, String username, String pin) async {
    if (businessCode.trim().isEmpty || username.trim().isEmpty || pin.isEmpty) {
      throw AuthException('İşletme kodu, kullanıcı adı ve PIN boş olamaz.');
    }

    // Try online path first
    if (_apiClient != null) {
      try {
        final response = await _apiClient!.post('/auth/login/sub', {
          'business_code': businessCode.trim().toUpperCase(),
          'username': username.trim(),
          'pin': pin,
        });

        if (response.isSuccess) {
          final data = response.json;
          final token = (data['access_token'] ?? data['accessToken']) as String;
          final refreshToken = (data['refresh_token'] ?? data['refreshToken']) as String;
          final userMap = data['user'] as Map<String, dynamic>;

          await _prefs.setString('auth_jwt_token', token);
          await _prefs.setString('auth_refresh_token', refreshToken);
          _apiClient!.setJwtToken(token);

          final roles = userMap['roles'] as List<dynamic>? ?? [];
          final roleStr = roles.isNotEmpty ? roles.first.toString() : 'cashier';
          final role = UserRole.values.firstWhere(
            (r) => r.name == roleStr.toLowerCase(),
            orElse: () => UserRole.cashier,
          );

          final user = AuthUser(
            id: userMap['id'] as String,
            companyId: userMap['company_id'] as String? ?? 'TEST_COMPANY',
            name: userMap['name'] as String,
            email: userMap['email'] as String? ?? '',
            role: role,
            permissions: getPermissionsForRole(role),
            createdAt: DateTime.now(),
          );

          // Cache credentials in local sqlite for offline login
          try {
            final hashedPin = _hashService.hashPassword(pin);
            await _userRepository.insertUser(
              user,
              '', // no password
              username: username.trim(),
              pinHash: hashedPin,
              businessCode: businessCode.trim().toUpperCase(),
            );
          } catch (_) {
            try {
              final hashedPin = _hashService.hashPassword(pin);
              await _userRepository.updateUserFields(
                user,
                isActive: true,
                username: username.trim(),
                pinHash: hashedPin,
                businessCode: businessCode.trim().toUpperCase(),
              );
            } catch (_) {}
          }

          _currentUser = user;
          await _prefs.setString(_userStorageKey, user.toJson());
          await _prefs.setString('serenut_last_authz_verified_at_${user.id}', DateTime.now().toUtc().toIso8601String());
          return user;
        }
      } catch (e) {
        if (e is ApiException) {
          if (e.statusCode == 400 || e.statusCode == 401 || e.statusCode == 403) {
            final body = e.responseBody;
            String message = 'Giriş başarısız.';
            if (body != null) {
              try {
                message = jsonDecode(body)['message'] ?? message;
              } catch (_) {}
            }
            throw AuthException(message);
          }
        }
        // Network timeout / DNS resolution issues — fall back to offline DB check
      }
    }

    // Offline path fallback
    try {
      final user = await _userRepository.findByBusinessCodeAndUsername(
        businessCode.trim(),
        username.trim(),
      );
      if (user != null) {
        // Check brute-force lockout
        final lockoutData = await _userRepository.getFailedPinAttempts(user.id);
        final lockedUntilStr = lockoutData['locked_until'] as String?;
        if (lockedUntilStr != null) {
          final lockedUntil = DateTime.tryParse(lockedUntilStr);
          if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
            final remaining = lockedUntil.difference(DateTime.now()).inSeconds;
            throw AuthException('Hesap çok fazla başarısız deneme nedeniyle kilitlendi. Lütfen $remaining saniye bekleyin.');
          }
        }

        final hashes = await _userRepository.getCredentialHashes(user.id);
        final pinHash = hashes['pin_hash'];
        if (pinHash != null) {
          final isValid = _hashService.verifyPassword(pin, pinHash);
          if (isValid) {
            final lastVerifiedStr = _prefs.getString('serenut_last_authz_verified_at_${user.id}');
            // Lease check removed from here to allow offline POS sales.
            await _userRepository.resetPinAttempts(user.id);
            await _onLoginSuccess(user);
            await _userRepository.updateLastLogin(user.id);
            return user;
          } else {
            await _userRepository.incrementFailedPinAttempts(user.id);
            final updated = await _userRepository.getFailedPinAttempts(user.id);
            final attempts = updated['failed_pin_attempts'] as int? ?? 0;
            final remainingAttempts = 5 - attempts;
            if (remainingAttempts <= 0) {
              throw AuthException('Çok fazla başarısız deneme. Hesap 5 dakika süreyle kilitlendi.');
            } else {
              throw AuthException('İşletme kodu, kullanıcı adı veya PIN hatalı. Kalan deneme hakkı: $remainingAttempts');
            }
          }
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
    }

    throw AuthException('İşletme kodu, kullanıcı adı veya PIN hatalı.');
  }

  /// Verifies a sub-user PIN for the currently logged-in user or an admin/manager.
  /// Used for gated action verification with brute-force lockout.
  Future<({bool success, String? approverUserId, String? approverUserName})> verifyCurrentUserPin(String pin) async {
    final user = await getCurrentUser();
    if (user == null) {
      return (success: false, approverUserId: null, approverUserName: null);
    }

    // Offline lease check for admin-gated actions
    final lastVerifiedStr = _prefs.getString('serenut_last_authz_verified_at_${user.id}');
    if (lastVerifiedStr != null) {
      final lastVerified = DateTime.tryParse(lastVerifiedStr);
      final leaseDays = _prefs.getInt('offline_auth_lease_days') ?? 7;
      if (lastVerified != null && DateTime.now().toUtc().difference(lastVerified).inDays > leaseDays) {
        throw AuthException('Oturum süresi (offline lease) dolmuştur. Hassas yetkili işlemler için lütfen internete bağlanın.');
      }
    }

    // Check brute-force lockout first
    final lockoutData = await _userRepository.getFailedPinAttempts(user.id);
    final lockedUntilStr = lockoutData['locked_until'] as String?;
    if (lockedUntilStr != null) {
      final lockedUntil = DateTime.tryParse(lockedUntilStr);
      if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
        return (success: false, approverUserId: null, approverUserName: null);
      }
    }

    final hashes = await _userRepository.getCredentialHashes(user.id);
    final pinHash = hashes['pin_hash'];
    bool isValid = false;

    if (pinHash != null && pinHash.isNotEmpty) {
      isValid = _hashService.verifyPassword(pin, pinHash);
    } else {
      // Fallback to password hash if PIN is not configured
      final passwordHash = hashes['password_hash'];
      if (passwordHash != null && passwordHash.isNotEmpty) {
        isValid = _hashService.verifyPassword(pin, passwordHash);
      }
    }

    if (isValid) {
      await _userRepository.resetPinAttempts(user.id);
      return (success: true, approverUserId: user.id, approverUserName: user.name);
    } else {
      await _userRepository.incrementFailedPinAttempts(user.id);
      return (success: false, approverUserId: null, approverUserName: null);
    }
  }

  /// Rehash a legacy password with PBKDF2 after successful login.
  Future<void> _rehashPassword(String userId, String password) async {
    try {
      final newHash = _hashService.hashPassword(password);
      await _userRepository.updatePasswordHash(userId, newHash);
    } catch (_) {
      // Non-fatal — user can still log in with legacy hash next time
    }
  }

  // ════════════════════════════════════════════════════════════
  // SESSION
  // ════════════════════════════════════════════════════════════

  /// Get current logged-in user
  Future<AuthUser?> getCurrentUser() async {
    if (_currentUser == null) {
      await _loadStoredUser();
    }
    return _currentUser;
  }

  /// Get the current JWT token
  String? getJwtToken() {
    return _prefs.getString('auth_jwt_token');
  }

  /// Get the current Refresh token
  String? getRefreshToken() {
    return _prefs.getString('auth_refresh_token');
  }

  /// Refresh the access token using the saved refresh token
  Future<bool> refreshToken() async {
    final rToken = getRefreshToken();
    if (rToken == null || _apiClient == null) return false;

    try {
      final response = await _apiClient!.post('/auth/refresh', {
        'refresh_token': rToken,
      });

      if (response.isSuccess) {
        final data = response.json;
        final token = data['access_token'] as String;
        final newRToken = data['refresh_token'] as String;

        await _prefs.setString('auth_jwt_token', token);
        await _prefs.setString('auth_refresh_token', newRToken);
        _apiClient!.setJwtToken(token);
        return true;
      }
    } on ApiException catch (e) {
      // 400/401/403 are permanent authentication failures (stale token, session revoked, replay attack)
      if (e.statusCode == 400 || e.statusCode == 401 || e.statusCode == 403) {
        return false;
      }
      rethrow;
    } catch (_) {
      rethrow;
    }
    return false;
  }

  /// Logout — clears session
  Future<void> logout() async {
    _currentUser = null;
    await _prefs.remove(_userStorageKey);
    await _prefs.remove('auth_jwt_token');
    await _prefs.remove('auth_refresh_token');
    _apiClient?.setJwtToken(null);
  }

  void Function()? onSessionExpiredCallback;
  void Function(AuthUser user)? onUserUpdatedCallback;

  void triggerSessionExpired() {
    logout();
    if (onSessionExpiredCallback != null) {
      onSessionExpiredCallback!();
    }
  }

  Future<void> checkCurrentUserSessionOnline() async {
    if (_currentUser == null || _apiClient == null || _apiClient!.jwtToken == null) return;
    try {
      final response = await _apiClient!.get('/auth/me');
      if (response.statusCode == 200) {
        await _prefs.setString('serenut_last_authz_verified_at_${_currentUser!.id}', DateTime.now().toUtc().toIso8601String());
        final data = response.json;
        final userMap = data['user'] as Map<String, dynamic>;
        
        final isActive = userMap['is_active'] as bool? ?? true;
        if (!isActive) {
          triggerSessionExpired();
          return;
        }

        final roles = userMap['roles'] as List<dynamic>? ?? [];
        final roleStr = roles.isNotEmpty ? roles.first.toString() : (userMap['role'] as String? ?? 'cashier');
        final role = UserRole.values.firstWhere(
          (r) => r.name == roleStr.toLowerCase(),
          orElse: () => UserRole.cashier,
        );

        if (role != _currentUser!.role) {
          final updatedUser = _currentUser!.copyWith(
            role: role,
            permissions: getPermissionsForRole(role),
          );
          _currentUser = updatedUser;
          await _prefs.setString(_userStorageKey, updatedUser.toJson());
          await _userRepository.updateUserFields(updatedUser);
          if (onUserUpdatedCallback != null) {
            onUserUpdatedCallback!(updatedUser);
          }
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        triggerSessionExpired();
      }
    } catch (_) {
      // Offline fallback: keep cached credentials
    }
  }

  /// Offline login başarısında çağrılır.
  /// NOT: JWT token burada üretilmez — offline session JWT'siz çalışır.
  /// Gerçek JWT yalnızca backend login başarısında (satır 108-157) set edilir.
  Future<void> _onLoginSuccess(AuthUser user) async {
    _currentUser = user;
    await _prefs.setString(_userStorageKey, user.toJson());
    // Offline durumda API çağrılarına gerek yok;
    // token null kalır → sync geldiğinde yeniden login istenir
  }

  /// Directly set the current authenticated user — used after setup (Web)
  Future<void> setCurrentUser(AuthUser user) async {
    _currentUser = user;
    await _prefs.setString(_userStorageKey, user.toJson());
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    return user != null;
  }

  /// Şifre sıfırlama isteği gönder (backend e-posta akışı)
  /// 
  /// Backend POST /auth/forgot-password çağırır.
  /// Network yoksa veya backend hata verirse silent fail —
  /// güvenlik gereği kullanıcıya her zaman başarı gösterilir.
  Future<void> requestPasswordReset(String email) async {
    if (_apiClient == null) return;
    try {
      await _apiClient!.post('/auth/forgot-password', {'email': email});
    } catch (_) {
      // Silent fail — enumeration önlemi için UI her zaman başarı gösterir
    }
  }

  bool _isLeaseExpired(AuthUser user) {
    final lastVerifiedStr = _prefs.getString('serenut_last_authz_verified_at_${user.id}');
    if (lastVerifiedStr != null) {
      final lastVerified = DateTime.tryParse(lastVerifiedStr);
      final leaseDays = _prefs.getInt('offline_auth_lease_days') ?? 7;
      if (lastVerified != null && DateTime.now().toUtc().difference(lastVerified).inDays > leaseDays) {
        return true;
      }
    }
    return false;
  }

  Future<bool> hasPermission(String permission) async {
    final user = await getCurrentUser();
    if (user == null) return false;
    
    // Only allow cashier permissions if lease expired
    if (_isLeaseExpired(user) && !_getCashierPermissions().contains(permission)) {
      return false;
    }
    
    return user.hasPermission(permission);
  }

  /// Check if current user has all permissions
  Future<bool> hasAllPermissions(List<String> permissions) async {
    final user = await getCurrentUser();
    if (user == null) return false;
    
    if (_isLeaseExpired(user)) {
      final cashierPerms = _getCashierPermissions();
      if (!permissions.every((p) => cashierPerms.contains(p))) {
        return false;
      }
    }
    
    return user.hasAllPermissions(permissions);
  }

  /// Get all permission names for current user
  Future<List<String>> getAllPermissions() async {
    final user = await getCurrentUser();
    return user?.getAllPermissions() ?? [];
  }

  // ════════════════════════════════════════════════════════════
  // SQLite User Management CRUD
  // ════════════════════════════════════════════════════════════

  Future<List<AuthUser>> getUsers() async {
    if (kIsWeb) {
      return [
        AuthUser(
          id: 'user-admin',
          name: 'Admin',
          email: 'admin@serenut.com',
          role: UserRole.admin,
          permissions: getPermissionsForRole(UserRole.admin),
          createdAt: DateTime.now(),
        ),
        AuthUser(
          id: 'user-manager',
          name: 'Yönetici',
          email: 'yonetici@serenut.com',
          role: UserRole.manager,
          permissions: getPermissionsForRole(UserRole.manager),
          createdAt: DateTime.now(),
        ),
        AuthUser(
          id: 'user-cashier',
          name: 'Kasiyer',
          email: 'kasiyer@serenut.com',
          role: UserRole.cashier,
          permissions: getPermissionsForRole(UserRole.cashier),
          createdAt: DateTime.now(),
        ),
      ];
    }

    try {
      return await _userRepository.findAll();
    } catch (_) {
      return [];
    }
  }

  Future<void> createUser(AuthUser user, String password, {String? pin}) async {
    if (password.isEmpty) {
      throw AuthException('Şifre boş olamaz.');
    }
    String? pinHash;
    if (pin != null && pin.isNotEmpty) {
      pinHash = _hashService.hashPassword(pin);
    }
    await _userRepository.insertUser(
      user, 
      _hashService.hashPassword(password),
      username: user.username,
      businessCode: user.businessCode,
      pinHash: pinHash,
    );
  }

  Future<void> updateUser(
    AuthUser user, {
    String? password,
    String? pin,
    bool? isActive,
  }) async {
    String? passwordHash;
    if (password != null && password.isNotEmpty) {
      passwordHash = _hashService.hashPassword(password);
    }
    String? pinHash;
    if (pin != null && pin.isNotEmpty) {
      pinHash = _hashService.hashPassword(pin);
    }
    await _userRepository.updateUserFields(
      user, 
      isActive: isActive, 
      passwordHash: passwordHash,
      username: user.username,
      businessCode: user.businessCode,
      pinHash: pinHash,
    );
  }

  Future<void> deleteUser(String id) async {
    await _userRepository.delete(id);
  }

  /// Change password for a specific user.
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.isEmpty || newPassword.length < 6) {
      throw AuthException('Yeni şifre en az 6 karakter olmalıdır.');
    }
    final hash = await _userRepository.getPasswordHash(userId);
    if (hash == null) throw AuthException('Kullanıcı bulunamadı.');

    if (!_hashService.verifyPassword(currentPassword, hash)) {
      throw AuthException('Mevcut şifre hatalı.');
    }

    await _userRepository.updatePasswordHash(userId, _hashService.hashPassword(newPassword));
  }

  static List<String> getPermissionsForRole(UserRole role) => switch (role) {
        UserRole.owner   => _getAllPermissions(),
        UserRole.admin   => _getAllPermissions(),
        UserRole.sysadmin => _getAllPermissions(),
        UserRole.manager => _getManagerPermissions(),
        UserRole.cashier => _getCashierPermissions(),
        UserRole.staff   => _getCashierPermissions(),
      };

  // ════════════════════════════════════════════════════════════
  // Permission definitions (27 total)
  // ════════════════════════════════════════════════════════════

  static List<String> _getAllPermissions() => [
        'sales:view', 'sales:create', 'sales:edit', 'sales:delete', 'sales:print',
        'orders:view', 'orders:create', 'orders:edit', 'orders:deliver',
        'customers:view', 'customers:create', 'customers:edit', 'customers:delete',
        'payments:view', 'payments:record', 'payments:reverse',
        'inventory:view', 'inventory:adjust', 'inventory:transfer',
        'reports:view', 'reports:financial', 'reports:inventory',
        'admin:settings', 'admin:users',
      ];

  static List<String> _getManagerPermissions() => [
        'sales:view', 'sales:create', 'sales:print',
        'orders:view', 'orders:create', 'orders:edit', 'orders:deliver',
        'customers:view', 'customers:create', 'customers:edit',
        'payments:view', 'payments:record',
        'inventory:view', 'inventory:adjust', 'inventory:transfer',
        'reports:view', 'reports:financial', 'reports:inventory',
      ];

  static List<String> _getCashierPermissions() => [
        'sales:view', 'sales:create', 'sales:print',
        'payments:record',
        'customers:view',
      ];
}
